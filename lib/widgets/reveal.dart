import 'package:flutter/material.dart';

/// scroll-reveal 风格入场动画：子组件挂载后淡入 + 向上位移。
/// 配合 ListView.builder，滚动到新构建的项时触发，产生"进入视口显现"效果。
class Reveal extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Offset offset;
  final double minScale;

  const Reveal({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 600),
    this.offset = const Offset(0, 28),
    this.minScale = 0.96,
  });

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: widget.offset,
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(
            begin: widget.minScale,
            end: 1.0,
          ).animate(curved),
          child: widget.child,
        ),
      ),
    );
  }
}
