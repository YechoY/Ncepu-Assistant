import 'package:flutter/material.dart';

import '../theme.dart';
import 'glass_card.dart';

/// 玻璃拟态下拉框：点击后从底部弹出玻璃拟态（毛玻璃模糊）选项面板。
/// 按钮为半透明磨砂芯片 + 高光描边；弹窗是浮起的 GlassCard，
/// 选项彼此留白（不再紧挨），选中项用浅紫承托 + 墨紫文字。
class GlassDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final List<String>? displayNames;

  /// 单选模式回调（多选模式不用，走 [onMultiChanged]）。
  final ValueChanged<String>? onChanged;
  final String? label;

  /// 是否撑满父容器宽度：true 时按钮占满整行、选中文本不再限宽（配合外层 Expanded 使用）。
  final bool expand;

  // —— 多选模式（如成绩页勾选学期快速选课）：选项带勾选框，点按不关面板、实时回调 ——
  final bool multi;

  /// 多选模式下已勾选的项。
  final Set<String> multiValues;

  /// 多选模式下「部分选中」的项（勾选框显示 "-"，如某学期只勾了部分课程）。
  final Set<String> multiPartial;

  /// 多选模式回调：每次勾选变化都会触发（面板保持打开，底层页面实时刷新）。
  final ValueChanged<Set<String>>? onMultiChanged;

  const GlassDropdown({
    super.key,
    required this.value,
    required this.items,
    this.onChanged,
    this.displayNames,
    this.label,
    this.expand = false,
    this.multi = false,
    this.multiValues = const {},
    this.multiPartial = const {},
    this.onMultiChanged,
  });

  String _display(String v) {
    final names = displayNames;
    if (names != null && names.length == items.length) {
      final i = items.indexOf(v);
      if (i >= 0) return names[i];
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    // 选中文本：撑满模式下用 Expanded 占据剩余空间；紧凑模式下限宽 110。
    final valueText = Text(
      _display(value),
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 12,
        color: kTextMain,
        fontWeight: FontWeight.w600,
      ),
    );
    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        width: expand ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x143D4670),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (label != null) ...[
              Text(
                label!,
                style: const TextStyle(
                  fontSize: 9,
                  color: kTextMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 5),
            ],
            if (expand)
              Expanded(child: valueText)
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: valueText,
              ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 17, color: kPrimary),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    // 多选模式：弹出带勾选框的面板，勾选不关闭，点「完成」才收起。
    if (multi) {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: const Color(0x4D2E3350),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: GlassCard(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: SafeArea(
              top: false,
              child: _MultiSheet(
                label: label ?? '多选',
                items: items,
                displayNames: displayNames,
                initial: Set.of(multiValues),
                partial: multiPartial,
                onChanged: onMultiChanged,
              ),
            ),
          ),
        ),
      );
      return;
    }
    final sel = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x4D2E3350),
      builder: (ctx) => Padding(
        // 面板四周浮起留白，与屏幕边缘分开，强化"玻璃片悬浮"感
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: GlassCard(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (label != null) ...[
                    Text(
                      label!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: kTextMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  // 选项之间留 8px 空隙（最后一项不留），不再彼此紧挨
                  for (var i = 0; i < items.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: i == items.length - 1 ? 0 : 8,
                      ),
                      child: _OptionTile(
                        label: _display(items[i]),
                        selected: items[i] == value,
                        onTap: () => Navigator.pop(ctx, items[i]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (sel != null) onChanged?.call(sel);
  }
}

/// 下拉面板中的单个选项：圆角大、可点区域铺满整行，选中态浅紫承托。
/// 多选模式（checkbox=true）：行首显示勾选框，选中态体现在勾选框上。
class _OptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool checkbox;

  /// 部分选中：勾选框显示 "-"（仅多选模式有意义）。
  final bool partial;
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.checkbox = false,
    this.partial = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: kSpring,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(
            color: selected && !checkbox
                ? kPrimaryContainer
                : Colors.white.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected && !checkbox
                  ? kPrimarySoft.withValues(alpha: 0.8)
                  : Colors.white.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              if (checkbox) ...[
                _CheckMark(checked: selected, partial: partial),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected && !checkbox
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: selected && !checkbox ? kInk : kTextMain,
                  ),
                ),
              ),
              if (!checkbox && selected)
                const Icon(Icons.check_rounded, size: 16, color: kPrimary),
            ],
          ),
        ),
      ),
    );
  }
}

/// 多选勾选框：选中实底紫 + 白勾；部分选中浅紫底 + 紫色 "-"；未选中半透明白。
class _CheckMark extends StatelessWidget {
  final bool checked;
  final bool partial;
  const _CheckMark({required this.checked, this.partial = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: kSpring,
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: checked
            ? kPrimary
            : partial
            ? kPrimaryContainer
            : Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: checked
              ? kPrimary
              : partial
              ? kPrimarySoft
              : Colors.white.withValues(alpha: 0.65),
        ),
      ),
      child: checked
          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : partial
          ? const Icon(Icons.remove_rounded, size: 14, color: kPrimary)
          : null,
    );
  }
}

/// 多选面板：本地维护勾选副本，每次变化实时回调（底层页面同步刷新），点「完成」收起。
class _MultiSheet extends StatefulWidget {
  final String label;
  final List<String> items;
  final List<String>? displayNames;
  final Set<String> initial;
  final Set<String> partial;
  final ValueChanged<Set<String>>? onChanged;

  const _MultiSheet({
    required this.label,
    required this.items,
    required this.initial,
    required this.partial,
    this.displayNames,
    this.onChanged,
  });

  @override
  State<_MultiSheet> createState() => _MultiSheetState();
}

class _MultiSheetState extends State<_MultiSheet> {
  late Set<String> values = Set.of(widget.initial);

  void _toggle(String v) {
    setState(() => values.contains(v) ? values.remove(v) : values.add(v));
    // 传副本出去，避免面板内部集合与页面状态共享可变引用。
    widget.onChanged?.call(Set.of(values));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: kTextMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: kPrimary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '完成',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < widget.items.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == widget.items.length - 1 ? 0 : 8,
              ),
              child: _OptionTile(
                label: _displayName(widget.items[i]),
                selected: values.contains(widget.items[i]),
                checkbox: true,
                partial: widget.partial.contains(widget.items[i]),
                onTap: () => _toggle(widget.items[i]),
              ),
            ),
        ],
      ),
    );
  }

  String _displayName(String v) {
    final names = widget.displayNames;
    if (names != null && names.length == widget.items.length) {
      final i = widget.items.indexOf(v);
      if (i >= 0) return names[i];
    }
    return v;
  }
}
