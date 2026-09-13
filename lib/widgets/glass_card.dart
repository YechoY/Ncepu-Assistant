import 'dart:ui';

import 'package:flutter/material.dart';

/// 玻璃拟态卡片：半透明背景 + 背景模糊 + 细白高光边框 + 大圆角 + 多层阴影。
class GlassCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blur;
  final double opacity;
  final EdgeInsetsGeometry padding;
  final Color tintColor;
  final double? width;
  final double? height;

  const GlassCard({
    super.key,
    required this.child,
    this.radius = 20,
    this.blur = 16,
    this.opacity = 0.14,
    this.padding = const EdgeInsets.all(16),
    this.tintColor = Colors.white,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            width: width,
            height: height,
            padding: padding,
            decoration: BoxDecoration(
              color: tintColor.withValues(alpha: opacity),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
                // 内高光，模拟光从上方落在玻璃边缘
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.35),
                  blurRadius: 0,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
