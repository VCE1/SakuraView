import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';

import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/providers/recent_tags_notifier.dart';
import 'package:vce1_sakuraview/widgets/android/android_full_image_screen.dart';
import 'package:vce1_sakuraview/widgets/windows/window_full_image_screen.dart';
import 'package:vce1_sakuraview/widgets/common/group_posts_screen.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_loader.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_animated_image.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_page_route.dart';

class SearchPage extends StatefulWidget {
  final String? initialTag;

  const SearchPage({super.key, this.initialTag});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Logger _logger = Logger('SearchPage');

  final List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  bool _hasMore = true;
  int _currentPage = 1;
  static const int _perPage = 40;

  @override
  void initState() {
    super.initState();
    _applyTag(widget.initialTag);
  }

  @override
  void didUpdateWidget(SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTag != null &&
        widget.initialTag != oldWidget.initialTag) {
      _applyTag(widget.initialTag);
    }
  }

  void _applyTag(String? tag) {
    if (tag != null && tag.isNotEmpty) {
      _searchController.text = tag;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _search(clear: true);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _search({bool clear = false}) async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    context.read<RecentTagsNotifier>().addTag(query);

    if (clear) {
      setState(() {
        _results.clear();
        _currentPage = 1;
        _hasMore = true;
      });
    }
    if (_isLoading || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final siteConfig = Provider.of<SiteConfigProvider>(context, listen: false);
      final apiClient = siteConfig.apiClient;

      final fetchedPosts = await apiClient.searchPosts(
        tags: query,
        page: _currentPage,
        limit: _perPage,
        safeMode: siteConfig.config.safeMode,
      );

      if (!mounted) return;
      setState(() {
        if (fetchedPosts.isEmpty) {
          _hasMore = false;
        } else {
          _hasMore = true;
          _results.addAll(fetchedPosts.map((p) => p.toApiMap()));
          _currentPage++;
        }
        _isLoading = false;
        _hasSearched = true;
      });
    } catch (e) {
      _logger.severe('Search error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search error: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            isLandscape ? 4 : 8,
            16,
            isLandscape ? 4 : 8,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: SizedBox(
                height: isLandscape ? 42 : 48,
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(fontSize: isLandscape ? 13.5 : 14.5),
                  decoration: InputDecoration(
                    hintText: 'Search tags...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 0,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _results.clear();
                                _hasSearched = false;
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: theme.colorScheme.surface.withAlpha(200),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _search(clear: true),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: _buildResults(theme),
        ),
      ],
    );
  }

  Widget _buildResults(ThemeData theme) {
    if (_isLoading && _results.isEmpty) {
      return const SakuraGridShimmer();
    }

    if (_hasSearched && _results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'No results found',
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      return _buildRecentTags(theme);
    }

    final width = MediaQuery.of(context).size.width;
    final columns = (width / 168).floor().clamp(2, 7);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            _scrollController.position.pixels >=
                _scrollController.position.maxScrollExtent - 200 &&
            _hasMore &&
            !_isLoading) {
          _search();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () => _search(clear: true),
        child: MasonryGridView.count(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 86),
          crossAxisCount: columns,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          itemCount: _results.length + (_hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _results.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: SakuraLoader(size: 28),
                ),
              );
            }

            final item = _results[index];
            final num imgWidth =
                item['width'] as num? ?? item['sample_width'] as num? ?? 1;
            final num imgHeight =
                item['height'] as num? ?? item['sample_height'] as num? ?? 1;
            final double aspectRatio =
                (imgWidth <= 0 || imgHeight <= 0) ? 1.0 : imgWidth / imgHeight;

            final hasChildren = item['has_children'] as bool? ?? false;
            final previewUrl = item['preview_url'] as String? ??
                item['sample_url'] as String? ??
                '';

            return GestureDetector(
              onTap: () async {
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
                    builder: (context) => Platform.isWindows
                        ? WindowsFullImageScreen(postData: item)
                        : AndroidFullImageScreen(postData: item),
                  ),
                );
                if (tag != null && tag.isNotEmpty && mounted) {
                  _applyTag(tag);
                }
              },
              child: Card(
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 2.5,
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  child: SakuraAnimatedImage(
                    imageUrl: previewUrl,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRecentTags(ThemeData theme) {
    final recentTags = context.watch<RecentTagsNotifier>();
    if (recentTags.tags.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              'Enter tags to search',
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 86),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Recent Tags',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    label: const Text('Clear'),
                    onPressed: () => recentTags.clear(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: recentTags.tags.map((tag) {
                  return InputChip(
                    label: Text(tag, style: const TextStyle(fontSize: 13)),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => recentTags.removeTag(tag),
                    onPressed: () {
                      _searchController.text = tag;
                      _search(clear: true);
                    },
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
