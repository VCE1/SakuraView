import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// 作品分享选项弹窗：支持「直接复制分享文本 / 复制链接」，无需强制跳转第三方应用。
Future<void> showShareOptionsSheet({
  required BuildContext context,
  required String shareText,
  required String subject,
  String? linkToCopy,
  String? localFilePath,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final cleanLink = (linkToCopy ?? '').trim();

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) {
      final theme = Theme.of(sheetCtx);
      final cs = theme.colorScheme;

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
              child: Text(
                '分享作品',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.45),
                  ),
                ),
                child: SelectableText(
                  shareText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.45,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.copy_all_rounded, color: cs.primary),
              title: const Text('复制分享内容'),
              subtitle: const Text('仅复制标题与链接到剪贴板，不打开第三方应用'),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: shareText));
                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text('已复制分享内容到剪贴板'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
              },
            ),
            if (cleanLink.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.link_rounded),
                title: const Text('仅复制作品链接'),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: cleanLink));
                  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text('已复制作品链接到剪贴板'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                },
              ),
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: const Text('通过第三方应用分享'),
              subtitle: const Text('调起系统分享面板发送图片或链接'),
              onTap: () async {
                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                try {
                  final renderObj = sheetCtx.findRenderObject();
                  final box = renderObj is RenderBox ? renderObj : null;
                  final shareOrigin = (box != null && box.hasSize)
                      ? (box.localToGlobal(Offset.zero) & box.size)
                      : Rect.fromCenter(
                          center: MediaQuery.sizeOf(context).center(Offset.zero),
                          width: 1,
                          height: 1,
                        );
                  final local = localFilePath?.trim() ?? '';
                  if (local.isNotEmpty && await File(local).exists()) {
                    await SharePlus.instance.share(
                      ShareParams(
                        files: [XFile(local)],
                        text: shareText,
                        subject: subject,
                        sharePositionOrigin: shareOrigin,
                      ),
                    );
                  } else {
                    await SharePlus.instance.share(
                      ShareParams(
                        text: shareText,
                        subject: subject,
                        sharePositionOrigin: shareOrigin,
                      ),
                    );
                  }
                } catch (_) {
                  await Clipboard.setData(ClipboardData(text: shareText));
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text('已复制分享内容到剪贴板'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
          ),
        ),
      );
    },
  );
}
