// glass_loading.dart —— 玻璃体系统一加载指示器。
//
// 替代裸 CircularProgressIndicator：细线宽 + 圆头，颜色默认墨色，
// 各模块传入主题色搭配（洗衣 kLaundryDeep / 饮水 kHuishDeep / 教务 kPrimary）。

import 'package:flutter/material.dart';

import '../theme.dart';

class GlassLoading extends StatelessWidget {
  const GlassLoading({super.key, this.color, this.size = 28});

  /// 转圈颜色：null 用墨色（kTextMain 75%），模块内传各自主题色。
  final Color? color;

  /// 直径（Material 默认 36，玻璃体系收窄到 28 更秀气）。
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        strokeCap: StrokeCap.round,
        color: color ?? kTextMain.withValues(alpha: 0.75),
      ),
    );
  }
}
