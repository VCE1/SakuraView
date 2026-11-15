import 'package:flutter/material.dart';
import 'package:vce1_sakuraview/core/utils/post_normalization.dart';

/// 顶部导航栏紧凑型内容分级快速切换胶囊（ALL / SAFE / R18）。
class RatingFilterPill extends StatelessWidget {
  final RatingFilterMode mode;
  final ValueChanged<RatingFilterMode> onSelected;
  final EdgeInsetsGeometry padding;

  const RatingFilterPill({
    super.key,
    required this.mode,
    required this.onSelected,
    this.padding = const EdgeInsets.only(right: 6),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color bgColor;
    final Color fgColor;
    final IconData icon;

    switch (mode) {
      case RatingFilterMode.r18:
        bgColor = cs.errorContainer.withAlpha(220);
        fgColor = cs.onErrorContainer;
        icon = Icons.explicit_rounded;
        break;
      case RatingFilterMode.safe:
        bgColor = cs.secondaryContainer.withAlpha(200);
        fgColor = cs.onSecondaryContainer;
        icon = Icons.shield_outlined;
        break;
      case RatingFilterMode.all:
        bgColor = cs.surfaceContainerHighest.withAlpha(200);
        fgColor = cs.onSurfaceVariant;
        icon = Icons.layers_outlined;
        break;
    }

    return Padding(
      padding: padding,
      child: PopupMenuButton<RatingFilterMode>(
        tooltip: '内容分级 (${mode.displayLabel})',
        initialValue: mode,
        onSelected: onSelected,
        offset: const Offset(0, 38),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        itemBuilder: (ctx) => RatingFilterMode.values
            .map(
              (item) => PopupMenuItem<RatingFilterMode>(
                value: item,
                child: Row(
                  children: [
                    Icon(
                      item == mode
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 18,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(item.displayLabel),
                  ],
                ),
              ),
            )
            .toList(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: cs.outlineVariant.withAlpha(140),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: fgColor),
              const SizedBox(width: 4),
              Text(
                mode.shortLabel,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: fgColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
