import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';

import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/pages/about_page.dart';
import 'package:vce1_sakuraview/pages/blacklist_page.dart';
import 'package:vce1_sakuraview/pages/history_page.dart';
import 'package:vce1_sakuraview/pages/post_detail_page.dart';
import 'package:vce1_sakuraview/pages/search_page.dart';
import 'package:vce1_sakuraview/pages/site_accounts_page.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/providers/settings_provider.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/services/blacklist_service.dart';
import 'package:vce1_sakuraview/utils/settings_page.dart';
import 'package:vce1_sakuraview/utils/settings_service.dart';
import 'package:vce1_sakuraview/widgets/common/favorite_display_widget.dart';
import 'package:vce1_sakuraview/widgets/common/quick_search_drawer.dart';
import 'package:vce1_sakuraview/widgets/common/rating_filter_pill.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_drawer_swipe_region.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_loader.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_page_route.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_post_card.dart';
import 'package:vce1_sakuraview/widgets/drawer_widget.dart';

class WindowImageGridPage extends StatefulWidget {
  const WindowImageGridPage({super.key});

  @override
  WindowImageGridPageState createState() => WindowImageGridPageState();
}

class WindowImageGridPageState extends State<WindowImageGridPage> {
  static const double _wideRailBreakpoint = 860.0;

  List<Map<String, dynamic>> imageList = [];
  bool showFavoritesView = false;
  bool showSearchView = false;
  int currentPage = 1;
  final int imagesPerPage = 40;

  bool isLoading = false;
  bool _isDisposed = false;
  bool _hasMoreImages = true;
  String? _lastError;

  static final Logger _logger = Logger('WindowImageGridPage');
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  RatingFilterMode? _lastRatingFilter;
  String? _lastSourceId;

  @override
  void initState() {
    super.initState();
    _logger.info('WindowImageGridPageState initState');
    _scrollController.addListener(_onScroll);
    BlacklistService.instance.addListener(_onBlacklistChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) fetchImages(clear: true);
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    BlacklistService.instance.removeListener(_onBlacklistChanged);
    _logger.info('WindowImageGridPageState disposed');
    super.dispose();
  }

  void _onBlacklistChanged() {
    if (!mounted) return;
    final blacklist = BlacklistService.instance;
    if (imageList.isNotEmpty) {
      setState(() {
        imageList.removeWhere(blacklist.isPostBlocked);
      });
    }
    if (imageList.isEmpty && !isLoading) {
      fetchImages(clear: true);
    }
  }

