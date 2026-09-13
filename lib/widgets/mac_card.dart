import 'package:flutter/material.dart';

/// macOS 风格卡片容器：实色白底 + 多层柔和投影 + 细微高光描边 + 大圆角。
/// 可选左侧彩色强调条 [accent]，用于给卡片一点主题色点缀（如课程配色）。
///
/// 设计要点（模仿 macOS/Big Sur 卡片）：
/// - 大圆角(默认 16)让轮廓更柔和；
/// - 两层阴影叠加：近处一层较实（贴地感），远处一层大扩散低透明（悬浮感）；
/// - 顶部一条极淡的白色内高光描边，模拟光从上方打下来的质感；
/// - 背景用实色（白），符合“实色卡+深投影”的取向。
class MacCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final double radius;
  final Color background;
  final Color? accent; // 左侧强调条颜色；null=不显示
  final VoidCallback? onTap;

  const MacCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.margin = EdgeInsets.zero,
    this.radius = 16,
    this.background = Colors.white,
    this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
        // 细微高光描边：半透明白，弱化边界又保留层次
        border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 1),
        boxShadow: [
          // 远处大扩散阴影：营造悬浮感
          BoxShadow(
            color: const Color(0xFF1E293B).withValues(alpha: 0.10),
            blurRadius: 20,
            spreadRadius: -4,
            offset: const Offset(0, 10),
          ),
          // 近处小阴影：贴地、加重边缘立体感
          BoxShadow(
            color: const Color(0xFF1E293B).withValues(alpha: 0.06),
            blurRadius: 6,
            spreadRadius: -2,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      // 用 ClipRRect 裁掉溢出，保证左侧强调条与圆角贴合
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (accent != null)
                Container(width: 4, color: accent),
              Expanded(
                child: Padding(padding: padding, child: child),
              ),
            ],
          ),
        ),
      ),
    );

    final withMargin = Padding(padding: margin, child: card);
    if (onTap == null) return withMargin;
    // 点击有轻微涟漪反馈，圆角与卡片一致
    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: card,
        ),
      ),
    );
  }
}
