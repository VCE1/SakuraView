import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vce1_sakuraview/providers/recent_tags_notifier.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_page_route.dart';
import 'package:vce1_sakuraview/widgets/common/search_results_page.dart';

/// 参考 JHenTai 的右侧滑出式快速搜索抽屉（从主屏右半侧左滑呼出）。
class QuickSearchDrawer extends StatefulWidget {
  const QuickSearchDrawer({super.key});

  @override
  State<QuickSearchDrawer> createState() => _QuickSearchDrawerState();
}

class _QuickSearchDrawerState extends State<QuickSearchDrawer> {
  final TextEditingController _inputCtrl = TextEditingController();

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  void _openSearchResults(
    BuildContext context, {
    required String query,
    String uploader = '',
    String artist = '',
    String? sort,
  }) {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty && uploader.trim().isEmpty && artist.trim().isEmpty) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    if (cleanQuery.isNotEmpty) {
      context.read<RecentTagsNotifier>().addTag(cleanQuery);
    }
    final navigator = Navigator.of(context);
    navigator.pop(); // 关闭 endDrawer 后压入搜索结果页，返回时直接回到前一页面
    navigator.push(
      SakuraPageRoute(
        builder: (_) => SearchResultsPage(
          query: cleanQuery,
          uploader: uploader,
          artist: artist,
          sort: sort,
        ),
      ),
    );
  }

  Future<void> _showAddPresetDialog(BuildContext context) async {
    final labelCtrl = TextEditingController();
    final queryCtrl = TextEditingController(text: _inputCtrl.text.trim());
    final artistCtrl = TextEditingController();
    final uploaderCtrl = TextEditingController();
    final notifier = context.read<RecentTagsNotifier>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增快速搜索预设'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(
                  labelText: '预设名称 (选填)',
                  hintText: '例如：蓝瞳少女 / 画师合集',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: queryCtrl,
                decoration: const InputDecoration(
                  labelText: '标签关键词',
                  hintText: '如 blue_eyes long_hair',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: artistCtrl,
                decoration: const InputDecoration(
                  labelText: '画师筛选 (选填)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: uploaderCtrl,
                decoration: const InputDecoration(
                  labelText: '上传者筛选 (选填)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              if (queryCtrl.text.trim().isEmpty &&
                  artistCtrl.text.trim().isEmpty &&
                  uploaderCtrl.text.trim().isEmpty) {
                return;
              }
              await notifier.addQuickSearch(
                label: labelCtrl.text.trim(),
                query: queryCtrl.text.trim(),
                artist: artistCtrl.text.trim(),
                uploader: uploaderCtrl.text.trim(),
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存预设'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final recent = context.watch<RecentTagsNotifier>();
    final presets = recent.quickSearches;
    final history = recent.tags;

    return Drawer(
      width: 316,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.bolt_rounded, color: cs.primary, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '快速搜索',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '直达预设标签或最近检索',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '新增快速搜索预设',
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    onPressed: () => _showAddPresetDialog(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _inputCtrl,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: '输入标签并回车搜索',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 19),
                  suffixIcon: IconButton(
                    tooltip: '搜索',
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    onPressed: () => _openSearchResults(
                      context,
                      query: _inputCtrl.text,
                    ),
                  ),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withAlpha(150),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (val) => _openSearchResults(context, query: val),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                children: [
                  Row(
                    children: [
                      Text(
                        '收藏预设 (${presets.length})',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _showAddPresetDialog(context),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('新建'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                  if (presets.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: cs.outlineVariant.withAlpha(70),
                        ),
                      ),
                      child: Text(
                        '暂无预设，可在右上角点击「+」添加，或在搜索结果页点击书签图标一键收藏。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    )
                  else
                    ...presets.map(
                      (entry) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        elevation: 0,
                        color: cs.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: cs.outlineVariant.withAlpha(80),
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          leading: Icon(
                            Icons.bookmark_rounded,
                            size: 18,
                            color: cs.primary,
                          ),
                          title: Text(
                            entry.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: entry.subtitle.isNotEmpty
                              ? Text(
                                  entry.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
                                )
                              : null,
                          trailing: IconButton(
                            tooltip: '删除预设',
                            icon: const Icon(Icons.close_rounded, size: 17),
                            onPressed: () => recent.removeQuickSearch(entry.id),
                          ),
                          onTap: () => _openSearchResults(
                            context,
                            query: entry.query,
                            uploader: entry.uploader,
                            artist: entry.artist,
                            sort: entry.sort,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        '最近历史 (${history.length})',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      if (history.isNotEmpty)
                        TextButton(
                          onPressed: () => recent.clear(),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('清空'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (history.isEmpty)
                    Text(
                      '暂无最近搜索记录',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: history
                          .map(
                            (tag) => ActionChip(
                              label: Text(tag, style: const TextStyle(fontSize: 12)),
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  _openSearchResults(context, query: tag),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
