import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Minimalist pastel sakura emblem: small 5-petal blossom in the bottom-left
/// paired with light drifting petal accents in the top-right over airy space.
class SakuraLogoIcon extends StatelessWidget {
  final double size;
  final bool showBackgroundTile;
  final double borderRadiusRatio;

  const SakuraLogoIcon({
    super.key,
    this.size = 52,
    this.showBackgroundTile = true,
    this.borderRadiusRatio = 0.22,
  });

  /// Paints the minimalist sakura mark onto [canvas] within [size].
  static void paintSakura(
    Canvas canvas,
    Size size, {
    bool showBackgroundTile = true,
    double borderRadiusRatio = 0.22,
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
      // Flat calm paper-blush backdrop instead of glossy gradients
      final bgPaint = Paint()..color = const Color(0xFFFCF7F9);
      canvas.drawRRect(rrect, bgPaint);

      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, s * 0.012)
        ..color = const Color(0xFFEDE0E5);
      canvas.drawRRect(rrect.deflate(borderPaint.strokeWidth / 2), borderPaint);
    }

    // Muted, low-saturation dusty sakura palette
    const lineColor = Color(0xFFD195A6);
    const fillColor = Color(0xFFF6E3E9);

    final petalFill = Paint()
      ..style = PaintingStyle.fill
      ..color = fillColor.withValues(alpha: 0.78);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.05, s * 0.017)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = lineColor;

    // Bottom-left compact 5-petal sakura (~40% smaller footprint, clean corner balance)
    final flowerCenter = Offset(
      rect.left + s * 0.31,
      rect.top + s * 0.69,
    );
    final outerR = s * (showBackgroundTile ? 0.18 : 0.21);
    const tiltOffset = -0.22;

    for (int i = 0; i < 5; i++) {
      final baseAngle = tiltOffset - math.pi / 2 + i * (2 * math.pi / 5);
      final path = _buildSimplePetalPath(
        origin: flowerCenter,
        angle: baseAngle,
        length: outerR,
        halfAngle: 0.42,
      );
      canvas.drawPath(path, petalFill);
      canvas.drawPath(path, linePaint);
    }

    // Minimalist stamen center dot
    canvas.drawCircle(
      flowerCenter,
      math.max(1.1, outerR * 0.10),
      Paint()..color = lineColor.withValues(alpha: 0.9),
    );

    // Top-right light asymmetric petal accents (rounded bases, zero sharp tips)
    _drawLoosePetal(
      canvas: canvas,
      center: Offset(rect.left + s * 0.75, rect.top + s * 0.25),
      length: s * 0.105,
      angle: -0.58,
      fillPaint: Paint()
        ..style = PaintingStyle.fill
        ..color = fillColor.withValues(alpha: 0.68),
      strokePaint: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.95, s * 0.014)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = lineColor.withValues(alpha: 0.85),
    );

    _drawLoosePetal(
      canvas: canvas,
      center: Offset(rect.left + s * 0.63, rect.top + s * 0.18),
      length: s * 0.062,
      angle: -1.02,
      fillPaint: Paint()
        ..style = PaintingStyle.fill
        ..color = fillColor.withValues(alpha: 0.50),
      strokePaint: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.85, s * 0.012)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = lineColor.withValues(alpha: 0.65),
    );
  }

  static Path _buildSimplePetalPath({
    required Offset origin,
    required double angle,
    required double length,
    required double halfAngle,
  }) {
    final innerR = length * 0.13;
    final tipR = length * 0.85;
    final shoulderR = length * 0.89;

    Offset polar(double r, double a) =>
        Offset(origin.dx + r * math.cos(a), origin.dy + r * math.sin(a));

    final p0 = polar(innerR, angle - halfAngle * 0.45);
    final cLeft1 = polar(length * 0.56, angle - halfAngle * 1.12);
    final leftLobe = polar(length, angle - halfAngle * 0.40);
    final cLeftTop = polar(shoulderR, angle - halfAngle * 0.92);

    final notchPoint = polar(tipR, angle);

    final rightLobe = polar(length, angle + halfAngle * 0.40);
    final cRightTop = polar(shoulderR, angle + halfAngle * 0.92);
    final cRight1 = polar(length * 0.56, angle + halfAngle * 1.12);
    final pEnd = polar(innerR, angle + halfAngle * 0.45);

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
        polar(length * 1.01, angle - halfAngle * 0.15).dx,
        polar(length * 1.01, angle - halfAngle * 0.15).dy,
        notchPoint.dx,
        notchPoint.dy,
      )
      ..quadraticBezierTo(
        polar(length * 1.01, angle + halfAngle * 0.15).dx,
        polar(length * 1.01, angle + halfAngle * 0.15).dy,
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

  static void _drawLoosePetal({
    required Canvas canvas,
    required Offset center,
    required double length,
    required double angle,
    required Paint fillPaint,
    required Paint strokePaint,
  }) {
    final origin = Offset(
      center.dx - length * 0.48 * math.cos(angle),
      center.dy - length * 0.48 * math.sin(angle),
    );
    Offset polar(double r, double a) =>
        Offset(origin.dx + r * math.cos(a), origin.dy + r * math.sin(a));

    final leftBase = polar(length * 0.14, angle - 0.55);
    final rightBase = polar(length * 0.14, angle + 0.55);
    final baseCtrl = polar(length * 0.02, angle + math.pi);
    final leftCtrl1 = polar(length * 0.46, angle - 0.56);
    final leftCtrl2 = polar(length * 0.88, angle - 0.44);
    final leftTip = polar(length, angle - 0.17);
    final leftShoulder = polar(length * 1.01, angle - 0.06);
    final notch = polar(length * 0.85, angle);
    final rightShoulder = polar(length * 1.01, angle + 0.06);
    final rightTip = polar(length, angle + 0.17);
    final rightCtrl2 = polar(length * 0.88, angle + 0.44);
    final rightCtrl1 = polar(length * 0.46, angle + 0.56);

    final path = Path()
      ..moveTo(leftBase.dx, leftBase.dy)
      ..cubicTo(
        leftCtrl1.dx,
        leftCtrl1.dy,
        leftCtrl2.dx,
        leftCtrl2.dy,
        leftTip.dx,
        leftTip.dy,
      )
      ..quadraticBezierTo(
        leftShoulder.dx,
        leftShoulder.dy,
        notch.dx,
        notch.dy,
      )
      ..quadraticBezierTo(
        rightShoulder.dx,
        rightShoulder.dy,
        rightTip.dx,
        rightTip.dy,
      )
      ..cubicTo(
        rightCtrl2.dx,
        rightCtrl2.dy,
        rightCtrl1.dx,
        rightCtrl1.dy,
        rightBase.dx,
        rightBase.dy,
      )
      ..quadraticBezierTo(
        baseCtrl.dx,
        baseCtrl.dy,
        leftBase.dx,
        leftBase.dy,
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
