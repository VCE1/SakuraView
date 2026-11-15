import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';

import 'package:vce1_sakuraview/api/yande_api.dart';
import 'package:vce1_sakuraview/pages/post_detail_page.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_animated_image.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_page_route.dart';

class GroupPostsScreen extends StatefulWidget {
  final Map<String, dynamic> parentPost;
  final ValueChanged<String>? onTagTap;

  const GroupPostsScreen({
    super.key,
    required this.parentPost,
    this.onTagTap,
  });

  @override
  State<GroupPostsScreen> createState() => _GroupPostsScreenState();
}

class _GroupPostsScreenState extends State<GroupPostsScreen> {
  static final _logger = Logger('GroupPostsScreen');
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _allPosts = [];
  bool _isLoading = true;

  int get _effectiveParentId {
    final parentId = widget.parentPost['parent_id'] as int? ??
        widget.parentPost['parentId'] as int?;
    if (parentId != null && parentId > 0) return parentId;
    return widget.parentPost['id'] as int? ?? 0;
  }

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
        final siteProvider =
            Provider.of<SiteConfigProvider>(context, listen: false);
        final postSiteId = (widget.parentPost['site_id'] ??
                widget.parentPost['site'])
            ?.toString();
        final adapter = (postSiteId != null && postSiteId.isNotEmpty)
            ? siteProvider.adapterFor(postSiteId)
            : siteProvider.apiClient;
        children = await adapter.fetchGroupPosts(widget.parentPost);
      } else {
        children = await YandeApi.fetchChildPosts(_effectiveParentId);
      }
      if (mounted) {
        final hasPool = widget.parentPost['pool_id'] != null;
        final List<Map<String, dynamic>> combined;
        if (hasPool && children.isNotEmpty) {
          final seen = <int>{};
          combined = <Map<String, dynamic>>[];
          for (final child in children) {
            final id = child['id'] as int? ?? 0;
            if (id != 0 && seen.add(id)) {
              combined.add(child);
            }
          }
          final curId = widget.parentPost['id'] as int? ?? 0;
          if (curId != 0 && !seen.contains(curId)) {
            combined.insert(0, widget.parentPost);
          }
        } else {
          final Set<int> existingIds = {
            widget.parentPost['id'] as int? ?? 0,
          };
          final uniqueChildren = <Map<String, dynamic>>[];
          for (final child in children) {
            final id = child['id'] as int? ?? 0;
            if (id != 0 && !existingIds.contains(id)) {
              existingIds.add(id);
              uniqueChildren.add(child);
            }
          }
          combined = [widget.parentPost, ...uniqueChildren];
        }

        setState(() {
          _allPosts = combined;
          _isLoading = false;
        });
      }
    } catch (e) {
      _logger.warning('Failed to fetch children for $_effectiveParentId: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openPostDetail(int index) {
    if (_allPosts.isEmpty) return;
    final postData = _allPosts[index];
    Navigator.push(
      context,
      SakuraPageRoute(
        builder: (_) => PostDetailPage(
          postData: postData,
          siteName: (postData['site_id'] ?? postData['site'])?.toString(),
          onTagTap: widget.onTagTap,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parentTags = (widget.parentPost['tags'] as String? ?? '')
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          () {
            final poolName =
                (widget.parentPost['pool_name']?.toString() ?? '').trim();
            if (poolName.isNotEmpty) return poolName;
            final poolId = widget.parentPost['pool_id'];
            if (poolId != null) return '画廊 #$poolId';
            return '图组 #$_effectiveParentId';
          }(),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (!_isLoading && _allPosts.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.download_for_offline_outlined, size: 18),
              label: Text('下载整组 (${_allPosts.length})'),
              onPressed: () async {
                final summary = await context
                    .read<BaseDownloadNotifier>()
                    .enqueueBatchDownload(_allPosts);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      summary.added > 0
                          ? '已加入整组下载队列：新增 ${summary.added} 张'
                          : '整组作品已在本地目录或队列中',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            )
          : _allPosts.length <= 1
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.collections_bookmark_outlined,
                          size: 56, color: Colors.grey[500]),
                      const SizedBox(height: 12),
                      Text(
                        '未找到关联子图',
                        style:
                            TextStyle(color: Colors.grey[400], fontSize: 15),
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (parentTags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: parentTags
                              .take(15)
                              .map((t) => Chip(
                                    label: Text(t,
                                        style: const TextStyle(fontSize: 11)),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                  ))
                              .toList(),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                      child: Text(
                        '共 ${_allPosts.length} 张图片',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withAlpha(160),
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: MasonryGridView.count(
                          controller: _scrollController,
                          crossAxisCount:
                              (MediaQuery.of(context).size.width / 160)
                                  .floor()
                                  .clamp(2, 7),
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          itemCount: _allPosts.length,
                          itemBuilder: (context, index) {
                            final post = _allPosts[index];
                            final num w = post['width'] as num? ??
                                post['sample_width'] as num? ??
                                1;
                            final num h = post['height'] as num? ??
                                post['sample_height'] as num? ??
                                1;
                            final double aspect =
                                (w <= 0 || h <= 0) ? 1.0 : w / h;
                            final bool isParent = index == 0;

                            return GestureDetector(
                              onTap: () => _openPostDetail(index),
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
                                      SakuraAnimatedImage(
                                        imageUrl: post['preview_url']
                                                as String? ??
                                            post['sample_url'] as String? ??
                                            '',
                                        fit: BoxFit.cover,
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
                                                  .withAlpha(210),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              '主图',
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
