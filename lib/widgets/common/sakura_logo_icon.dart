import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Crisp minimalist sakura emblem: soft pastel 5-petal blossom tucked toward
/// the bottom-left with light drifting petals in the top-right.
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

  /// Paints the minimalist sakura mark onto [canvas] within [size].
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

    const tileBgColor = Color(0xFFFFFAFC);
    const tileBorderColor = Color(0xFFF6DCE5);
    const strokePink = Color(0xFFEA84A7);
    const fillPink = Color(0xFFFDE6EE);

    if (showBackgroundTile) {
      final rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(s * borderRadiusRatio),
      );
      canvas.drawRRect(rrect, Paint()..color = tileBgColor);

      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, s * 0.016)
        ..color = tileBorderColor;
      canvas.drawRRect(rrect.deflate(borderPaint.strokeWidth / 2), borderPaint);
    }

    final petalFill = Paint()
      ..style = PaintingStyle.fill
      ..color = fillPink.withValues(alpha: 0.72);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.25, s * 0.023)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = strokePink;

    // Main 5-petal sakura shrunk ~40% (outerR = 0.21 vs 0.34) near bottom-left
    final flowerCenter = Offset(
      rect.left + s * 0.34,
      rect.top + s * 0.65,
    );
    final outerR = s * (showBackgroundTile ? 0.21 : 0.24);
    const tiltOffset = -0.14;

    for (int i = 0; i < 5; i++) {
      final baseAngle = tiltOffset - math.pi / 2 + i * (2 * math.pi / 5);
      final path = _buildMinimalistPetalPath(
        cx: flowerCenter.dx,
        cy: flowerCenter.dy,
        angle: baseAngle,
        outerR: outerR,
        notchDepth: outerR * 0.16,
        halfAngle: 0.44,
      );
      canvas.drawPath(path, petalFill);
      canvas.drawPath(path, linePaint);
    }

    // Crisp open circular center prevents inner petal strokes from tangling
    final centerCoverColor = showBackgroundTile ? tileBgColor : Colors.white;
    canvas.drawCircle(
      flowerCenter,
      outerR * 0.22,
      Paint()..color = centerCoverColor,
    );
    canvas.drawCircle(
      flowerCenter,
      outerR * 0.22,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.1, s * 0.018)
        ..color = strokePink,
    );
    canvas.drawCircle(
      flowerCenter,
      math.max(1.2, outerR * 0.095),
      Paint()..color = strokePink,
    );

    // Top-right slender floating sakura petals (elongated proportions, shallow notch)
    _drawSinglePetal(
      canvas: canvas,
      center: Offset(rect.left + s * 0.74, rect.top + s * 0.26),
      length: s * 0.135,
      angle: -0.62,
      fillPaint: Paint()
        ..style = PaintingStyle.fill
        ..color = fillPink.withValues(alpha: 0.72),
      strokePaint: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.05, s * 0.017)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = strokePink.withValues(alpha: 0.92),
    );

    _drawSinglePetal(
      canvas: canvas,
      center: Offset(rect.left + s * 0.62, rect.top + s * 0.17),
      length: s * 0.088,
      angle: -1.12,
      fillPaint: Paint()
        ..style = PaintingStyle.fill
        ..color = fillPink.withValues(alpha: 0.56),
      strokePaint: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.95, s * 0.014)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = strokePink.withValues(alpha: 0.78),
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

  /// Renders a slender single drifting sakura petal with a gentle tip cleft.
  static void _drawSinglePetal({
    required Canvas canvas,
    required Offset center,
    required double length,
    required double angle,
    required Paint fillPaint,
    required Paint strokePaint,
  }) {
    final baseOrigin = Offset(
      center.dx - length * 0.50 * math.cos(angle),
      center.dy - length * 0.50 * math.sin(angle),
    );
    const halfAngle = 0.28;
    Offset polar(double r, double a) =>
        Offset(baseOrigin.dx + r * math.cos(a), baseOrigin.dy + r * math.sin(a));

    final startBase = polar(length * 0.08, angle - halfAngle * 0.50);
    final endBase = polar(length * 0.08, angle + halfAngle * 0.50);
    final baseCurveCtrl = polar(-length * 0.02, angle);

    final cLeft1 = polar(length * 0.45, angle - halfAngle * 1.25);
    final cLeftTop = polar(length * 0.85, angle - halfAngle * 1.05);
    final leftLobe = polar(length, angle - halfAngle * 0.44);
    final notch = polar(length * 0.91, angle);
    final rightLobe = polar(length, angle + halfAngle * 0.44);
    final cRightTop = polar(length * 0.85, angle + halfAngle * 1.05);
    final cRight1 = polar(length * 0.45, angle + halfAngle * 1.25);

    final path = Path()
      ..moveTo(startBase.dx, startBase.dy)
      ..cubicTo(
        cLeft1.dx,
        cLeft1.dy,
        cLeftTop.dx,
        cLeftTop.dy,
        leftLobe.dx,
        leftLobe.dy,
      )
      ..quadraticBezierTo(
        polar(length * 1.01, angle - halfAngle * 0.16).dx,
        polar(length * 1.01, angle - halfAngle * 0.16).dy,
        notch.dx,
        notch.dy,
      )
      ..quadraticBezierTo(
        polar(length * 1.01, angle + halfAngle * 0.16).dx,
        polar(length * 1.01, angle + halfAngle * 0.16).dy,
        rightLobe.dx,
        rightLobe.dy,
      )
      ..cubicTo(
        cRightTop.dx,
        cRightTop.dy,
        cRight1.dx,
        cRight1.dy,
        endBase.dx,
        endBase.dy,
      )
      ..quadraticBezierTo(
        baseCurveCtrl.dx,
        baseCurveCtrl.dy,
        startBase.dx,
        startBase.dy,
      )
      ..close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);
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
