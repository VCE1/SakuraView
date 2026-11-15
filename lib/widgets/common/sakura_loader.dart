import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class SakuraLoader extends StatelessWidget {
  final double size;
  final String? label;

  const SakuraLoader({super.key, this.size = 48, this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Shimmer.fromColors(
        baseColor: cs.surfaceContainerHighest,
        highlightColor: cs.surface,
        period: const Duration(milliseconds: 1200),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(size / 4),
              ),
            ),
            if (label != null) ...[
              const SizedBox(height: 14),
              Container(
                width: 100,
                height: 12,
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SakuraProgressIndicator extends StatelessWidget {
  final double? value;
  final double height;

  const SakuraProgressIndicator({
    super.key,
    this.value,
    this.height = 3,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (value == null) {
      return Shimmer.fromColors(
        baseColor: cs.surfaceContainerHighest,
        highlightColor: cs.surface,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(height / 2),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: LinearProgressIndicator(
        value: value,
        minHeight: height,
        backgroundColor: cs.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
      ),
    );
  }
}

class SakuraGridShimmer extends StatelessWidget {
  final int columns;
  final int rows;

  const SakuraGridShimmer({super.key, this.columns = 3, this.rows = 12});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final sw = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final itemWidth =
            ((sw - 16 - (columns - 1) * 8) / columns).clamp(60.0, 600.0);

        return Shimmer.fromColors(
          baseColor: cs.surfaceContainerHighest,
          highlightColor: cs.surface,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(rows, (i) {
                final h = (140 + (i % 3) * 40).toDouble();
                return ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: itemWidth,
                    height: h,
                    color: cs.surface,
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}
