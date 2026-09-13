import 'package:flutter/material.dart';

import 'glass_card.dart';

/// 玻璃拟态下拉框：点击后从底部弹出玻璃拟态（毛玻璃模糊）选项面板。
/// 按钮半透明磨砂 + 细白描边 + 柔和发光；弹窗用 GlassCard（BackdropFilter 真模糊 + 白描边 + 大圆角）。
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
        color: Color(0xFF1F2937),
        fontWeight: FontWeight.w600,
      ),
    );
    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        width: expand ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
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
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
            ],
            if (expand)
              Expanded(child: valueText)
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: valueText,
              ),
            const SizedBox(width: 4),
            const Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: Color(0xFF6B7280),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final sel = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.2),
      builder: (ctx) => GlassCard(
        radius: 20,
        opacity: 0.12,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
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
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                for (final it in items)
                  InkWell(
                    onTap: () => Navigator.pop(ctx, it),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 11,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        color: it == value
                            ? const Color(0xFF3B82F6)
                            : Colors.white.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _display(it),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: it == value
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: it == value
                              ? Colors.white
                              : const Color(0xFF1F2937),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (sel != null) onChanged(sel);
  }
}
