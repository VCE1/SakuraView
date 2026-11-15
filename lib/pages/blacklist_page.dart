import 'package:flutter/material.dart';
import 'package:vce1_sakuraview/services/blacklist_service.dart';

/// Tag Blacklist Page.
/// Adheres strictly to Less is More:
/// - Concise UI copy without instructional manuals
/// - Neutral, unified chip aesthetics
/// - Instant feedback, no emojis
class BlacklistPage extends StatefulWidget {
  const BlacklistPage({super.key});

  @override
  State<BlacklistPage> createState() => _BlacklistPageState();
}

class _BlacklistPageState extends State<BlacklistPage> {
  final BlacklistService _blacklistService = BlacklistService.instance;
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _blacklistService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _blacklistService.removeListener(_onServiceUpdate);
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _handleAddTag() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    final tagsToAdd = text
        .split(RegExp(r'[\s,]+'))
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toList();

    for (final tag in tagsToAdd) {
      await _blacklistService.addTag(tag);
    }

    _inputController.clear();
    _focusNode.requestFocus();
  }

  void _handleRemoveTag(String tag) async {
    await _blacklistService.removeTag(tag);
  }

  void _showClearConfirmDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空黑名单'),
        content: const Text('确定要清空所有屏蔽标签吗？'),
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
            onPressed: () {
              Navigator.of(ctx).pop();
              _blacklistService.clearAll();
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tags = _blacklistService.tags;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('黑名单'),
        actions: [
          if (tags.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '清空',
              onPressed: _showClearConfirmDialog,
            ),
        ],
      ),
      body: Column(
        children: [
          // Tag Input Row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    focusNode: _focusNode,
                    decoration: InputDecoration(
                      hintText: '输入标签',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _handleAddTag(),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _handleAddTag,
                  child: const Text('添加'),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Tags Display
          Expanded(
            child: tags.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.block_rounded,
                          size: 48,
                          color: cs.outline.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '无屏蔽标签',
                          style: TextStyle(
                            fontSize: 15,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: tags.map((tag) {
                          return InputChip(
                            label: Text(tag),
                            labelStyle: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface,
                            ),
                            backgroundColor: cs.surfaceContainerHighest,
                            deleteIcon: const Icon(Icons.close_rounded, size: 16),
                            onDeleted: () => _handleRemoveTag(tag),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: cs.outlineVariant.withValues(alpha: 0.4),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
