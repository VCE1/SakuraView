import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:vce1_sakuraview/models/post_hive_model.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/providers/favorites_notifier.dart';
import 'package:vce1_sakuraview/utils/settings_page.dart';
import 'package:vce1_sakuraview/widgets/drawer_widget.dart';
import 'package:vce1_sakuraview/widgets/windows/window_full_image_screen.dart';
import 'package:vce1_sakuraview/widgets/common/group_posts_screen.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_loader.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_animated_image.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_page_route.dart';
import 'package:vce1_sakuraview/models/site_config.dart';
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
  String? _searchTag;
  int currentPage = 1;
  final int imagesPerPage = 40;

  bool isLoading = false;
  bool _isDisposed = false;
  bool _hasMoreImages = true;

  static final Logger _logger = Logger('WindowImageGridPage');
  final ScrollController _scrollController = ScrollController();
  final Set<int> _processingDownloads = {};
  late Box<PostHiveModel> _postBox;

  @override
  void initState() {
    super.initState();
    _logger.info('WindowImageGridPageState initState');
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
    _logger.info('WindowImageGridPageState disposed');
    super.dispose();
  }

  void _onScroll() {
    if (showFavoritesView || showSearchView || isLoading || !_scrollController.hasClients) {
      return;
    }
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
      showSearchView = false;
    });
    Navigator.pop(context);
    fetchImages(clear: true);
  }

  void handleFavoritesTapped() {
    if (!mounted) return;
    setState(() {
      showFavoritesView = true;
      showSearchView = false;
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
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    );
  }

  bool _isPostDownloaded(int postId) => _postBox.containsKey(postId);

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FavoritesNotifier>(
      builder: (context, favoritesNotifier, child) {
        Widget bodyContent;

        if (showSearchView) {
          bodyContent = SearchPage(initialTag: _searchTag);
        } else if (showFavoritesView) {
          bodyContent = FavoriteDisplayWidget(
            favoriteItems: favoritesNotifier.favoriteItems,
            onTagSelected: (tag) {
              setState(() {
                _searchTag = tag;
                showFavoritesView = false;
                showSearchView = true;
              });
            },
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
                            .clamp(2, 6),
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
                                      builder: (context) =>
                                          WindowsFullImageScreen(
                                        postData: item,
                                        posts: imageList,
                                        initialIndex: index,
                                      ),
                                    ),
                                  );
                          if (tag != null && tag.isNotEmpty && mounted) {
                            setState(() {
                              _searchTag = tag;
                              showFavoritesView = false;
                              showSearchView = true;
                            });
                          }
                        },
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14.0),
                          ),
                          elevation: 3,
                          shadowColor:
                              Theme.of(context).colorScheme.primary.withAlpha(50),
                          child: AspectRatio(
                            aspectRatio: aspectRatio,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                  Positioned.fill(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(14.0),
                                      child: SakuraAnimatedImage(
                                        imageUrl: item['preview_url']
                                                as String? ??
                                            item['sample_url'] as String? ??
                                            '',
                                        filterQuality: FilterQuality.medium,
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
              appBar: AppBar(
                title: Text(
                  showSearchView
                      ? 'Search'
                      : showFavoritesView
                          ? 'Favorites'
                          : 'SakuraView',
                ),
                actions: [
                  IconButton(
                    icon: Icon(
                      !showSearchView && !showFavoritesView
                          ? Icons.home
                          : Icons.home_outlined,
                    ),
                    tooltip: 'Home',
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
                    tooltip: 'Search',
                    onPressed: () {
                      setState(() {
                        _searchTag = null;
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
                    tooltip: 'Favorites',
                    onPressed: () {
                      setState(() {
                        showSearchView = false;
                        showFavoritesView = true;
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.download_outlined),
                    tooltip: 'Downloads',
                    onPressed: () => Navigator.pushNamed(context, '/downloads'),
                  ),
                  PopupMenuButton<ImageSite>(
                    tooltip: 'Switch Image Site',
                    onSelected: handleSiteChanged,
                    itemBuilder: (ctx) => ImageSite.values
                        .map((s) => PopupMenuItem<ImageSite>(
                              value: s,
                              child: Row(
                                children: [
                                  Icon(
                                    s == siteConfig.config.site
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(s.displayName),
                                ],
                              ),
                            ))
                        .toList(),
                    child: Container(
                      margin: const EdgeInsets.only(right: 12, left: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withAlpha(180),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud,
                            size: 15,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            siteConfig.config.site.displayName,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
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
                    showSearchView = true;
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
              body: bodyContent,
            );
          },
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
            (MediaQuery.of(context).size.width / 180).floor().clamp(2, 5),
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
              onTap: () async {
                final hasChildren =
                    item['has_children'] as bool? ?? false;
                if (hasChildren) {
                  Navigator.push(
                    context,
                    SakuraPageRoute(
                      builder: (_) => GroupPostsScreen(parentPost: item),
                    ),
                  );
                  return;
                }
                final tag = await Navigator.push<String>(
                  context,
                  SakuraPageRoute(
                    builder: (context) =>
                        WindowsFullImageScreen(
                          postData: item,
                          posts: favoriteItems,
                          initialIndex: index,
                        ),
                  ),
                );
                if (tag != null && tag.isNotEmpty) {
                  onTagSelected?.call(tag);
                }
              },
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14.0),
                  child: SakuraAnimatedImage(
                    imageUrl: imageUrl,
                    filterQuality: FilterQuality.medium,
                    fit: BoxFit.cover,
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
