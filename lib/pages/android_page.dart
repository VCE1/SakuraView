import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
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
    if (showFavoritesView || isLoading || !_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll && maxScroll > 0) {
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
        });
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
            SnackBar(content: Text('Error: ${e.toString()}')),
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
    });
    Navigator.pop(context);
    fetchImages(clear: true);
  }

  void handleFavoritesTapped() {
    if (!mounted) return;
    setState(() {
      showFavoritesView = true;
      _currentTabIndex = 2;
    });
    Navigator.pop(context);
    Provider.of<FavoritesNotifier>(context, listen: false);
  }

  void handleDownloadsTapped() {
    Navigator.pop(context);
    Navigator.pushNamed(context, '/downloads');
  }

  void handleSettingsTapped() {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    );
  }

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  bool _isPostDownloaded(int postId) => _postBox.containsKey(postId);

  @override
  Widget build(BuildContext context) {
    return Consumer<FavoritesNotifier>(
      builder: (context, favoritesNotifier, child) {
        Widget bodyContent;

        if (_currentTabIndex == 1) {
          bodyContent = SearchPage(initialTag: _searchTag);
        } else if (showFavoritesView) {
          bodyContent = FavoriteDisplayWidget(
            favoriteItems: favoritesNotifier.favoriteItems,
          );
        } else if (imageList.isEmpty && isLoading) {
          bodyContent = const SakuraGridShimmer();
        } else if (imageList.isEmpty && !isLoading) {
          bodyContent = Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 10),
                Text(
                  'No images found.\nTry switching sites or check connection.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  onPressed: () => fetchImages(clear: true),
                ),
              ],
            ),
          );
        } else {
          bodyContent = Consumer<BaseDownloadNotifier>(
            builder: (context, downloadNotifier, child) {
              return RefreshIndicator(
                onRefresh: () => fetchImages(clear: true),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: MasonryGridView.count(
                    controller: _scrollController,
                    crossAxisCount:
                        (MediaQuery.of(context).size.width / 180)
                            .floor()
                            .clamp(2, 4),
                    mainAxisSpacing: 8.0,
                    crossAxisSpacing: 8.0,
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
                      final isActuallyFavorite =
                          favoritesNotifier.isFavorite(
                        item['id']?.toString() ?? '',
                      );
                      final hasChildren =
                          item['has_children'] as bool? ?? false;
                      final num imgWidth =
                          item['width'] as num? ?? item['sample_width'] as num? ?? 1;
                      final num imgHeight =
                          item['height'] as num? ?? item['sample_height'] as num? ?? 1;
                      final double aspectRatio =
                          (imgWidth <= 0 || imgHeight <= 0)
                              ? 1.0
                              : imgWidth / imgHeight;
                      final bool isDownloaded =
                          _isPostDownloaded(postId);

                      return GestureDetector(
                        onTap: () async {
                          if (hasChildren) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => GroupPostsScreen(parentPost: item),
                              ),
                            );
                            return;
                          }
                          final tag = await Navigator.push<String>(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AndroidFullImageScreen(
                                postData: item,
                              ),
                            ),
                          );
                          if (tag != null && tag.isNotEmpty) {
                            setState(() {
                              _searchTag = tag;
                              _currentTabIndex = 1;
                            });
                          }
                        },
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14.0),
                          ),
                          elevation: 3,
                          child: AspectRatio(
                            aspectRatio: aspectRatio,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Positioned.fill(
                                  child: ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(14.0),
                                    child: CachedNetworkImage(
                                      imageUrl: item['preview_url']
                                              as String? ??
                                          item['sample_url'] as String? ??
                                          '',
                                      filterQuality: FilterQuality.medium,
                                      placeholder: (context, url) =>
                                          Shimmer.fromColors(
                                        baseColor: Colors.grey[200]!,
                                        highlightColor: Colors.grey[100]!,
                                        child: Container(
                                          color: Colors.white,
                                        ),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Center(
                                        child: Icon(
                                          Icons.broken_image,
                                          color: Colors.grey[300],
                                          size: 40,
                                        ),
                                      ),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                if (hasChildren)
                                  Positioned(
                                    top: 6,
                                    left: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 3,
                                        horizontal: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .secondary
                                            .withAlpha(180),
                                        borderRadius:
                                            BorderRadius.circular(8.0),
                                      ),
                                      child: const Text(
                                        'Group',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [
                                          Colors.black87,
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.end,
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            isActuallyFavorite
                                                ? Icons.favorite
                                                : Icons.favorite_border,
                                            color: isActuallyFavorite
                                                ? Colors.pinkAccent
                                                : Colors.white,
                                          ),
                                          iconSize: 20,
                                          visualDensity:
                                              VisualDensity.compact,
                                          onPressed: () =>
                                              favoritesNotifier
                                                  .toggleFavorite(item),
                                        ),
                                        IconButton(
                                          icon: Icon(
                                            isDownloaded
                                                ? Icons.download_done
                                                : Icons.download_outlined,
                                            color: isDownloaded
                                                ? Colors.greenAccent
                                                : Colors.white,
                                          ),
                                          iconSize: 20,
                                          visualDensity:
                                              VisualDensity.compact,
                                          tooltip: isDownloaded
                                              ? 'Downloaded'
                                              : 'Download',
                                          onPressed: () async {
                                            if (_processingDownloads
                                                .contains(postId)) { return; }
                                            if (_isPostDownloaded(postId)) {
                                              _showSnackbar(
                                                  'Already downloaded');
                                              return;
                                            }
                                            try {
                                              _processingDownloads
                                                  .add(postId);
                                              final result =
                                                  await downloadNotifier
                                                      .enqueueDownload(item);
                                              if (context.mounted) {
                                                String message;
                                                switch (result) {
                                                  case EnqueueResult.success:
                                                    message =
                                                        'Added to download queue';
                                                    break;
                                                  case EnqueueResult
                                                        .alreadyDownloaded:
                                                    message =
                                                        'Already downloaded';
                                                    break;
                                                  case EnqueueResult
                                                        .alreadyInQueue:
                                                    message =
                                                        'Already in queue';
                                                    break;
                                                  case EnqueueResult.failed:
                                                    message =
                                                        'Download failed';
                                                    break;
                                                }
                                                _showSnackbar(message);
                                              }
                                            } finally {
                                              _processingDownloads
                                                  .remove(postId);
                                            }
                                          },
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
                    },
                  ),
                ),
              );
            },
          );
        }

        return Consumer<SiteConfigProvider>(
          builder: (context, siteConfig, child) {
            return Scaffold(
              extendBodyBehindAppBar: true,
              extendBody: true,
              appBar: AppBar(
                title: Text(
                  _currentTabIndex == 1
                      ? 'Search'
                      : showFavoritesView
                          ? 'Favorites'
                          : 'SakuraView',
                ),
                flexibleSpace: _GlassAppBarBackground(),
                actions: [
                  if (_currentTabIndex != 1)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(180),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withAlpha(100),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            siteConfig.config.site.displayName,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
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
              body: Container(
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
                child: bodyContent,
              ),
              bottomNavigationBar: _GlassBottomNav(
                currentIndex: _currentTabIndex,
                onDestinationSelected: (index) {
                  setState(() {
                    _currentTabIndex = index;
                    if (index == 1) {
                      _searchTag = null;
                    } else if (index == 0) {
                      showFavoritesView = false;
                      if (imageList.isEmpty) fetchImages(clear: true);
                    } else if (index == 2) {
                      showFavoritesView = true;
                    } else if (index == 3) {
                      handleDownloadsTapped();
                      _currentTabIndex = 0;
                      return;
                    }
                  });
                },
              ),
            );
          },
        );
      },
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
                ? Colors.white.withAlpha(200)
                : const Color(0xFF1A1A2E).withAlpha(200),
            border: Border(
              bottom: BorderSide(
                color: brightness == Brightness.light
                    ? Colors.black.withAlpha(15)
                    : Colors.white.withAlpha(15),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onDestinationSelected;

  const _GlassBottomNav({
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: onDestinationSelected,
          animationDuration: const Duration(milliseconds: 300),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search),
              label: 'Search',
            ),
            NavigationDestination(
              icon: Icon(Icons.favorite_outline),
              selectedIcon: Icon(Icons.favorite),
              label: 'Favorites',
            ),
            NavigationDestination(
              icon: Icon(Icons.download_outlined),
              selectedIcon: Icon(Icons.download),
              label: 'Downloads',
            ),
          ],
        ),
      ),
    );
  }
}

