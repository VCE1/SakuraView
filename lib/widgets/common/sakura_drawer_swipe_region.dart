import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared horizontal swipe detector for opening left/right drawers or triggering left-side back gestures.
class SakuraDrawerSwipeDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSwipeRightFromLeft;
  final VoidCallback? onSwipeLeftFromRight;
  final double leftZoneFraction;
  final double rightZoneFraction;
  final double minLeftStartWidth;
  final double? maxLeftStartWidth;

  const SakuraDrawerSwipeDetector({
    super.key,
    required this.child,
    this.onSwipeRightFromLeft,
    this.onSwipeLeftFromRight,
    this.leftZoneFraction = 0.5,
    this.rightZoneFraction = 0.5,
    this.minLeftStartWidth = 0.0,
    this.maxLeftStartWidth,
  });

  @override
  State<SakuraDrawerSwipeDetector> createState() =>
      _SakuraDrawerSwipeDetectorState();
}

class _SakuraDrawerSwipeDetectorState extends State<SakuraDrawerSwipeDetector> {
  double? _startX;
  double _deltaX = 0.0;

  void _reset() {
    _startX = null;
    _deltaX = 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (details) {
        _startX = details.localPosition.dx;
        _deltaX = 0.0;
      },
      onHorizontalDragUpdate: (details) {
        if (_startX == null) return;
        _deltaX += details.primaryDelta ?? 0.0;
      },
      onHorizontalDragCancel: _reset,
      onHorizontalDragEnd: (details) {
        final startX = _startX;
        final deltaX = _deltaX;
        _reset();
        if (startX == null) return;

        final boxWidth = context.size?.width ?? MediaQuery.sizeOf(context).width;
        final vx = details.velocity.pixelsPerSecond.dx;

        final maxLeft = widget.maxLeftStartWidth != null
            ? math.min(
                boxWidth * widget.leftZoneFraction,
                widget.maxLeftStartWidth!,
              )
            : boxWidth * widget.leftZoneFraction;

        if (widget.onSwipeRightFromLeft != null &&
            startX >= widget.minLeftStartWidth &&
            startX <= maxLeft &&
            (deltaX >= 42 || vx >= 320)) {
          widget.onSwipeRightFromLeft!.call();
          return;
        }

        if (widget.onSwipeLeftFromRight != null &&
            startX >= boxWidth * (1.0 - widget.rightZoneFraction) &&
            (deltaX <= -42 || vx <= -320)) {
          widget.onSwipeLeftFromRight!.call();
        }
      },
      child: widget.child,
    );
  }
}
