import 'package:flutter/material.dart';
import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/providers/settings_provider.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_animated_image.dart';

/// 根据可视宽度、列数与设备像素比计算瀑布流缩略图解码宽度，防止后台因超高分辨率位图触发 LMK 强杀。
int computeGridTileCacheWidth(
  BuildContext context, {
  required int columns,
}) {
  final media = MediaQuery.of(context);
  final logicalTileWidth = media.size.width / (columns > 0 ? columns : 2);
  return (logicalTileWidth * media.devicePixelRatio).round().clamp(180, 900);
}

/// 后台静默预加载后续缩略图，受设置中的「预加载图片」开关控制。
void prefetchPostThumbnails(
  BuildContext context,
  List<Map<String, dynamic>> posts, {
  required int cacheWidth,
  int maxItems = 12,
}) {
  final settings = SettingsProvider.maybeOf(context, listen: false);
  if (settings != null && !settings.preloadImages) {
    return;
  }
  final target = posts.take(maxItems).toList();
  for (final post in target) {
    final url =
        (post['preview_url'] as String?) ?? (post['sample_url'] as String?) ?? '';
    if (url.isEmpty || SourceUrlResolver.isVideoMedia(url: url)) {
      continue;
    }
    final site = (post['site'] ?? post['site_id'])?.toString();
    final provider = ResizeImage.resizeIfNeeded(
      cacheWidth,
      null,
      createSiteImageProvider(url, siteId: site),
    );
    precacheImage(provider, context).catchError((_) {});
  }
}

/// 首页、搜索页与桌面端复用的统一作品瀑布流卡片。
class SakuraPostCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final int cacheWidth;
  final VoidCallback onTap;
  final bool? showGroupBadgeOverride;
  final bool? showR18BadgeOverride;

  const SakuraPostCard({
    super.key,
    required this.item,
    required this.cacheWidth,
    required this.onTap,
    this.showGroupBadgeOverride,
    this.showR18BadgeOverride,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = SettingsProvider.maybeOf(context);
    final showGroupBadge =
        showGroupBadgeOverride ?? (settings?.showGroupBadge ?? true);
    final showR18Badge =
        showR18BadgeOverride ?? (settings?.showR18Badge ?? true);

    final num imgWidth = item['preview_width'] as num? ??
        item['width'] as num? ??
        item['sample_width'] as num? ??
        1;
    final num imgHeight = item['preview_height'] as num? ??
        item['height'] as num? ??
        item['sample_height'] as num? ??
        1;
    final double aspectRatio = (imgWidth <= 0 || imgHeight <= 0)
        ? 1.0
        : (imgWidth / imgHeight).clamp(0.42, 2.4);

    final String imageUrl =
        item['preview_url'] as String? ?? item['sample_url'] as String? ?? '';
    final String site =
        (item['site'] ?? item['site_id'])?.toString() ?? 'post';
    final String rating =
        (item['rating'] as String? ?? 'unknown').toLowerCase();
    final String fileExt = (item['file_ext'] as String? ?? '').toLowerCase();

    final bool hasGroup = PostGroupHelper.hasGroup(item);
    final bool isExplicit = ContentRating.parse(rating, siteId: site).isExplicit;
    final bool isGif = const {
      'gif',
      'webm',
      'mp4',
      'webp',
      'mkv',
      'mov',
      'apng',
    }.contains(fileExt);
    final String postId = item['id']?.toString() ?? '';
    final String heroTag = 'post_hero_${site}_$postId';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.0),
          color: cs.surfaceContainerHighest.withAlpha(80),
          border: Border.all(
            color: cs.outlineVariant.withAlpha(90),
            width: 0.8,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: heroTag,
                child: SakuraAnimatedImage(
                  imageUrl: imageUrl,
                  siteId: site,
                  cacheWidth: cacheWidth,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  enableRetryTap: false,
                ),
              ),
              if ((showGroupBadge && hasGroup) || isGif)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showGroupBadge && hasGroup)
                        _SakuraCardBadge(
                          icon: Icons.photo_library_rounded,
                          text: '图组',
                          color: cs.primary.withAlpha(210),
                        ),
                      if (showGroupBadge && hasGroup && isGif)
                        const SizedBox(width: 4),
                      if (isGif)
                        _SakuraCardBadge(
                          text: fileExt.toUpperCase(),
                          color: cs.primaryContainer.withAlpha(210),
                          textColor: cs.onPrimaryContainer,
                        ),
                    ],
                  ),
                ),
              if (showR18Badge && isExplicit)
                Positioned(
                  top: 6,
                  right: 6,
                  child: _SakuraCardBadge(
                    text: 'R18',
                    color: cs.error.withAlpha(215),
                    textColor: cs.onError,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SakuraCardBadge extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color color;
  final Color textColor;

  const _SakuraCardBadge({
    required this.text,
    this.icon,
    required this.color,
    this.textColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: textColor),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: TextStyle(
              color: textColor,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
