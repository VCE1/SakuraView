import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';

import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/pages/about_page.dart';
import 'package:vce1_sakuraview/pages/blacklist_page.dart';
import 'package:vce1_sakuraview/pages/history_page.dart';
import 'package:vce1_sakuraview/pages/post_detail_page.dart';
import 'package:vce1_sakuraview/pages/site_accounts_page.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/providers/settings_provider.dart';
import 'package:vce1_sakuraview/providers/favorites_notifier.dart';
import 'package:vce1_sakuraview/services/blacklist_service.dart';
import 'package:vce1_sakuraview/utils/settings_page.dart';
import 'package:vce1_sakuraview/utils/settings_service.dart';
import 'package:vce1_sakuraview/widgets/drawer_widget.dart';
import 'package:vce1_sakuraview/widgets/common/quick_search_drawer.dart';
import 'package:vce1_sakuraview/widgets/common/rating_filter_pill.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_animated_image.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_page_route.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_post_card.dart';
import 'package:vce1_sakuraview/pages/search_page.dart';

class WindowImageGridPage extends StatefulWidget {
  const WindowImageGridPage({super.key});

  @override
  WindowImageGridPageState createState() => WindowImageGridPageState();
}

class WindowImageGridPageState extends State<WindowImageGridPage> {
  List<Map<String, dynamic>> imageList = [];
  bool showFavoritesView = false;
  bool showSearchView = false;
  int currentPage = 1;
  final int imagesPerPage = 40;

  bool isLoading = false;
  bool _isDisposed = false;
  bool _hasMoreImages = true;

  static final Logger _logger = Logger('WindowImageGridPage');
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  double? _swipeStartX;
  double _swipeDeltaX = 0.0;
  RatingFilterMode? _lastRatingFilter;
  String? _lastSourceId;

