// widgets/glass_info_row.dart —— 详情弹窗通用信息行（标签 + 值）。
// 用于 GlassDialog 内的键值对展示（课程/考试/成绩/账单详情等）。
// 细线分割式：每行顶部一条 kGlassGridLine 细线，多条信息逐行分隔，
// 比无边框堆叠更易逐条查看；字号字重全局统一。

import 'package:flutter/material.dart';
import '../theme.dart';

class GlassInfoRow extends StatelessWidget {
  final String label;
  final String value;

  /// 值的最大行数（交易号等长文本可传更多行）。
  final int maxLines;
  const GlassInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.maxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: kGlassGridLine)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: kTextMuted),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: kTextMain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