class FavoriteDisplayWidget extends StatelessWidget {
  final List<Map<String, dynamic>> favoriteItems;
  const FavoriteDisplayWidget({super.key, required this.favoriteItems});

  @override
  Widget build(BuildContext context) {
    if (favoriteItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_outline, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No favorites yet',
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
            (MediaQuery.of(context).size.width / 180).floor().clamp(2, 4),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        itemCount: favoriteItems.length,
        itemBuilder: (context, index) {
          final item = favoriteItems[index];
          final String imageUrl = item['sample_url'] as String? ??
              item['preview_url'] as String? ??
              '';
          final num imgWidth = item['width'] as num? ??
              item['sample_width'] as num? ??
              1;
          final num imgHeight = item['height'] as num? ??
              item['sample_height'] as num? ??
              1;
          final double aspectRatio = (imgWidth <= 0 || imgHeight <= 0)
              ? 1.0
              : imgWidth / imgHeight;

          return Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14.0),
            ),
            child: InkWell(
              onTap: () {
                final hasChildren =
                    item['has_children'] as bool? ?? false;
                if (hasChildren) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GroupPostsScreen(parentPost: item),
                    ),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        AndroidFullImageScreen(postData: item),
                  ),
                );
              },
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14.0),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    filterQuality: FilterQuality.medium,
                    placeholder: (context, url) => Shimmer.fromColors(
                      baseColor: Colors.grey[200]!,
                      highlightColor: Colors.grey[100]!,
                      child: Container(color: Colors.white),
                    ),
                    errorWidget: (context, url, error) => const Center(
                      child: Icon(
                        Icons.broken_image,
                        color: Colors.grey,
                        size: 40,
                      ),
                    ),
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 300),
                    fadeInCurve: Curves.easeIn,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
