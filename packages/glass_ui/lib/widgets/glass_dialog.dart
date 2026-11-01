// widgets/glass_dialog.dart —— 玻璃风确认弹窗（公共组件）。
// 样式：GlassCard 包裹 + 标题 + 正文 + 取消/确认 pill 按钮。
// [cancelText] 为空时只显示一个确认按钮（铺满整行）；否则「取消 + 确认」并排。
// [destructive] = 确认按钮用柔和红（退出登录等危险操作）。
// 点确认 → Navigator.pop(context, [popResult])，由 showDialog 的返回值接住。

import 'package:flutter/material.dart';
import '../theme.dart';
import 'glass_card.dart';

class GlassDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final String confirmText;
  final String? cancelText;
  final bool destructive;
  final Object? popResult;
  const GlassDialog({
    super.key,
    required this.title,
    required this.content,
    required this.confirmText,
    this.cancelText,
    this.destructive = false,
    this.popResult,
  });

  @override
  Widget build(BuildContext context) {
    final tone = destructive ? const Color(0xFFB85450) : kPrimary;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: GlassCard(
        radius: 22,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: kInk,
              ),
            ),
            const SizedBox(height: 8),
            content,
            const SizedBox(height: 16),
            if (cancelText == null)
              _pill(
                context,
                confirmText,
                Colors.white,
                bg: tone.withValues(alpha: 0.92),
                onTap: () => Navigator.pop(context, popResult),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _pill(
                      context,
                      cancelText!,
                      kTextMain,
                      bg: Colors.white.withValues(alpha: 0.5),
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _pill(
                      context,
                      confirmText,
                      Colors.white,
                      bg: tone.withValues(alpha: 0.92),
                      onTap: () => Navigator.pop(context, popResult),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _pill(
    BuildContext context,
    String label,
    Color textColor, {
    required Color bg,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: kSpring,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
      ),
    );
  }
}
