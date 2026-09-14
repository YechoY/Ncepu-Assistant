import 'package:flutter/material.dart';

import '../theme.dart';

/// 玻璃拟态卡片（浅色版 Nocturne Glass 手法）。
///
/// 三层结构（对应 STYLEKIT 玻璃面板规范的浅色翻译）：
/// 1. 高倍高斯模糊 + 饱和度增强：透出的背景光斑被柔化、提亮（[glassBlurFilter]）；
/// 2. 顶部内发光：白色渐变从顶缘向下衰减，模拟光从上方打在玻璃表面；
/// 3. 方向性光影：白色高光描边 + 底部 1px 暗缘 + 外层冷调柔影。
///
/// 阴影画在 ClipRRect 外层（否则会被裁掉），模糊与描边画在裁剪层内。
class GlassCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blur;
  final double opacity;
  final EdgeInsetsGeometry padding;
  final Color tintColor;
  final double? width;
  final double? height;

  /// 是否做实时背景模糊。列表里卡片很多时，每张卡一个 BackdropFilter 会让
  /// 滚动明显掉帧；这种场景用 live:false 的「静态磨砂」（不透背景的乳白玻璃，
  /// 保留高光边/暗缘/柔影，观感接近、绘制开销几乎为零）。
  final bool live;

  const GlassCard({
    super.key,
    required this.child,
    this.radius = 22,
    this.blur = kGlassBlur,
    this.opacity = kGlassAlpha,
    this.padding = const EdgeInsets.all(16),
    this.tintColor = kGlassTint,
    this.width,
    this.height,
    this.live = true,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(this.radius);
    final body = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: tintColor.withValues(alpha: opacity),
        borderRadius: radius,
        border: Border.all(color: kGlassBorder, width: 1),
      ),
      child: Stack(
        children: [
          // 第 2 层：顶部内发光（上缘白色高光向内衰减）
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 48,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.55),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 底部 1px 暗缘（背光面），与顶边高光形成光的方向
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 1,
            child: IgnorePointer(
              child: ColoredBox(
                color: const Color(0xFF3D4670).withValues(alpha: 0.07),
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          // 远处大扩散冷影：悬浮感
          BoxShadow(color: kGlassShadow, blurRadius: 28, offset: Offset(0, 10)),
          // 近处贴地小影
          BoxShadow(
            color: Color(0x143D4670),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: live
            ? BackdropFilter(
                filter: glassBlurFilter(sigma: blur),
                child: body,
              )
            : body,
      ),
    );
  }
}
