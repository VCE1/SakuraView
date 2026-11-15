import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vce1_sakuraview/services/blacklist_service.dart';
import 'package:vce1_sakuraview/services/followed_tags_service.dart';

/// 长按标签或历史词条时弹出的统一操作面板：支持搜索、特别关注、加入黑名单及复制标签。
Future<void> showTagActionSheet(
  BuildContext context,
  String rawTag, {
  VoidCallback? onSearchTag,
}) async {
  final cleanTag = rawTag.trim();
  if (cleanTag.isEmpty) return;

  final messenger = ScaffoldMessenger.of(context);
  final blacklist = BlacklistService.instance;
  final followed = FollowedTagsService.instance;
  final displayTag = cleanTag.replaceAll('_', ' ');

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) {
      return ListenableBuilder(
        listenable: Listenable.merge([blacklist, followed]),
        builder: (ctx, _) {
          final cs = Theme.of(ctx).colorScheme;
          final isFollowed = followed.isFollowed(cleanTag);
          final isBlocked = blacklist.tags.contains(cleanTag.toLowerCase());

          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        displayTag,
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      if (displayTag != cleanTag) ...[
                        const SizedBox(height: 2),
                        SelectableText(
                          cleanTag,
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (onSearchTag != null)
                  ListTile(
                    leading: const Icon(Icons.search_rounded),
                    title: const Text('搜索此标签'),
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      onSearchTag();
                    },
                  ),
                ListTile(
                  leading: Icon(
                    isFollowed ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: isFollowed ? cs.primary : null,
                  ),
                  title: Text(isFollowed ? '取消特别关注' : '加入特别关注'),
                  subtitle: Text(
                    isFollowed ? '已保存在搜索页「特别关注」分组中' : '收藏常用画师、角色或偏好题材',
                  ),
                  onTap: () async {
                    await followed.toggleTag(cleanTag);
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.block_rounded,
                    color: isBlocked ? cs.error : null,
                  ),
                  title: Text(isBlocked ? '移出标签黑名单' : '加入标签黑名单'),
                  subtitle: Text(
                    isBlocked ? '恢复显示包含该标签的作品' : '隐藏首页与搜索结果中包含该标签的作品',
                  ),
                  onTap: () async {
                    if (isBlocked) {
                      await blacklist.removeTag(cleanTag);
                    } else {
                      await blacklist.addTag(cleanTag);
                    }
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.content_copy_rounded),
                  title: const Text('复制标签名称'),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: cleanTag));
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                    messenger
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text('已复制标签: $cleanTag'),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                  },
                ),
                const SizedBox(height: 8),
              ],
              ),
            ),
          );
        },
      );
    },
  );
}
