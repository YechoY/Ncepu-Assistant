import 'package:flutter/material.dart';

import '../study/models/grade.dart';
import 'package:glass_ui/theme.dart';
import 'package:glass_ui/widgets/glass_card.dart';
import 'package:glass_ui/widgets/glass_dialog.dart';
import 'package:glass_ui/widgets/glass_info_row.dart';

class GradeCard extends StatelessWidget {
  final Grade grade;

  /// 勾选模式：true 时卡片可点按勾选（仅必修课会传 true），点按不再弹详情。
  final bool selectable;

  /// 当前勾选状态（仅 selectable=true 时有意义）。
  final bool selected;
  final VoidCallback? onToggle;
  const GradeCard({
    super.key,
    required this.grade,
    this.selectable = false,
    this.selected = false,
    this.onToggle,
  });

  /// 等级色：优良中差四档功能色（柔和版），返回 (背景, 前景)。
  /// 数值分数与未知等级统一用主题容器色。
  static (Color, Color) _gradeTone(String badge) {
    final bg = badge.contains('优')
        ? const Color(0xFFE8F5EC)
        : badge.contains('良')
        ? const Color(0xFFE3F0F9)
        : badge.contains('中')
        ? const Color(0xFFFBEFDF)
        : badge.contains('不及格')
        ? const Color(0xFFFBE6E6)
        : kPrimaryContainer;
    final fg = badge.contains('优')
        ? const Color(0xFF3E7D55)
        : badge.contains('良')
        ? const Color(0xFF3B7399)
        : badge.contains('中')
        ? const Color(0xFFB07432)
        : badge.contains('不及格')
        ? const Color(0xFFB85450)
        : kInk;
    return (bg, fg);
  }

  @override
  Widget build(BuildContext context) {
    final badge = grade.grade;
    final (bg, fg) = _gradeTone(badge);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        // 勾选模式下点整张卡片切换选中；非勾选模式点击弹成绩详情弹窗。
        onTap: selectable ? onToggle : () => _showDetail(context),
        child: GlassCard(
          radius: 18,
          live: false,
          opacity: kFrostAlpha,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              if (selectable) ...[
                _CheckBox(checked: selected),
                const SizedBox(width: 10),
              ],
              // 等级色竖条
              Container(
                width: 4,
                height: 34,
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      grade.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: kTextMain,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${grade.term} · ${grade.attr} · ${grade.credit}学分',
                      style: const TextStyle(fontSize: 10.5, color: kTextMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bg,
                  shape: BoxShape.circle,
                  border: Border.all(color: fg.withValues(alpha: .35)),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 成绩详情弹窗：课程名做标题，成绩大徽章 + 全部字段。
  void _showDetail(BuildContext context) {
    final (bg, fg) = _gradeTone(grade.grade);
    final isNumeric = double.tryParse(grade.grade) != null;
    showDialog(
      context: context,
      builder: (_) => GlassDialog(
        title: grade.name,
        confirmText: '知道了',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 成绩大徽章：居中放大展示
            Center(
              child: Container(
                width: 68,
                height: 68,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bg,
                  shape: BoxShape.circle,
                  border: Border.all(color: fg.withValues(alpha: .35)),
                ),
                child: Text(
                  grade.grade.isEmpty ? '—' : grade.grade,
                  style: TextStyle(
                    fontSize: grade.grade.length > 3 ? 18 : 24,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                isNumeric ? '百分制成绩' : '等级制成绩',
                style: const TextStyle(fontSize: 11, color: kTextMuted),
              ),
            ),
            const SizedBox(height: 12),
            GlassInfoRow(label: '所属学期', value: grade.term),
            GlassInfoRow(label: '课程性质', value: grade.attr),
            GlassInfoRow(
              label: '学分',
              value: grade.credit.isEmpty ? '' : '${grade.credit} 学分',
            ),
          ],
        ),
      ),
    );
  }
}

/// 卡片勾选框：选中实底紫 + 白勾，未选中半透明白（与 GlassDropdown 的勾选框同款视觉）。
class _CheckBox extends StatelessWidget {
  final bool checked;
  const _CheckBox({required this.checked});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: kSpring,
      width: 19,
      height: 19,
      decoration: BoxDecoration(
        color: checked ? kPrimary : Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: checked ? kPrimary : Colors.white.withValues(alpha: 0.65),
        ),
      ),
      child: checked
          ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
          : null,
    );
  }
}
