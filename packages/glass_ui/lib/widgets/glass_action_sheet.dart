// widgets/glass_action_sheet.dart —— 玻璃风操作菜单弹窗（公共组件）。
//
// 居中弹出的设备/对象操作菜单：标题 + 若干操作行（淡主色底 + 水波），
// 支持小节标题（如「移动到分组」）。洗衣/饮水的设备操作菜单共用一套规格，
// 模块差异只用 [GlassActionSheet.accentColor] 表达。

import 'package:flutter/material.dart';
import '../theme.dart';
import 'glass_card.dart';

/// 一条操作项；[section] 非空时在该行上方插入小节标题。
class GlassAction {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// 覆盖 icon 与文字颜色（如警示红）。
  final Color? color;

  /// 行尾附件（如当前分组 ✓）。
  final Widget? trailing;
  final String? section;
  const GlassAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
    this.trailing,
    this.section,
  });
}

/// 单条操作行：淡主色底 + 水波反馈。菜单弹窗与底部面板通用。
class GlassActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final Widget? trailing;
  final Color accentColor;
  const GlassActionRow(
    this.icon,
    this.label, {
    super.key,
    this.onTap,
    this.color,
    this.trailing,
    this.accentColor = kPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: accentColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 21,
                  color: color ?? accentColor.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: color ?? kTextMain,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 操作菜单弹窗壳：透明 Dialog + 限宽 380 玻璃卡 + 居中标题 + 操作行列表。
/// 用法：showDialog(context, builder: (_) => GlassActionSheet(title: ..., actions: [...]))。
class GlassActionSheet extends StatelessWidget {
  final String title;
  final List<GlassAction> actions;
  final Color accentColor;
  const GlassActionSheet({
    super.key,
    required this.title,
    required this.actions,
    this.accentColor = kPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: GlassCard(
          radius: 22,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: kInk,
                ),
              ),
              const SizedBox(height: 12),
              for (final a in actions) ...[
                if (a.section != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                    child: Text(
                      a.section!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: kTextMuted,
                      ),
                    ),
                  ),
                _row(a),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(GlassAction a) {
    return GlassActionRow(
      a.icon,
      a.label,
      onTap: a.onTap,
      color: a.color,
      trailing: a.trailing,
      accentColor: accentColor,
    );
  }
}
