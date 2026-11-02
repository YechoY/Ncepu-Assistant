// widgets/glass_page_header.dart —— 二级页顶部栏（返回按钮 + 标题）。
//
// 洗衣记录 / 消费记录等子页共用同一规格：
// 38×38 白玻璃圆角返回钮（点击 pop）+ 标题 18/w800。
// 模块差异只用 [GlassPageHeader.accentColor] 表达（返回箭头颜色）。

import 'package:flutter/material.dart';
import '../theme.dart';

class GlassPageHeader extends StatelessWidget {
  final String title;
  final Color accentColor;
  const GlassPageHeader({
    super.key,
    required this.title,
    this.accentColor = kPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: accentColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: kInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
