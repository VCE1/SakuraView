import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/pages/post_detail_page.dart';
import 'package:vce1_sakuraview/services/history_service.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_animated_image.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_page_route.dart';

/// Browsing History Page
/// Displays recently viewed posts in a clean responsive grid.
/// Free of emojis, using Material 3 aesthetics.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final HistoryService _historyService = HistoryService.instance;
  List<Map<String, dynamic>> _historyItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final items = await _historyService.getHistory();
    if (mounted) {
      setState(() {
        _historyItems = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteItem(String id) async {
    await _historyService.removeHistoryItem(id);
    _loadHistory();
  }

  void _showClearConfirmDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史'),
        content: const Text('确定要清空全部历史记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
              foregroundColor: Theme.of(ctx).colorScheme.onErrorContainer,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _historyService.clearHistory();
              _loadHistory();
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  int _calcColumns(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 1200) return 6;
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cols = _calcColumns(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('浏览历史'),
        actions: [
          if (_historyItems.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '清空',
              onPressed: _showClearConfirmDialog,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _historyItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 48,
                        color: cs.outline.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '无浏览历史',
                        style: TextStyle(
                          fontSize: 15,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadHistory,
                  child: MasonryGridView.count(
                    padding: const EdgeInsets.all(12),
                    crossAxisCount: cols,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    itemCount: _historyItems.length,
                    itemBuilder: (context, index) {
                      final item = _historyItems[index];
                      final idStr = item['id']?.toString() ?? '';
                      final previewUrl = item['preview_url'] as String? ??
                          item['sample_url'] as String? ??
                          item['file_url'] as String? ??
                          '';
                      final num width = item['width'] as num? ?? 1;
                      final num height = item['height'] as num? ?? 1;
                      final double aspectRatio = (width <= 0 || height <= 0)
                          ? 1.0
                          : (width / height).clamp(0.5, 2.0);

                      final site = item['site'] as String? ?? '';
                      final ratingObj = ContentRating.parse(
                        item['rating'],
                        siteId: site.isNotEmpty ? site : null,
                      );
                      final ratingLabel = ratingObj == ContentRating.unknown
                          ? ''
                          : ratingObj.englishLabel.toUpperCase();

                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          Navigator.push(
                            context,
                            SakuraPageRoute(
                              builder: (_) => PostDetailPage(
                                postData: item,
                                siteName: site.isNotEmpty ? site : null,
                              ),
                            ),
                          ).then((_) => _loadHistory());
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: cs.outlineVariant.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AspectRatio(
                                  aspectRatio: aspectRatio,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Hero(
                                        tag: 'post_hero_${item['site'] ?? 'post'}_${item['id'] ?? index}',
                                        child: SakuraAnimatedImage(
                                          imageUrl: previewUrl,
                                          siteId: site.isNotEmpty ? site : null,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      if (ratingLabel.isNotEmpty)
                                        Positioned(
                                          top: 6,
                                          left: 6,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              ratingLabel,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(16),
                                          onTap: () => _deleteItem(idStr),
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(
                                              color: Colors.black45,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.close_rounded,
                                              size: 14,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                                  child: Row(
                                    children: [
                                      if (site.isNotEmpty)
                                        Text(
                                          site,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: cs.primary,
                                          ),
                                        ),
                                      const Spacer(),
                                      Text(
                                        '#$idStr',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: cs.outline,
                                        ),
                                      ),
                                    ],
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
  }
}
