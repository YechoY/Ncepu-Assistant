import 'package:flutter/material.dart';

/// 浅色渐变 + 模糊光斑背景：玻璃拟态卡片透出这些光斑才有"毛玻璃"效果。
class GlassBackground extends StatelessWidget {
  final Widget child;
  const GlassBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE8F1FF),
            Color(0xFFF0EFFF),
            Color(0xFFE7F6F5),
            Color(0xFFF7F9FD),
          ],
        ),
      ),
      child: Stack(
        children: [
          // 光斑：给玻璃卡片提供"可透"的丰富背景
          const _BlurOrb(top: -60, left: -40, size: 200, color: Color(0xFFBFDBFE)),
          const _BlurOrb(top: 90, right: -50, size: 260, color: Color(0xFFDDD6FE)),
          const _BlurOrb(bottom: -70, left: 40, size: 220, color: Color(0xFFBAE6FD)),
          child,
        ],
      ),
    );
  }
}

class _BlurOrb extends StatelessWidget {
  final double? top, bottom, left, right;
  final double size;
  final Color color;
  const _BlurOrb({this.top, this.bottom, this.left, this.right, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.6), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
