import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:shimmer/shimmer.dart';
import 'package:logging/logging.dart';

import 'package:provider/provider.dart';
import 'package:vce1_sakuraview/api/yande_api.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/widgets/android/android_full_image_screen.dart';
import 'package:vce1_sakuraview/widgets/windows/window_full_image_screen.dart';
import 'dart:io' show Platform;

class GroupPostsScreen extends StatefulWidget {
  final Map<String, dynamic> parentPost;

  const GroupPostsScreen({super.key, required this.parentPost});

  @override
  State<GroupPostsScreen> createState() => _GroupPostsScreenState();
}

class _GroupPostsScreenState extends State<GroupPostsScreen> {
  static final _logger = Logger('GroupPostsScreen');
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _allPosts = [];
  bool _isLoading = true;

  int get _postId => widget.parentPost['id'] as int? ?? 0;

  @override
  void initState() {
    super.initState();
    _allPosts = [widget.parentPost];
    _fetchChildren();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchChildren() async {
    try {
      List<Map<String, dynamic>> children;
      if (mounted) {
        final siteProvider = Provider.of<SiteConfigProvider>(context, listen: false);
        children = await siteProvider.apiClient.fetchChildPosts(_postId);
      } else {
        children = await YandeApi.fetchChildPosts(_postId);
      }
      if (mounted) {
        setState(() {
          _allPosts = [widget.parentPost, ...children];
          _isLoading = false;
        });
      }
    } catch (e) {
      _logger.warning('Failed to fetch children for $_postId: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openFullImage(Map<String, dynamic> postData) {
    final screen = Platform.isWindows
        ? WindowsFullImageScreen(postData: postData)
        : AndroidFullImageScreen(postData: postData);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parentTags =
        (widget.parentPost['tags'] as String? ?? '').split(' ').where((t) => t.isNotEmpty).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Group #$_postId'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: _ShimmerLoader())
          : _allPosts.length <= 1
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.collections_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text(
                        'No variants found',
                        style: TextStyle(color: Colors.grey[500], fontSize: 16),
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (parentTags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: parentTags
                              .map((t) => Chip(
                                    label: Text(t, style: const TextStyle(fontSize: 11)),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                  ))
                              .toList(),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      child: Text(
                        '${_allPosts.length} variants',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                            ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: MasonryGridView.count(
                          controller: _scrollController,
                          crossAxisCount:
                              (MediaQuery.of(context).size.width / 160).floor().clamp(2, 6),
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          itemCount: _allPosts.length,
                          itemBuilder: (context, index) {
                            final post = _allPosts[index];
                            final num w =
                                post['width'] as num? ?? post['sample_width'] as num? ?? 1;
                            final num h =
                                post['height'] as num? ?? post['sample_height'] as num? ?? 1;
                            final double aspect = (w <= 0 || h <= 0) ? 1.0 : w / h;
                            final bool isParent = index == 0;

                            return GestureDetector(
                              onTap: () => _openFullImage(post),
                              child: Card(
                                clipBehavior: Clip.antiAlias,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                                child: AspectRatio(
                                  aspectRatio: aspect,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      CachedNetworkImage(
                                        imageUrl: post['preview_url'] as String? ??
                                            post['sample_url'] as String? ??
                                            '',
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) => Shimmer.fromColors(
                                          baseColor: Colors.grey[300]!,
                                          highlightColor: Colors.grey[100]!,
                                          child: Container(color: Colors.white),
                                        ),
                                        errorWidget: (_, __, ___) => Container(
                                          color: Colors.grey[200],
                                          child: const Icon(Icons.broken_image,
                                              color: Colors.grey),
                                        ),
                                      ),
                                      if (isParent)
                                        Positioned(
                                          top: 6,
                                          left: 6,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withAlpha(200),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              'Parent',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold),
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
                    ),
                  ],
                ),
    );
  }
}

class _ShimmerLoader extends StatelessWidget {
  const _ShimmerLoader();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: 120,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(7),
            ),
          ),
        ],
      ),
    );
  }
}
