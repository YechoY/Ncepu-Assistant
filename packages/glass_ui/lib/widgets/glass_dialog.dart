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

  /// 点确认的自定义行为（如文本输入弹窗返回输入值）。
  /// 为空时默认 Navigator.pop(context, [popResult])。
  final VoidCallback? onConfirm;
  final Object? popResult;

  /// 确认按钮/主色调。默认全局主题色；模块化场景可传模块色（如洗衣粉）。
  final Color? accentColor;
  const GlassDialog({
    super.key,
    required this.title,
    required this.content,
    required this.confirmText,
    this.cancelText,
    this.destructive = false,
    this.onConfirm,
    this.popResult,
    this.accentColor,
  });

  /// 确认型弹窗便利方法：点确认返回 true，取消/关闭返回 false。
  /// [destructive] 时确认键为警示红（删除/退出等高危操作），优先级高于 [accentColor]。
  /// [accentColor] 可指定模块主色（如洗衣粉），缺省用全局主题色。
  static Future<bool> showConfirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = '确定',
    String cancelText = '取消',
    bool destructive = false,
    Color? accentColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => GlassDialog(
        title: title,
        content: Text(
          message,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.55,
            color: kTextMuted,
          ),
        ),
        confirmText: confirmText,
        cancelText: cancelText,
        destructive: destructive,
        accentColor: accentColor,
        popResult: true,
      ),
    ).then((v) => v == true);
  }

  /// 文本输入弹窗（重命名/新建分组等共用）：玻璃输入框 + 取消/确定，
  /// 点确定返回输入内容（trim 过），取消/关闭返回 null。
  static Future<String?> showText(
    BuildContext context, {
    required String title,
    String initial = '',
    String? hint,
    Color? accentColor,
    String confirmText = '确定',
    String cancelText = '取消',
  }) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => GlassDialog(
        title: title,
        accentColor: accentColor,
        content: TextField(
          controller: c,
          autofocus: true,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: kTextMain,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 12.5,
              color: kTextMuted.withValues(alpha: 0.7),
            ),
            isDense: true,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.6),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: (accentColor ?? kPrimary).withValues(alpha: 0.55),
                width: 1.4,
              ),
            ),
          ),
        ),
        cancelText: cancelText,
        confirmText: confirmText,
        onConfirm: () => Navigator.of(ctx).pop(c.text.trim()),
      ),
    ).whenComplete(() {
      // pop 完成时 TextField 仍在退场动画中挂在树上，立即 dispose controller
      // 会触发 framework 的 _dependents.isEmpty 断言（红屏），延迟到动画结束后释放
      Future.delayed(const Duration(milliseconds: 600), c.dispose);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tone = destructive
        ? const Color(0xFFB85450)
        : (accentColor ?? kPrimary);
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
                fontSize: 17,
                fontWeight: FontWeight.w800,
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
                onTap: onConfirm ?? () => Navigator.pop(context, popResult),
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
                      onTap: onConfirm ?? () => Navigator.pop(context, popResult),
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
