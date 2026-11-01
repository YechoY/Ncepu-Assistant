import 'package:flutter/material.dart';

import '../theme.dart';
import 'glass_card.dart';

class CapsuleNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const CapsuleNav({super.key, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const labels = ['课表', '成绩', '考试', '教室'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: GlassCard(
        radius: 24,
        padding: const EdgeInsets.all(5),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    // 出场（成为选中项）用 spring 的弹性入场；
                    // 退场（旧选中项）用短时长 easeOut 快速消失——
                    // 420ms spring 的减速长尾会让旧按钮上的紫底/柔光残留很久，
                    // 肉眼看就是「残影赖在原按钮上」。
                    duration: i == index
                        ? const Duration(milliseconds: 300)
                        : const Duration(milliseconds: 150),
                    curve: i == index ? kSpring : Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      // 选中：雾蓝紫实底 + 同色柔光；未选：透明（露出玻璃条本身）
                      color: i == index ? kPrimary : Colors.transparent,
                      borderRadius: BorderRadius.circular(19),
                      boxShadow: i == index
                          ? [
                              BoxShadow(
                                color: kPrimary.withValues(alpha: 0.38),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            i == index ? FontWeight.w700 : FontWeight.w500,
                        color: i == index ? Colors.white : kTextMuted,
                      ),
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
