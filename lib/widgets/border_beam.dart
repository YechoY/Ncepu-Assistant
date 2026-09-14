import 'package:flutter/material.dart';

import '../theme.dart';

/// 渐变发光边框：整个矩形边框是一圈粉彩渐变色（樱花粉→雾蓝紫→天青蓝），并带柔和发光。
/// 替代"单束流光"，更干净耐看。
class BorderBeam extends StatelessWidget {
  final Widget child;
  final double radius;
  final double strokeWidth;
  final LinearGradient borderGradient;

  const BorderBeam({
    super.key,
    required this.child,
    this.radius = 14,
    this.strokeWidth = 1.6,
    this.borderGradient = const LinearGradient(
      colors: [kAccentPink, kPrimarySoft, Color(0xFFA2D2E2), kAccentPink],
    ),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: kPrimarySoft.withValues(alpha: 0.22),
            blurRadius: 12,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _GradientBorderPainter(
                    radius: radius,
                    strokeWidth: strokeWidth,
                    gradient: borderGradient,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientBorderPainter extends CustomPainter {
  final double radius;
  final double strokeWidth;
  final LinearGradient gradient;

  _GradientBorderPainter({
    required this.radius,
    required this.strokeWidth,
    required this.gradient,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2, size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = gradient.createShader(Offset.zero & size);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _GradientBorderPainter old) =>
      old.radius != radius || old.strokeWidth != strokeWidth || old.gradient != gradient;
}
