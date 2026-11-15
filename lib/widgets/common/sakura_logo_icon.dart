import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Minimalist line-art pink sakura emblem used in About / Drawer and previewed for launcher icon.
class SakuraLogoIcon extends StatelessWidget {
  final double size;
  final bool showBackgroundTile;
  final double borderRadiusRatio;

  const SakuraLogoIcon({
    super.key,
    this.size = 52,
    this.showBackgroundTile = true,
    this.borderRadiusRatio = 0.24,
  });

  /// Paints the minimalist 5-petal sakura icon onto [canvas] within [size].
  static void paintSakura(
    Canvas canvas,
    Size size, {
    bool showBackgroundTile = true,
    double borderRadiusRatio = 0.24,
  }) {
    final s = math.min(size.width, size.height);
    final rect = Rect.fromLTWH(
      (size.width - s) / 2,
      (size.height - s) / 2,
      s,
      s,
    );

    if (showBackgroundTile) {
      final rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(s * borderRadiusRatio),
      );
      final bgPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFFFF5F8),
            Color(0xFFFFE0EC),
          ],
        ).createShader(rect);
      canvas.drawRRect(rrect, bgPaint);

      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, s * 0.025)
        ..color = const Color(0xFFFFBBD2);
      canvas.drawRRect(rrect.deflate(borderPaint.strokeWidth / 2), borderPaint);
    }

    final cx = rect.center.dx;
    final cy = rect.center.dy + s * 0.012;
    final outerR = s * (showBackgroundTile ? 0.34 : 0.44);
    final notchDepth = outerR * 0.16;
    final widthAngle = 0.44; // half angular spread of each petal

    final petalFill = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFFFB2CE).withValues(alpha: 0.28);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, s * 0.036)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFEF6499);

    final innerMaskPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = showBackgroundTile
          ? const Color(0xFFFFEBF2)
          : const Color(0xFFFFFFFF);

    final innerDotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFEF6499);

    // Draw 5 clean rounded sakura petals with a gentle notch at each tip
    for (int i = 0; i < 5; i++) {
      final baseAngle = -math.pi / 2 + i * (2 * math.pi / 5);
      final path = _buildMinimalistPetalPath(
        cx: cx,
        cy: cy,
        angle: baseAngle,
        outerR: outerR,
        notchDepth: notchDepth,
        halfAngle: widthAngle,
      );
      canvas.drawPath(path, petalFill);
      canvas.drawPath(path, linePaint);
    }

    // Smooth center cap covers converging petal inner joints cleanly
    canvas.drawCircle(Offset(cx, cy), outerR * 0.21, innerMaskPaint);
    canvas.drawCircle(
      Offset(cx, cy),
      outerR * 0.21,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, s * 0.024)
        ..color = const Color(0xFFEF6499),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      math.max(1.4, outerR * 0.09),
      innerDotPaint,
    );
  }

  static Path _buildMinimalistPetalPath({
    required double cx,
    required double cy,
    required double angle,
    required double outerR,
    required double notchDepth,
    required double halfAngle,
  }) {
    final innerStartR = outerR * 0.20;
    final shoulderR = outerR * 0.88;
    final tipR = outerR - notchDepth;

    Offset polar(double r, double a) =>
        Offset(cx + r * math.cos(a), cy + r * math.sin(a));

    final p0 = polar(innerStartR, angle - halfAngle * 0.65);
    final cLeft1 = polar(outerR * 0.58, angle - halfAngle * 1.18);
    final leftLobe = polar(outerR, angle - halfAngle * 0.42);
    final cLeftTop = polar(shoulderR, angle - halfAngle * 0.96);

    final notchPoint = polar(tipR, angle);

    final rightLobe = polar(outerR, angle + halfAngle * 0.42);
    final cRightTop = polar(shoulderR, angle + halfAngle * 0.96);
    final cRight1 = polar(outerR * 0.58, angle + halfAngle * 1.18);
    final pEnd = polar(innerStartR, angle + halfAngle * 0.65);

    return Path()
      ..moveTo(p0.dx, p0.dy)
      ..cubicTo(
        cLeft1.dx,
        cLeft1.dy,
        cLeftTop.dx,
        cLeftTop.dy,
        leftLobe.dx,
        leftLobe.dy,
      )
      ..quadraticBezierTo(
        polar(outerR * 1.02, angle - halfAngle * 0.16).dx,
        polar(outerR * 1.02, angle - halfAngle * 0.16).dy,
        notchPoint.dx,
        notchPoint.dy,
      )
      ..quadraticBezierTo(
        polar(outerR * 1.02, angle + halfAngle * 0.16).dx,
        polar(outerR * 1.02, angle + halfAngle * 0.16).dy,
        rightLobe.dx,
        rightLobe.dy,
      )
      ..cubicTo(
        cRightTop.dx,
        cRightTop.dy,
        cRight1.dx,
        cRight1.dy,
        pEnd.dx,
        pEnd.dy,
      );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SakuraLogoPainter(
          showBackgroundTile: showBackgroundTile,
          borderRadiusRatio: borderRadiusRatio,
        ),
      ),
    );
  }
}

class _SakuraLogoPainter extends CustomPainter {
  final bool showBackgroundTile;
  final double borderRadiusRatio;

  const _SakuraLogoPainter({
    required this.showBackgroundTile,
    required this.borderRadiusRatio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    SakuraLogoIcon.paintSakura(
      canvas,
      size,
      showBackgroundTile: showBackgroundTile,
      borderRadiusRatio: borderRadiusRatio,
    );
  }

  @override
  bool shouldRepaint(covariant _SakuraLogoPainter oldDelegate) {
    return oldDelegate.showBackgroundTile != showBackgroundTile ||
        oldDelegate.borderRadiusRatio != borderRadiusRatio;
  }
}
