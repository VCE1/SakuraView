import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';

import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/providers/settings_provider.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/utils/settings_page.dart';
import 'package:vce1_sakuraview/utils/settings_service.dart';
import 'package:vce1_sakuraview/widgets/drawer_widget.dart';
import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/pages/post_detail_page.dart';
import 'package:vce1_sakuraview/pages/search_page.dart';
import 'package:vce1_sakuraview/widgets/common/favorite_display_widget.dart';
import 'package:vce1_sakuraview/widgets/common/quick_search_drawer.dart';
import 'package:vce1_sakuraview/widgets/common/rating_filter_pill.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_drawer_swipe_region.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_page_route.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_post_card.dart';
import 'package:vce1_sakuraview/widgets/common/telegram_floating_nav_bar.dart';
import 'package:vce1_sakuraview/pages/site_accounts_page.dart';
import 'package:vce1_sakuraview/pages/history_page.dart';
import 'package:vce1_sakuraview/pages/about_page.dart';
import 'package:vce1_sakuraview/pages/blacklist_page.dart';
import 'package:vce1_sakuraview/services/blacklist_service.dart';

class AndroidImageGridPage extends StatefulWidget {
  const AndroidImageGridPage({super.key});

  @override
  AndroidImageGridPageState createState() => AndroidImageGridPageState();
}

class AndroidImageGridPageState extends State<AndroidImageGridPage> {
  List<Map<String, dynamic>> imageList = [];
  bool showFavoritesView = false;
  int currentPage = 1;
  final int imagesPerPage = 40;

  bool isLoading = false;
  bool _isDisposed = false;
  bool _hasMoreImages = true;
  String? _lastError;
  bool _navBarVisible = true;

  static final Logger _logger = Logger('AndroidImageGridPage');
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();

  int _currentTabIndex = 0;
  RatingFilterMode? _lastRatingFilter;
  String? _lastSourceId;
  bool _isDrawerOpen = false;
  bool _isEndDrawerOpen = false;

  @override
  void initState() {
    super.initState();
    _logger.info('AndroidImageGridPageState initState');
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
    _logger.info('AndroidImageGridPageState disposed');
    super.dispose();
  }

  void _onBlacklistChanged() {
    if (!mounted) return;
    setState(() {
      imageList.removeWhere(
          (item) => BlacklistService.instance.isPostBlocked(item));
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final direction = _scrollController.position.userScrollDirection;
    if (direction == ScrollDirection.reverse && _navBarVisible) {
      if (_scrollController.position.pixels > 80) {
        setState(() => _navBarVisible = false);
      }
    } else if (direction == ScrollDirection.forward && !_navBarVisible) {
      setState(() => _navBarVisible = true);
    }

    if (showFavoritesView || isLoading || !_hasMoreImages) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll > 0 &&
        currentScroll > 160 &&
        currentScroll >= maxScroll - 800) {
      fetchImages();
    }
  }

  Future<void> fetchImages({bool clear = false}) async {
    final siteConfig = Provider.of<SiteConfigProvider>(context, listen: false);
    _lastRatingFilter = siteConfig.ratingFilter;
    _lastSourceId = siteConfig.currentSourceId;

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
      if (clear) _lastError = null;
    });

