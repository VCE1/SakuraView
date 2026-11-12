import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:logging/logging.dart';

import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/providers/recent_tags_notifier.dart';
import 'package:vce1_sakuraview/widgets/android/android_full_image_screen.dart';
import 'package:vce1_sakuraview/widgets/common/group_posts_screen.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_loader.dart';

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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search tags...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
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
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(clear: true),
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
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: MasonryGridView.count(
            controller: _scrollController,
            crossAxisCount:
                (MediaQuery.of(context).size.width / 180).floor().clamp(2, 4),
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

              final hasChildren =
                  item['has_children'] as bool? ?? false;

              return GestureDetector(
                onTap: () {
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
                      builder: (context) => AndroidFullImageScreen(postData: item),
                    ),
                  );
                },
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 3,
                  child: AspectRatio(
                    aspectRatio: aspectRatio,
                    child: CachedNetworkImage(
                      imageUrl: item['preview_url'] as String? ??
                          item['sample_url'] as String? ??
                          '',
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Shimmer.fromColors(
                        baseColor: Colors.grey[200]!,
                        highlightColor: Colors.grey[100]!,
                        child: Container(color: Colors.white),
                      ),
                      errorWidget: (context, url, error) => Center(
                        child: Icon(Icons.broken_image, color: Colors.grey[300]),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
    );
  }
}
