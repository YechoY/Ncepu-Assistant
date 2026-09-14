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
  final ValueChanged<String> onChanged;
  final String? label;

  /// 是否撑满父容器宽度：true 时按钮占满整行、选中文本不再限宽（配合外层 Expanded 使用）。
  final bool expand;

  const GlassDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.displayNames,
    this.label,
    this.expand = false,
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
    if (sel != null) onChanged(sel);
  }
}

/// 下拉面板中的单个选项：圆角大、可点区域铺满整行，选中态浅紫承托。
class _OptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
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
            color: selected
                ? kPrimaryContainer
                : Colors.white.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? kPrimarySoft.withValues(alpha: 0.8)
                  : Colors.white.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? kInk : kTextMain,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check_rounded, size: 16, color: kPrimary),
            ],
          ),
        ),
      ),
    );
  }
}
