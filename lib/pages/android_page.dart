import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/providers/favorites_notifier.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/models/post_hive_model.dart';
import 'package:vce1_sakuraview/utils/settings_page.dart';
import 'package:vce1_sakuraview/widgets/drawer_widget.dart';
import 'package:vce1_sakuraview/widgets/android/android_full_image_screen.dart';
import 'package:vce1_sakuraview/models/site_config.dart';
import 'package:vce1_sakuraview/pages/search_page.dart';
import 'package:vce1_sakuraview/widgets/common/group_posts_screen.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_loader.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_animated_image.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_page_route.dart';
import 'package:vce1_sakuraview/widgets/common/telegram_floating_nav_bar.dart';
import 'package:vce1_sakuraview/pages/site_accounts_page.dart';

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
  final ScrollController _scrollController = ScrollController();
  final Set<int> _processingDownloads = {};
  late Box<PostHiveModel> _postBox;

  int _currentTabIndex = 0;
  String? _searchTag;

  @override
  void initState() {
    super.initState();
    _logger.info('AndroidImageGridPageState initState');
    _postBox = Hive.box<PostHiveModel>('downloaded_posts');
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
    _logger.info('AndroidImageGridPageState disposed');
    super.dispose();
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

    if (showFavoritesView || isLoading) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 240 && maxScroll > 0) {
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
      if (clear) _lastError = null;
    });

    try {
      final siteConfig = Provider.of<SiteConfigProvider>(context, listen: false);
      final apiClient = siteConfig.apiClient;

      final fetchedPosts = await apiClient.searchPosts(
        page: currentPage,
        limit: imagesPerPage,
        safeMode: siteConfig.config.safeMode,
      );

      if (!_isDisposed && mounted) {
        setState(() {
          if (fetchedPosts.isEmpty) {
            _hasMoreImages = false;
          } else {
            _hasMoreImages = true;
            imageList.addAll(fetchedPosts.map((p) => p.toApiMap()));
            currentPage++;
          }
          isLoading = false;
          _lastError = null;
        });
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

  void handleSafeModeChanged(bool value) {
    if (!mounted) return;
    Provider.of<SiteConfigProvider>(context, listen: false).setSafeMode(value);
    fetchImages(clear: true);
  }

  void handleSiteChanged(ImageSite site) {
    if (!mounted) return;
    Provider.of<SiteConfigProvider>(context, listen: false).setSite(site);
    fetchImages(clear: true);
  }

  void handleHomeTapped() {
    if (!mounted) return;
    setState(() {
      showFavoritesView = false;
      _currentTabIndex = 0;
      _navBarVisible = true;
    });
    Navigator.pop(context);
    fetchImages(clear: true);
  }

  void handleFavoritesTapped() {
    if (!mounted) return;
    setState(() {
      showFavoritesView = true;
      _currentTabIndex = 2;
      _navBarVisible = true;
    });
    Navigator.pop(context);
  }

  void handleDownloadsTapped() {
    Navigator.pop(context);
    Navigator.pushNamed(context, '/downloads');
  }

  void handleSettingsTapped() {
    Navigator.pop(context);
    Navigator.push(
      context,
      SakuraPageRoute(builder: (context) => const SettingsPage()),
    );
  }

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  bool _isPostDownloaded(int postId) => _postBox.containsKey(postId);

  int _calcColumns(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final isLandscape =
        media.orientation == Orientation.landscape || width >= 640;
    final targetTileWidth = isLandscape ? 168.0 : 175.0;
    return (width / targetTileWidth).floor().clamp(2, 7);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLandscape =
        media.orientation == Orientation.landscape || media.size.width >= 640;
    final double appBarHeight = isLandscape ? 46.0 : 54.0;
    final double topContentPadding = media.padding.top + appBarHeight + 6.0;
    final double bottomContentPadding =
        media.padding.bottom + (isLandscape ? 66.0 : 80.0);

    return PopScope(
      canPop: !showFavoritesView && _currentTabIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() {
          showFavoritesView = false;
          _currentTabIndex = 0;
          _navBarVisible = true;
        });
      },
      child: Consumer<FavoritesNotifier>(
        builder: (context, favoritesNotifier, child) {
          return Consumer<SiteConfigProvider>(
            builder: (context, siteConfig, _) {
              Widget bodyContent;

              if (_currentTabIndex == 1) {
                bodyContent = Padding(
                  key: const ValueKey<String>('tab_search'),
                  padding: EdgeInsets.only(
                    top: topContentPadding,
                    bottom: isLandscape ? 8 : 12,
                  ),
                  child: SearchPage(initialTag: _searchTag),
                );
              } else if (showFavoritesView) {
                bodyContent = FavoriteDisplayWidget(
                  key: const ValueKey<String>('tab_favorites'),
                  topPadding: topContentPadding,
                  bottomPadding: bottomContentPadding,
                );
              } else if (imageList.isEmpty && isLoading) {
              bodyContent = Padding(
                key: ValueKey<String>('shimmer_${siteConfig.config.site.name}'),
                padding: EdgeInsets.only(top: topContentPadding),
                child: SakuraGridShimmer(
                  columns: _calcColumns(context),
                  rows: isLandscape ? 15 : 12,
                ),
              );
            } else if (imageList.isEmpty && !isLoading) {
              bodyContent = _buildErrorOrEmptyView(siteConfig);
            } else {
              bodyContent = Consumer<BaseDownloadNotifier>(
                key: ValueKey<String>('grid_${siteConfig.config.site.name}'),
                builder: (context, downloadNotifier, child) {
                  final cols = _calcColumns(context);
                  return RefreshIndicator(
                    edgeOffset: topContentPadding,
                    onRefresh: () => fetchImages(clear: true),
                    child: MasonryGridView.count(
                      controller: _scrollController,
                      padding: EdgeInsets.fromLTRB(
                        isLandscape ? 12.0 : 8.0,
                        topContentPadding,
                        isLandscape ? 12.0 : 8.0,
                        bottomContentPadding,
                      ),
                      crossAxisCount: cols,
                      mainAxisSpacing: isLandscape ? 10.0 : 8.0,
                      crossAxisSpacing: isLandscape ? 10.0 : 8.0,
                      itemCount: imageList.length + (_hasMoreImages ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == imageList.length) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: SakuraLoader(size: 28),
                            ),
                          );
                        }

                        final item = imageList[index];
                        final int postId = item['id'] as int? ?? 0;
                        final isActuallyFavorite = favoritesNotifier.isFavorite(
                          item['id']?.toString() ?? '',
                        );
                        final hasChildren =
                            item['has_children'] as bool? ?? false;
                        final num imgWidth = item['width'] as num? ??
                            item['sample_width'] as num? ??
                            1;
                        final num imgHeight = item['height'] as num? ??
                            item['sample_height'] as num? ??
                            1;
                        final double aspectRatio =
                            (imgWidth <= 0 || imgHeight <= 0)
                                ? 1.0
                                : (imgWidth / imgHeight).clamp(0.42, 2.4);
                        final bool isDownloaded = _isPostDownloaded(postId);
                        final String rating =
                            (item['rating'] as String? ?? 's').toLowerCase();
                        final String fileExt =
                            (item['file_ext'] as String? ?? '').toLowerCase();

                        return _SakuraPostGridTile(
                          item: item,
                          aspectRatio: aspectRatio,
                          hasChildren: hasChildren,
                          isFavorite: isActuallyFavorite,
                          isDownloaded: isDownloaded,
                          rating: rating,
                          fileExt: fileExt,
                          onTap: () async {
                            if (hasChildren) {
                              Navigator.push(
                                context,
                                SakuraPageRoute(
                                  builder: (_) =>
                                      GroupPostsScreen(parentPost: item),
                                ),
                              );
                              return;
                            }
                            final tag = await Navigator.push<String>(
                              context,
                              SakuraPageRoute(
                                builder: (context) => AndroidFullImageScreen(
                                  postData: item,
                                  posts: imageList,
                                  initialIndex: index,
                                ),
                              ),
                            );
                            if (tag != null && tag.isNotEmpty) {
                              setState(() {
                                _searchTag = tag;
                                _currentTabIndex = 1;
                                _navBarVisible = true;
                              });
                            }
                          },
                          onFavoriteToggle: () =>
                              favoritesNotifier.toggleFavorite(item),
                          onDownloadTap: () async {
                            if (_processingDownloads.contains(postId)) return;
                            if (_isPostDownloaded(postId)) {
                              _showSnackbar('Already downloaded');
                              return;
                            }
                            try {
                              _processingDownloads.add(postId);
                              final result = await downloadNotifier
                                  .enqueueDownload(item);
                              if (context.mounted) {
                                final message = switch (result) {
                                  EnqueueResult.success =>
                                    'Added to download queue',
                                  EnqueueResult.alreadyDownloaded =>
                                    'Already downloaded',
                                  EnqueueResult.alreadyInQueue =>
                                    'Already in queue',
                                  EnqueueResult.failed => 'Download failed',
                                };
                                _showSnackbar(message);
                              }
                            } finally {
                              _processingDownloads.remove(postId);
                            }
                          },
                        );
                      },
                    ),
                  );
                },
              );
            }

            return Scaffold(
              extendBodyBehindAppBar: true,
              extendBody: true,
              appBar: PreferredSize(
                preferredSize: Size.fromHeight(appBarHeight),
                child: AppBar(
                  toolbarHeight: appBarHeight,
                  centerTitle: !isLandscape,
                  titleSpacing: isLandscape ? 8 : NavigationToolbar.kMiddleSpacing,
                  title: Text(
                    _currentTabIndex == 1
                        ? 'Search'
                        : showFavoritesView
                            ? 'Favorites'
                            : 'SakuraView',
                    style: TextStyle(
                      fontSize: isLandscape ? 17 : 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  flexibleSpace: _GlassAppBarBackground(),
                  actions: [
                    // Safe mode quick toggle pill
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () =>
                            handleSafeModeChanged(!siteConfig.config.safeMode),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: siteConfig.config.safeMode
                                ? Colors.teal.withAlpha(45)
                                : Colors.pinkAccent.withAlpha(45),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: siteConfig.config.safeMode
                                  ? Colors.tealAccent.withAlpha(110)
                                  : Colors.pinkAccent.withAlpha(110),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                siteConfig.config.safeMode
                                    ? Icons.shield_outlined
                                    : Icons.local_fire_department_rounded,
                                size: 13,
                                color: siteConfig.config.safeMode
                                    ? Colors.tealAccent
                                    : Colors.pinkAccent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                siteConfig.config.safeMode ? 'SAFE' : 'ALL',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: siteConfig.config.safeMode
                                      ? Colors.tealAccent
                                      : Colors.pinkAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Interactive Site Switcher Pill
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: PopupMenuButton<ImageSite>(
                        tooltip: 'Switch Site',
                        onSelected: handleSiteChanged,
                        offset: const Offset(0, 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        itemBuilder: (context) => ImageSite.values.map((s) {
                          final active = s == siteConfig.config.site;
                          return PopupMenuItem<ImageSite>(
                            value: s,
                            child: Row(
                              children: [
                                Icon(
                                  active
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  size: 16,
                                  color: active
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  s.displayName,
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
                            color: Colors.white.withAlpha(200),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withAlpha(120),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud,
                                  size: 13, color: Colors.grey[700]),
                              const SizedBox(width: 4),
                              Text(
                                siteConfig.config.site.displayName,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[800],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(Icons.expand_more,
                                  size: 14, color: Colors.grey[700]),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              drawer: AppDrawer(
                isSafeMode: siteConfig.config.safeMode,
                onSafeModeChanged: handleSafeModeChanged,
                onSiteChanged: handleSiteChanged,
                onHomeTapped: handleHomeTapped,
                onFavoritesTapped: handleFavoritesTapped,
                onDownloadsTapped: handleDownloadsTapped,
                onSettingsTapped: handleSettingsTapped,
                onSearchTapped: () {
                  setState(() {
                    showFavoritesView = false;
                    _currentTabIndex = 1;
                    _navBarVisible = true;
                  });
                  Navigator.pop(context);
                },
                onHistoryTapped: () {
                  Navigator.pop(context);
                },
                onFollowTapped: () {
                  Navigator.pop(context);
                },
                onRankingTapped: () {
                  Navigator.pop(context);
                },
              ),
              body: NotificationListener<UserScrollNotification>(
                onNotification: (notification) {
                  if (notification.direction == ScrollDirection.reverse && _navBarVisible) {
                    setState(() => _navBarVisible = false);
                  } else if (notification.direction == ScrollDirection.forward && !_navBarVisible) {
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
                        Theme.of(context).colorScheme.surface.withAlpha(200),
                        Theme.of(context).scaffoldBackgroundColor,
                      ],
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return SakuraEntranceTransition(
                        animation: animation,
                        child: child,
                      );
                    },
                    child: bodyContent,
                  ),
                ),
              ),
              bottomNavigationBar: Consumer<BaseDownloadNotifier>(
                builder: (context, dlNotifier, _) {
                  return TelegramFloatingNavBar(
                    currentIndex: _currentTabIndex,
                    visible: _navBarVisible,
                    activeDownloadCount: dlNotifier.downloadingTasks.length,
                    onDestinationSelected: (index) {
                      setState(() {
                        _navBarVisible = true;
                        if (index == 3) {
                          Navigator.pushNamed(context, '/downloads');
                          return;
                        }
                        _currentTabIndex = index;
                        if (index == 1) {
                          _searchTag = null;
                        } else if (index == 0) {
                          showFavoritesView = false;
                          if (imageList.isEmpty) fetchImages(clear: true);
                        } else if (index == 2) {
                          showFavoritesView = true;
                        }
                      });
                    },
                  );
                },
              ),
            );
          },
        );
      },
    ),
    );
  }

  Widget _buildErrorOrEmptyView(SiteConfigProvider siteConfig) {
    final isDanbooru403 = _lastError != null &&
        (_lastError!.contains('403') || _lastError!.contains('Cloudflare'));
    return Center(
      key: ValueKey<String>('empty_${siteConfig.config.site.name}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isDanbooru403 ? Icons.security_rounded : Icons.cloud_off_rounded,
              size: 56,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              _lastError ??
                  'No images found.\nTry switching sites or check connection.',
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
                  label: const Text('Retry'),
                  onPressed: () => fetchImages(clear: true),
                ),
                if (isDanbooru403)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.vpn_key_outlined, size: 18),
                    label: const Text('Configure API Key'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        SakuraPageRoute(
                          builder: (context) => const SettingsPage(),
                        ),
                      );
                    },
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text('Switch to Yande.re'),
                  onPressed: () => handleSiteChanged(ImageSite.yandere),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Card widget combining SakuraView's rounded design with pixes's `IllustWidget`
/// animated image loading, subtle outline border, and corner metadata badges.
class _SakuraPostGridTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final double aspectRatio;
  final bool hasChildren;
  final bool isFavorite;
  final bool isDownloaded;
  final String rating;
  final String fileExt;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onDownloadTap;

  const _SakuraPostGridTile({
    required this.item,
    required this.aspectRatio,
    required this.hasChildren,
    required this.isFavorite,
    required this.isDownloaded,
    required this.rating,
    required this.fileExt,
    required this.onTap,
    required this.onFavoriteToggle,
    required this.onDownloadTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final String imageUrl = item['preview_url'] as String? ??
        item['sample_url'] as String? ??
        '';
    final bool isExplicit = rating == 'e';
    final bool isGif = fileExt == 'gif' || fileExt == 'webm' || fileExt == 'mp4';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.0),
          color: cs.surfaceContainerHighest.withAlpha(80),
          border: Border.all(
            color: cs.outlineVariant.withAlpha(90),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(35),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              SakuraAnimatedImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              ),
              // Top-left badges (pixes style)
              if (hasChildren || isGif)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasChildren)
                        _CardBadge(
                          text: 'Group',
                          color: cs.secondary.withAlpha(200),
                        ),
                      if (hasChildren && isGif) const SizedBox(width: 4),
                      if (isGif)
                        _CardBadge(
                          text: fileExt.toUpperCase(),
                          color: cs.primaryContainer.withAlpha(210),
                          textColor: cs.onPrimaryContainer,
                        ),
                    ],
                  ),
                ),
              if (isExplicit)
                Positioned(
                  top: 6,
                  right: 6,
                  child: _CardBadge(
                    text: 'R18',
                    color: Colors.redAccent.withAlpha(210),
                  ),
                ),
              // Subtle bottom gradient with compact action buttons
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 12, 4, 2),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black54,
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _CompactCardIconBtn(
                        icon: isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: isFavorite ? Colors.pinkAccent : Colors.white,
                        onTap: onFavoriteToggle,
                      ),
                      const SizedBox(width: 2),
                      _CompactCardIconBtn(
                        icon: isDownloaded
                            ? Icons.download_done_rounded
                            : Icons.download_outlined,
                        color: isDownloaded ? Colors.greenAccent : Colors.white,
                        onTap: onDownloadTap,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardBadge extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;

  const _CardBadge({
    required this.text,
    required this.color,
    this.textColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CompactCardIconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CompactCardIconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(5.0),
          child: Icon(icon, size: 18, color: color),
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

class FavoriteDisplayWidget extends StatefulWidget {
  final double topPadding;
  final double bottomPadding;

  const FavoriteDisplayWidget({
    super.key,
    this.topPadding = 64.0,
    this.bottomPadding = 80.0,
  });

  @override
  State<FavoriteDisplayWidget> createState() => _FavoriteDisplayWidgetState();
}

class _FavoriteDisplayWidgetState extends State<FavoriteDisplayWidget> {
  int _favoriteMode = 0; // 0: 本地离线, 1: 云端账号

  void _syncCloudToLocal() async {
    final notifier = context.read<FavoritesNotifier>();
    final count = await notifier.syncCloudToLocal();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已成功将 $count 张云端收藏同步转存至本地离线数据库'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _refreshCloud() {
    final siteConfig = context.read<SiteConfigProvider>();
    context.read<FavoritesNotifier>().fetchCloudFavorites(siteConfig);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final favNotifier = context.watch<FavoritesNotifier>();
    final siteConfig = context.watch<SiteConfigProvider>();
    final isCloud = _favoriteMode == 1;
    final items = isCloud ? favNotifier.cloudItems : favNotifier.favoriteItems;
    final creds = siteConfig.credentialsFor(siteConfig.config.site);
    final hasUserOrCookie = creds.username.isNotEmpty || creds.cookies.isNotEmpty;

    return Column(
      children: [
        SizedBox(height: widget.topPadding),
        // Mode Selector Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  segments: [
                    ButtonSegment<int>(
                      value: 0,
                      label: Text('本地离线 (${favNotifier.favoriteItems.length})'),
                      icon: const Icon(Icons.offline_pin_outlined, size: 16),
                    ),
                    ButtonSegment<int>(
                      value: 1,
                      label: Text('云端账号 (${favNotifier.cloudItems.length})'),
                      icon: const Icon(Icons.cloud_outlined, size: 16),
                    ),
                  ],
                  selected: {_favoriteMode},
                  onSelectionChanged: (set) {
                    setState(() => _favoriteMode = set.first);
                    if (set.first == 1 &&
                        favNotifier.cloudItems.isEmpty &&
                        !favNotifier.isCloudLoading &&
                        hasUserOrCookie) {
                      _refreshCloud();
                    }
                  },
                ),
              ),
              if (isCloud && hasUserOrCookie) ...[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: '一键将云端收藏同步至本地',
                  icon: const Icon(Icons.sync_alt_rounded, size: 20),
                  onPressed: favNotifier.cloudItems.isNotEmpty ? _syncCloudToLocal : null,
                ),
                IconButton.filledTonal(
                  tooltip: '刷新云端收藏',
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  onPressed: _refreshCloud,
                ),
              ],
            ],
          ),
        ),
        if (isCloud && !hasUserOrCookie)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.account_circle_outlined, size: 56, color: cs.primary),
                    const SizedBox(height: 16),
                    Text(
                      '未配置 ${siteConfig.config.site.displayName} 账号',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '请先配置用户名或通过内置网页登录获取会话 Cookie，即可直接同步与浏览您的云端收藏夹。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SiteAccountsPage()),
                        ).then((_) {
                          if (mounted) _refreshCloud();
                        });
                      },
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('前往配置或登录账号'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (isCloud && favNotifier.isCloudLoading)
          const Expanded(
            child: Center(
              child: SakuraLoader(size: 32),
            ),
          )
        else if (isCloud && favNotifier.cloudError != null)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 52,
                      color: Colors.orangeAccent,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '加载云端收藏失败\n${favNotifier.cloudError}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: _refreshCloud,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (items.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isCloud ? Icons.cloud_off_rounded : Icons.favorite_outline_rounded,
                    size: 60,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isCloud ? '云端收藏夹为空' : '暂无本地离线收藏',
                    style: TextStyle(color: Colors.grey[500], fontSize: 16),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: Builder(
              builder: (ctx) {
                final width = MediaQuery.of(ctx).size.width;
                final cols = (width / 170).floor().clamp(2, 7);
                return MasonryGridView.count(
                  padding: EdgeInsets.fromLTRB(10, 4, 10, widget.bottomPadding),
                  crossAxisCount: cols,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final String imageUrl = item['sample_url'] as String? ??
                        item['preview_url'] as String? ??
                        '';
                    final num imgWidth =
                        item['width'] as num? ?? item['sample_width'] as num? ?? 1;
                    final num imgHeight =
                        item['height'] as num? ?? item['sample_height'] as num? ?? 1;
                    final double aspectRatio = (imgWidth <= 0 || imgHeight <= 0)
                        ? 1.0
                        : (imgWidth / imgHeight).clamp(0.42, 2.4);

                    return Card(
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: InkWell(
                        onTap: () {
                          final hasChildren = item['has_children'] as bool? ?? false;
                          if (hasChildren) {
                            Navigator.push(
                              context,
                              SakuraPageRoute(
                                builder: (_) => GroupPostsScreen(parentPost: item),
                              ),
                            );
                            return;
                          }
                          Navigator.push(
                            context,
                            SakuraPageRoute(
                              builder: (context) => AndroidFullImageScreen(
                                postData: item,
                                posts: items,
                                initialIndex: index,
                              ),
                            ),
                          );
                        },
                        child: AspectRatio(
                          aspectRatio: aspectRatio,
                          child: SakuraAnimatedImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
