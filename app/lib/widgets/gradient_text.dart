import 'package:flutter/material.dart';

/// text-gradient-flow 风格渐变文字：文字用渐变填充，并让渐变位置持续流动。
class GradientText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final List<Color> colors;
  final double fontSize;

  const GradientText({
    super.key,
    required this.text,
    this.style,
    this.colors = const [Color(0xFF454C84), Color(0xFF6E77B5), Color(0xFFA4ABD6), Color(0xFF6E77B5), Color(0xFF454C84)],
    this.fontSize = 12,
  });

  @override
  State<GradientText> createState() => _GradientTextState();
}

class _GradientTextState extends State<GradientText> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        // 渐变端点从左往右平滑移动，让颜色流动
        final begin = Alignment(-1.0 + 2 * t, 0);
        final end = Alignment(0.0 + 2 * t, 0);
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: begin,
            end: end,
            colors: widget.colors,
          ).createShader(bounds),
          child: Text(
            widget.text,
            textAlign: TextAlign.center,
            style: (widget.style ?? const TextStyle(fontWeight: FontWeight.w700)).copyWith(
              fontSize: widget.fontSize,
            ),
          ),
        );
      },
    );
  }
}