  @override
  void initState() {
    super.initState();
    _logger.info('WindowImageGridPageState initState');
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) fetchImages(clear: true);
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _logger.info('WindowImageGridPageState disposed');
    super.dispose();
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
      });
    }
    if (isLoading || !mounted) return;

    setState(() => isLoading = true);

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
          final width = MediaQuery.of(context).size.width;
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
      _logger.severe("Error fetching images: $e");
      if (!_isDisposed && mounted) {
        setState(() {
          isLoading = false;
          _hasMoreImages = false;
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString().replaceFirst('ApiException: ', ''))),
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
        Widget homeContent;

        if (imageList.isEmpty && isLoading) {
          homeContent = const Center(
            child: CircularProgressIndicator(strokeWidth: 2.2),
          );
        } else if (imageList.isEmpty && !isLoading) {
          homeContent = Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 10),
                Text(
                  '未获取到图片，请重试或切换其他图站',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                  onPressed: () => fetchImages(clear: true),
                ),
              ],
            ),
          );
        } else {
          final width = MediaQuery.of(context).size.width;
          final gridPreset =
              SettingsProvider.maybeOf(context)?.gridSizePreset ??
                  GridSizePreset.standard;
          final cols = gridPreset.calcColumns(width, isLandscape: true);
          final tileCacheWidth = computeGridTileCacheWidth(
            context,
            columns: cols,
          );
          homeContent = RefreshIndicator(
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
          );
        }

        return Scaffold(
          key: _scaffoldKey,
          endDrawer: const QuickSearchDrawer(),
          endDrawerEnableOpenDragGesture: true,
          appBar: AppBar(
            title: (showSearchView || showFavoritesView)
                ? Text(showSearchView ? '搜索' : '我的收藏')
                : null,
            actions: [
              IconButton(
                icon: Icon(
                  !showSearchView && !showFavoritesView
                      ? Icons.home
                      : Icons.home_outlined,
                ),
                tooltip: '首页',
                onPressed: () {
                  setState(() {
                    showSearchView = false;
                    showFavoritesView = false;
                  });
                  if (imageList.isEmpty) fetchImages(clear: true);
                },
              ),
              IconButton(
                icon: Icon(
                  showSearchView ? Icons.search : Icons.search_outlined,
                ),
                tooltip: '搜索',
                onPressed: () {
                  setState(() {
                    showFavoritesView = false;
                    showSearchView = true;
                  });
                },
              ),
              IconButton(
                icon: Icon(
                  showFavoritesView
                      ? Icons.favorite
                      : Icons.favorite_outline,
                ),
                tooltip: '收藏',
                onPressed: () {
                  setState(() {
                    showSearchView = false;
                    showFavoritesView = true;
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.download_outlined),
                tooltip: '下载',
                onPressed: () => Navigator.pushNamed(context, '/downloads'),
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
                    .map((s) => PopupMenuItem<String>(
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
                        ))
                    .toList(),
                child: Container(
                  margin: const EdgeInsets.only(right: 12, left: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
            activeIndex: showFavoritesView ? 2 : (showSearchView ? 1 : 0),
            onSearchTapped: () {
              setState(() {
                showFavoritesView = false;
                showSearchView = true;
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
          body: IndexedStack(
            index: showFavoritesView ? 2 : (showSearchView ? 1 : 0),
            children: [
              HeroMode(
                enabled: !showFavoritesView && !showSearchView,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: (details) {
                    _swipeStartX = details.globalPosition.dx;
                    _swipeDeltaX = 0.0;
                  },
                  onHorizontalDragUpdate: (details) {
                    if (_swipeStartX == null) return;
                    _swipeDeltaX += details.primaryDelta ?? 0.0;
                  },
                  onHorizontalDragCancel: () {
                    _swipeStartX = null;
                    _swipeDeltaX = 0.0;
                  },
                  onHorizontalDragEnd: (details) {
                    final startX = _swipeStartX;
                    final deltaX = _swipeDeltaX;
                    _swipeStartX = null;
                    _swipeDeltaX = 0.0;
                    if (startX == null) return;
                    final screenWidth = MediaQuery.of(context).size.width;
                    final vx = details.velocity.pixelsPerSecond.dx;
                    if (startX >= screenWidth * 0.5 &&
                        (deltaX <= -42 || vx <= -320)) {
                      _scaffoldKey.currentState?.openEndDrawer();
                    }
                  },
                  child: homeContent,
                ),
              ),
              HeroMode(
                enabled: !showFavoritesView && showSearchView,
                child: const SearchPage(),
              ),
              HeroMode(
                enabled: showFavoritesView,
                child: Consumer<FavoritesNotifier>(
                  builder: (context, favoritesNotifier, _) =>
                      FavoriteDisplayWidget(
                    favoriteItems: favoritesNotifier.favoriteItems,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class FavoriteDisplayWidget extends StatelessWidget {
  final List<Map<String, dynamic>> favoriteItems;
  final ValueChanged<String>? onTagSelected;

  const FavoriteDisplayWidget({
    super.key,
    required this.favoriteItems,
    this.onTagSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (favoriteItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_outline, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              '暂无收藏作品',
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: MasonryGridView.count(
        crossAxisCount:
            (MediaQuery.of(context).size.width / 180).floor().clamp(2, 5),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        itemCount: favoriteItems.length,
        itemBuilder: (context, index) {
          final item = favoriteItems[index];
          final String imageUrl = item['preview_url'] as String? ??
              item['sample_url'] as String? ??
              '';
          final String site = item['site']?.toString() ?? 'yandere';
          final num imgWidth = item['preview_width'] as num? ??
              item['width'] as num? ??
              item['sample_width'] as num? ??
              1;
          final num imgHeight = item['preview_height'] as num? ??
              item['height'] as num? ??
              item['sample_height'] as num? ??
              1;
          final double aspectRatio = (imgWidth <= 0 || imgHeight <= 0)
              ? 1.0
              : (imgWidth / imgHeight).clamp(0.42, 2.4);

          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(
                color: cs.outlineVariant.withAlpha(90),
                width: 0.8,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  SakuraPageRoute(
                    builder: (_) => PostDetailPage(
                      postData: item,
                      siteName: site,
                    ),
                  ),
                );
              },
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: SakuraAnimatedImage(
                  imageUrl: imageUrl,
                  siteId: site,
                  filterQuality: FilterQuality.medium,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