    try {
      final apiClient = siteConfig.apiClient;
      final ratingFilter = siteConfig.ratingFilter;

      final fetchedPosts = await apiClient.searchPosts(
        page: currentPage,
        limit: imagesPerPage,
        safeMode: siteConfig.safeMode,
        ratingFilter: ratingFilter,
      );

      final blacklist = BlacklistService.instance;
      final filteredPosts = fetchedPosts
          .map((p) => p.toApiMap(siteName: siteConfig.currentSourceId))
          .where((item) =>
              !blacklist.isPostBlocked(item) && ratingFilter.matchesPost(item))
          .toList();

      final previousCount = imageList.length;
      final mergedPosts =
          PostGroupHelper.mergeAndDeduplicate(imageList, filteredPosts);

      if (!_isDisposed && mounted) {
        setState(() {
          if (fetchedPosts.isEmpty) {
            _hasMoreImages = false;
          } else {
            _hasMoreImages = true;
            imageList = mergedPosts;
            currentPage++;
          }
          isLoading = false;
          _lastError = null;
        });
        if (fetchedPosts.isNotEmpty && mergedPosts.length > previousCount) {
          final cols = _calcColumns(context, listen: false);
          final tileCacheWidth = computeGridTileCacheWidth(
            context,
            columns: cols,
          );
          final newlyAdded = mergedPosts.sublist(previousCount);
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
      _logger.severe("Error fetching images: $e");
      if (!_isDisposed && mounted) {
        final msg = e.toString().replaceFirst('ApiException: ', '');
        setState(() {
          isLoading = false;
          _hasMoreImages = false;
          _lastError = msg;
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              behavior: SnackBarBehavior.floating,
            ),
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
      _currentTabIndex = 0;
      _navBarVisible = true;
    });
    fetchImages(clear: true);
  }

  void handleFavoritesTapped() {
    if (!mounted) return;
    setState(() {
      showFavoritesView = true;
      _currentTabIndex = 2;
      _navBarVisible = true;
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

  int _calcColumns(BuildContext context, {bool listen = true}) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final isLandscape =
        media.orientation == Orientation.landscape || width >= 640;
    final gridPreset =
        SettingsProvider.maybeOf(context, listen: listen)?.gridSizePreset ??
            GridSizePreset.standard;
    return gridPreset.calcColumns(width, isLandscape: isLandscape);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLandscape =
        media.orientation == Orientation.landscape || media.size.width >= 640;
    final settings = SettingsProvider.maybeOf(context);
    final floatingNavMode = settings?.floatingNavMode ?? FloatingNavMode.auto;
    final bool isDockHidden = floatingNavMode == FloatingNavMode.hidden;
    final bool dockVisible = switch (floatingNavMode) {
      FloatingNavMode.auto => _navBarVisible,
      FloatingNavMode.always => true,
      FloatingNavMode.hidden => false,
    };
    final double appBarHeight = isLandscape ? 46.0 : 54.0;
    final double topContentPadding = media.padding.top + appBarHeight + 6.0;
    final double bottomContentPadding =
        media.padding.bottom + (isDockHidden ? 12.0 : (isLandscape ? 66.0 : 80.0));

    return PopScope(
      canPop: !showFavoritesView &&
          _currentTabIndex == 0 &&
          !_isDrawerOpen &&
          !_isEndDrawerOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isEndDrawerOpen) {
          _scaffoldKey.currentState?.closeEndDrawer();
          return;
        }
        if (_isDrawerOpen) {
          _scaffoldKey.currentState?.closeDrawer();
          return;
        }
        setState(() {
          showFavoritesView = false;
          _currentTabIndex = 0;
          _navBarVisible = true;
        });
      },
      child: Consumer<SiteConfigProvider>(
        builder: (context, siteConfig, _) {
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
          Widget homeContent;

          if (imageList.isEmpty && isLoading) {
            homeContent = Center(
              key: ValueKey<String>('loading_${siteConfig.currentSourceId}'),
              child: const CircularProgressIndicator(strokeWidth: 2.2),
            );
          } else if (imageList.isEmpty && !isLoading) {
            homeContent = _buildErrorOrEmptyView(siteConfig);
          } else {
            final cols = _calcColumns(context);
            final tileCacheWidth =
                computeGridTileCacheWidth(context, columns: cols);
            homeContent = RefreshIndicator(
              key: ValueKey<String>('grid_${siteConfig.currentSourceId}'),
              edgeOffset: topContentPadding,
              onRefresh: () => fetchImages(clear: true),
              child: MasonryGridView.count(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(
                  media.padding.left + (isLandscape ? 12.0 : 8.0),
                  topContentPadding,
                  media.padding.right + (isLandscape ? 12.0 : 8.0),
                  bottomContentPadding,
                ),
                crossAxisCount: cols,
                mainAxisSpacing: isLandscape ? 10.0 : 8.0,
                crossAxisSpacing: isLandscape ? 10.0 : 8.0,
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

                  return SakuraPostCard(
                    item: item,
                    cacheWidth: tileCacheWidth,
                    onTap: () {
                      Navigator.push(
                        context,
                        SakuraPageRoute(
                          builder: (context) => PostDetailPage(
                            postData: item,
                            siteName: item['site']?.toString() ??
                                siteConfig.currentSourceId,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            );
          }

          return Scaffold(
              key: _scaffoldKey,
              extendBodyBehindAppBar: true,
              extendBody: true,
              onDrawerChanged: (opened) => _isDrawerOpen = opened,
              onEndDrawerChanged: (opened) => _isEndDrawerOpen = opened,
              drawerEnableOpenDragGesture: true,
              drawerEdgeDragWidth: 64.0,
              endDrawer: const QuickSearchDrawer(),
              endDrawerEnableOpenDragGesture: true,
              appBar: PreferredSize(
                preferredSize: Size.fromHeight(appBarHeight),
                child: AppBar(
                  toolbarHeight: appBarHeight,
                  centerTitle: !isLandscape,
                  leading: Builder(
                    builder: (leadingCtx) => IconButton(
                      icon: const Icon(Icons.menu_rounded),
                      tooltip: '导航菜单',
                      onPressed: () => Scaffold.of(leadingCtx).openDrawer(),
                    ),
                  ),
                  titleSpacing: isLandscape ? 8 : NavigationToolbar.kMiddleSpacing,
                  title: (_currentTabIndex == 1 || showFavoritesView)
                      ? Text(
                          _currentTabIndex == 1 ? '搜索' : '我的收藏',
                          style: TextStyle(
                            fontSize: isLandscape ? 17 : 19,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : null,
                  flexibleSpace: _GlassAppBarBackground(),
                  actions: [
                    RatingFilterPill(
                      mode: siteConfig.ratingFilter,
                      onSelected: handleRatingFilterChanged,
                    ),
                    // Interactive Site Switcher Pill (enabled sources only)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: PopupMenuButton<String>(
                        tooltip: '切换图站',
                        onSelected: handleSiteChanged,
                        offset: const Offset(0, 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        itemBuilder: (context) =>
                            siteConfig.enabledSources.map((s) {
                          final active = s.id == siteConfig.currentSourceId;
                          return PopupMenuItem<String>(
                            value: s.id,
                            child: Row(
                              children: [
                                Icon(
                                  active
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  size: 16,
                                  color: active ? cs.primary : null,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  s.name,
                                  style: TextStyle(
                                    fontWeight: active
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
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
                              Icon(Icons.public_rounded,
                                  size: 13, color: cs.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(
                                siteConfig.currentSource.name,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(Icons.expand_more,
                                  size: 14, color: cs.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
                activeIndex: showFavoritesView
                    ? 2
                    : (_currentTabIndex == 1 ? 1 : 0),
                onSearchTapped: () {
                  setState(() {
                    showFavoritesView = false;
                    _currentTabIndex = 1;
                    _navBarVisible = true;
                  });
                },
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
              body: NotificationListener<UserScrollNotification>(
                onNotification: (notification) {
                  if (floatingNavMode != FloatingNavMode.auto) {
                    return false;
                  }
                  if (notification.direction == ScrollDirection.reverse &&
                      _navBarVisible) {
                    setState(() => _navBarVisible = false);
                  } else if (notification.direction == ScrollDirection.forward &&
                      !_navBarVisible) {
                    setState(() => _navBarVisible = true);
                  }
                  return false;
                },
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        cs.surface.withAlpha(200),
                        Theme.of(context).scaffoldBackgroundColor,
                      ],
                    ),
                  ),
                  child: SakuraDrawerSwipeDetector(
                    onSwipeRightFromLeft: () =>
                        _scaffoldKey.currentState?.openDrawer(),
                    onSwipeLeftFromRight: () =>
                        _scaffoldKey.currentState?.openEndDrawer(),
                    child: IndexedStack(
                      index: showFavoritesView
                          ? 2
                          : (_currentTabIndex == 1 ? 1 : 0),
                      children: [
                        HeroMode(
                          enabled: !showFavoritesView && _currentTabIndex == 0,
                          child: homeContent,
                        ),
                      HeroMode(
                        enabled: !showFavoritesView && _currentTabIndex == 1,
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: topContentPadding,
                            bottom: isLandscape ? 8 : 12,
                          ),
                          child: const SearchPage(),
                        ),
                      ),
                      HeroMode(
                        enabled: showFavoritesView,
                        child: FavoriteDisplayWidget(
                          topPadding: topContentPadding,
                          bottomPadding: bottomContentPadding,
                        ),
                      ),
                    ],
                    ),
                  ),
                ),
              ),
              bottomNavigationBar: isDockHidden
                  ? null
                  : Consumer<BaseDownloadNotifier>(
                      builder: (context, dlNotifier, _) {
                        return TelegramFloatingNavBar(
                          currentIndex: _currentTabIndex,
                          visible: dockVisible,
                          activeDownloadCount: dlNotifier.downloadingTasks.length,
                          onDestinationSelected: (index) {
                            if (index == 3) {
                              setState(() => _navBarVisible = true);
                              Navigator.pushNamed(context, '/downloads');
                              return;
                            }
                            setState(() {
                              _navBarVisible = true;
                              _currentTabIndex = index;
                              if (index == 0) {
                                showFavoritesView = false;
                                if (imageList.isEmpty) fetchImages(clear: true);
                              } else if (index == 2) {
                                showFavoritesView = true;
                              } else if (index == 1) {
                                showFavoritesView = false;
                              }
                            });
                          },
                        );
                      },
                    ),
            );
        },
      ),
    );
  }

  Widget _buildErrorOrEmptyView(SiteConfigProvider siteConfig) {
    final isAuthError = _lastError != null &&
        (_lastError!.contains('403') ||
            _lastError!.contains('401') ||
            _lastError!.contains('Cloudflare') ||
            _lastError!.contains('API Key'));
    return Center(
      key: ValueKey<String>('empty_${siteConfig.currentSourceId}'),
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
              style: TextStyle(color: Colors.grey[400], fontSize: 13.5),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
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

class _GlassAppBarBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: brightness == Brightness.light
                ? Colors.white.withAlpha(185)
                : const Color(0xFF1A1A2E).withAlpha(185),
            border: Border(
              bottom: BorderSide(
                color: brightness == Brightness.light
                    ? Colors.black.withAlpha(15)
                    : Colors.white.withAlpha(18),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