  void _onScroll() {
    if (showFavoritesView ||
        showSearchView ||
        isLoading ||
        !_hasMoreImages ||
        !_scrollController.hasClients) {
      return;
    }
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll > 0 &&
        currentScroll > 160 &&
        currentScroll >= maxScroll - 800) {
      fetchImages();
    }
  }

  Future<void> fetchImages({bool clear = false}) async {
    if (clear) {
      setState(() {
        imageList.clear();
        currentPage = 1;
        _hasMoreImages = true;
        _lastError = null;
      });
    }
    if (isLoading || !mounted) return;

    setState(() {
      isLoading = true;
      _lastError = null;
    });

    try {
      final siteConfig = Provider.of<SiteConfigProvider>(context, listen: false);
      _lastRatingFilter = siteConfig.ratingFilter;
      _lastSourceId = siteConfig.currentSourceId;
      final ratingFilter = siteConfig.ratingFilter;
      final apiClient = siteConfig.apiClient;

      final fetchedPosts = await apiClient.searchPosts(
        page: currentPage,
        limit: imagesPerPage,
        safeMode: siteConfig.safeMode,
        ratingFilter: ratingFilter,
      );

      final blacklist = BlacklistService.instance;
      final incomingMaps = fetchedPosts
          .map((p) => p.toApiMap(siteName: siteConfig.currentSourceId))
          .where((item) =>
              !blacklist.isPostBlocked(item) && ratingFilter.matchesPost(item))
          .toList();
      final previousCount = imageList.length;
      final merged = PostGroupHelper.mergeAndDeduplicate(imageList, incomingMaps);

      if (!_isDisposed && mounted) {
        setState(() {
          if (fetchedPosts.isEmpty) {
            _hasMoreImages = false;
          } else {
            _hasMoreImages = true;
            imageList = merged;
            currentPage++;
          }
          isLoading = false;
        });
        if (fetchedPosts.isNotEmpty && merged.length > previousCount) {
          final width = MediaQuery.sizeOf(context).width;
          final gridPreset =
              SettingsProvider.maybeOf(context, listen: false)?.gridSizePreset ??
                  GridSizePreset.standard;
          final cols = gridPreset.calcColumns(width, isLandscape: true);
          final tileCacheWidth = computeGridTileCacheWidth(
            context,
            columns: cols,
          );
          final newlyAdded = merged.sublist(previousCount);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              prefetchPostThumbnails(
                context,
                newlyAdded,
                cacheWidth: tileCacheWidth,
              );
            }
          });
        }
      }
    } catch (e) {
      _logger.severe('Error fetching images: $e');
      if (!_isDisposed && mounted) {
        final msg = e.toString().replaceFirst('ApiException: ', '');
        setState(() {
          isLoading = false;
          _hasMoreImages = false;
          _lastError = msg;
        });
        if (imageList.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
      }
    }
  }

  void handleRatingFilterChanged(RatingFilterMode mode) {
    if (!mounted) return;
    Provider.of<SiteConfigProvider>(context, listen: false)
        .setRatingFilter(mode);
    fetchImages(clear: true);
  }

  void handleSafeModeChanged(bool value) {
    handleRatingFilterChanged(
      value ? RatingFilterMode.safe : RatingFilterMode.all,
    );
  }

  void handleSiteChanged(String sourceId) {
    if (!mounted) return;
    Provider.of<SiteConfigProvider>(context, listen: false)
        .setSourceById(sourceId);
    fetchImages(clear: true);
  }

  void handleHomeTapped() {
    if (!mounted) return;
    setState(() {
      showFavoritesView = false;
      showSearchView = false;
    });
    fetchImages(clear: true);
  }

  void _selectHomeTab() {
    if (!mounted) return;
    setState(() {
      showFavoritesView = false;
      showSearchView = false;
    });
    if (imageList.isEmpty && !isLoading) {
      fetchImages(clear: true);
    }
  }

  void _selectSearchTab() {
    if (!mounted) return;
    setState(() {
      showFavoritesView = false;
      showSearchView = true;
    });
  }

  void handleFavoritesTapped() {
    if (!mounted) return;
    setState(() {
      showFavoritesView = true;
      showSearchView = false;
    });
  }

  void handleDownloadsTapped() {
    if (!mounted) return;
    Navigator.pushNamed(context, '/downloads');
  }

  void handleSettingsTapped() {
    if (!mounted) return;
    Navigator.push(
      context,
      SakuraPageRoute(builder: (context) => const SettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeIndex = showFavoritesView ? 2 : (showSearchView ? 1 : 0);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f5): () {
          if (!showFavoritesView && !showSearchView && !isLoading) {
            fetchImages(clear: true);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () {
          if (!showFavoritesView && !showSearchView && !isLoading) {
            fetchImages(clear: true);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _selectSearchTab,
        const SingleActivator(LogicalKeyboardKey.keyD, control: true):
            handleDownloadsTapped,
        const SingleActivator(LogicalKeyboardKey.comma, control: true):
            handleSettingsTapped,
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, viewportConstraints) {
          final isWideRail =
              viewportConstraints.maxWidth >= _wideRailBreakpoint;

          return Consumer<SiteConfigProvider>(
            builder: (context, siteConfig, child) {
              if (_lastRatingFilter != null &&
                  (_lastRatingFilter != siteConfig.ratingFilter ||
                      _lastSourceId != siteConfig.currentSourceId) &&
                  !isLoading) {
                _lastRatingFilter = siteConfig.ratingFilter;
                _lastSourceId = siteConfig.currentSourceId;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !isLoading) {
                    fetchImages(clear: true);
                  }
                });
              }

              final cs = Theme.of(context).colorScheme;
              final gridPreset =
                  SettingsProvider.maybeOf(context)?.gridSizePreset ??
                      GridSizePreset.standard;
              final homeContent = _buildHomeContent(siteConfig, gridPreset);

              final stackedContent = IndexedStack(
                index: activeIndex,
                children: [
                  HeroMode(
                    enabled: activeIndex == 0,
                    child: homeContent,
                  ),
                  HeroMode(
                    enabled: activeIndex == 1,
                    child: const SearchPage(),
                  ),
                  HeroMode(
                    enabled: activeIndex == 2,
                    child: const FavoriteDisplayWidget(
                      topPadding: 8.0,
                      bottomPadding: 24.0,
                    ),
                  ),
                ],
              );

              return Scaffold(
                key: _scaffoldKey,
                drawerEnableOpenDragGesture: true,
                drawerEdgeDragWidth: 64.0,
                endDrawer: const QuickSearchDrawer(),
                endDrawerEnableOpenDragGesture: true,
                appBar: AppBar(
                  title: Text(
                    showSearchView
                        ? '搜索'
                        : (showFavoritesView ? '我的收藏' : 'SakuraView'),
                    overflow: TextOverflow.ellipsis,
                  ),
                  actions: [
                    if (!isWideRail) ...[
                      IconButton(
                        icon: Icon(
                          activeIndex == 0 ? Icons.home : Icons.home_outlined,
                        ),
                        tooltip: '首页',
                        onPressed: _selectHomeTab,
                      ),
                      IconButton(
                        icon: Icon(
                          activeIndex == 1
                              ? Icons.search
                              : Icons.search_outlined,
                        ),
                        tooltip: '搜索 (Ctrl+F)',
                        onPressed: _selectSearchTab,
                      ),
                      IconButton(
                        icon: Icon(
                          activeIndex == 2
                              ? Icons.favorite
                              : Icons.favorite_outline,
                        ),
                        tooltip: '收藏',
                        onPressed: handleFavoritesTapped,
                      ),
                      IconButton(
                        icon: const Icon(Icons.download_outlined),
                        tooltip: '下载 (Ctrl+D)',
                        onPressed: handleDownloadsTapped,
                      ),
                    ],
                    if (activeIndex == 0)
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: '刷新 (F5)',
                        onPressed: isLoading
                            ? null
                            : () => fetchImages(clear: true),
                      ),
                    Builder(
                      builder: (btnCtx) => IconButton(
                        icon: const Icon(Icons.bookmarks_outlined, size: 21),
                        tooltip: '快速搜索预设',
                        onPressed: () => Scaffold.of(btnCtx).openEndDrawer(),
                      ),
                    ),
                    RatingFilterPill(
                      mode: siteConfig.ratingFilter,
                      onSelected: handleRatingFilterChanged,
                      padding: const EdgeInsets.only(right: 6, left: 4),
                    ),
                    PopupMenuButton<String>(
                      tooltip: '切换图站',
                      onSelected: handleSiteChanged,
                      itemBuilder: (ctx) => siteConfig.enabledSources
                          .map(
                            (s) => PopupMenuItem<String>(
                              value: s.id,
                              child: Row(
                                children: [
                                  Icon(
                                    s.id == siteConfig.currentSourceId
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    size: 18,
                                    color: cs.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(s.name),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                      child: Container(
                        margin: const EdgeInsets.only(right: 12, left: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withAlpha(200),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: cs.outlineVariant.withAlpha(140),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.public_rounded,
                              size: 15,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              siteConfig.currentSource.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                drawer: AppDrawer(
                  isSafeMode: siteConfig.safeMode,
                  onSafeModeChanged: handleSafeModeChanged,
                  ratingFilter: siteConfig.ratingFilter,
                  onRatingFilterChanged: handleRatingFilterChanged,
                  onSiteChanged: handleSiteChanged,
                  onHomeTapped: handleHomeTapped,
                  onFavoritesTapped: handleFavoritesTapped,
                  onDownloadsTapped: handleDownloadsTapped,
                  onSettingsTapped: handleSettingsTapped,
                  activeIndex: activeIndex,
                  onSearchTapped: _selectSearchTab,
                  onHistoryTapped: () {
                    Navigator.push(
                      context,
                      SakuraPageRoute(builder: (_) => const HistoryPage()),
                    );
                  },
                  onBlacklistTapped: () {
                    Navigator.push(
                      context,
                      SakuraPageRoute(builder: (_) => const BlacklistPage()),
                    );
                  },
                  onSiteAccountsTapped: () {
                    Navigator.push(
                      context,
                      SakuraPageRoute(builder: (_) => const SiteAccountsPage()),
                    );
                  },
                  onAboutTapped: () {
                    Navigator.push(
                      context,
                      SakuraPageRoute(builder: (_) => const AboutPage()),
                    );
                  },
                ),
                body: SakuraDrawerSwipeDetector(
                  onSwipeRightFromLeft: () =>
                      _scaffoldKey.currentState?.openDrawer(),
                  onSwipeLeftFromRight: () =>
                      _scaffoldKey.currentState?.openEndDrawer(),
                  child: isWideRail
                      ? Row(
                          children: [
                            _buildNavigationRail(
                              context,
                              activeIndex: activeIndex,
                              availableHeight: viewportConstraints.maxHeight,
                            ),
                            VerticalDivider(
                              width: 1,
                              thickness: 0.8,
                              color: cs.outlineVariant.withAlpha(100),
                            ),
                            Expanded(child: stackedContent),
                          ],
                        )
                      : stackedContent,
                ),
              );
            },
          );
        },
        ),
      ),
    );
  }

  Widget _buildNavigationRail(
    BuildContext context, {
    required int activeIndex,
    required double availableHeight,
  }) {
    final cs = Theme.of(context).colorScheme;
    BaseDownloadNotifier? dlNotifier;
    try {
      dlNotifier = Provider.of<BaseDownloadNotifier>(context);
    } on ProviderNotFoundException {
      dlNotifier = null;
    }
    final activeDownloads = dlNotifier?.downloadingTasks.length ?? 0;

    return NavigationRail(
      backgroundColor: cs.surface,
      selectedIndex: activeIndex,
      labelType: NavigationRailLabelType.all,
      minWidth: 74,
      onDestinationSelected: (index) {
        switch (index) {
          case 0:
            _selectHomeTab();
            break;
          case 1:
            _selectSearchTab();
            break;
          case 2:
            handleFavoritesTapped();
            break;
          case 3:
            handleDownloadsTapped();
            break;
        }
      },
      destinations: [
        const NavigationRailDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: Text('首页'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.search_outlined),
          selectedIcon: Icon(Icons.search_rounded),
          label: Text('搜索'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.favorite_outline_rounded),
          selectedIcon: Icon(Icons.favorite_rounded),
          label: Text('收藏'),
        ),
        NavigationRailDestination(
          icon: Badge(
            isLabelVisible: activeDownloads > 0,
            label: Text('$activeDownloads'),
            child: const Icon(Icons.download_outlined),
          ),
          selectedIcon: Badge(
            isLabelVisible: activeDownloads > 0,
            label: Text('$activeDownloads'),
            child: const Icon(Icons.download_rounded),
          ),
          label: const Text('下载'),
        ),
      ],
      trailing: availableHeight >= 480
          ? Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: '设置 (Ctrl+,)',
                    onPressed: handleSettingsTapped,
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildHomeContent(
    SiteConfigProvider siteConfig,
    GridSizePreset gridPreset,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final paneWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final cols = gridPreset.calcColumns(paneWidth, isLandscape: true);

        if (imageList.isEmpty && isLoading) {
          return SakuraGridShimmer(columns: cols);
        }
        if (imageList.isEmpty && !isLoading) {
          return _buildErrorOrEmptyView(siteConfig);
        }

        final tileCacheWidth = computeGridTileCacheWidth(
          context,
          columns: cols,
        );

        return Scrollbar(
          controller: _scrollController,
          child: RefreshIndicator(
            onRefresh: () => fetchImages(clear: true),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: MasonryGridView.count(
                controller: _scrollController,
                crossAxisCount: cols,
                mainAxisSpacing: 8.0,
                crossAxisSpacing: 8.0,
                itemCount: imageList.length,
                itemBuilder: (context, index) {
                  if (_hasMoreImages &&
                      !isLoading &&
                      index >= imageList.length - 6 &&
                      _scrollController.hasClients &&
                      _scrollController.position.pixels > 160) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _hasMoreImages && !isLoading) {
                        fetchImages();
                      }
                    });
                  }

                  final item = imageList[index];
                  final String site =
                      item['site']?.toString() ?? siteConfig.currentSourceId;

                  return SakuraPostCard(
                    item: item,
                    cacheWidth: tileCacheWidth,
                    onTap: () {
                      Navigator.push(
                        context,
                        SakuraPageRoute(
                          builder: (context) => PostDetailPage(
                            postData: item,
                            siteName: site,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorOrEmptyView(SiteConfigProvider siteConfig) {
    final isAuthError = _lastError != null &&
        (_lastError!.contains('403') ||
            _lastError!.contains('401') ||
            _lastError!.contains('Cloudflare') ||
            _lastError!.contains('API Key'));
    return Center(
      key: ValueKey<String>('win_empty_${siteConfig.currentSourceId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isAuthError ? Icons.security_rounded : Icons.cloud_off_rounded,
              size: 56,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              _lastError ?? '未获取到图片，请重试或切换其他图站',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 13.5),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重试'),
                  onPressed: () => fetchImages(clear: true),
                ),
                if (isAuthError)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.vpn_key_outlined, size: 18),
                    label: const Text('配置账号密钥'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        SakuraPageRoute(
                          builder: (context) => const SiteAccountsPage(),
                        ),
                      );
                    },
                  ),
                if (siteConfig.currentSourceId != 'yandere')
                  OutlinedButton.icon(
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text('切换至 Yande.re'),
                    onPressed: () => handleSiteChanged('yandere'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
