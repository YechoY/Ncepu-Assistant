import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/data_state.dart';
import '../theme.dart';
import '../widgets/empty_view.dart';
import '../widgets/exam_card.dart';
import '../widgets/glass_dropdown.dart';
import '../widgets/reveal.dart';

class ExamsPage extends ConsumerWidget {
  const ExamsPage({super.key});

  // 空串 = 「本学期（默认）」，即请求里 xnxqid 交给服务器取当前学期。
  static const String _current = '';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dataStateProvider);
    final notifier = ref.read(dataStateProvider.notifier);
    final exams = state.exams;

    // 下拉选项：本学期（默认）在最前，其后是成绩里出现过的各学期（降序）。
    final terms = notifier.availableExamTerms();
    final items = <String>[_current, ...terms];
    final displayNames = items.map(_termLabel).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 顶部学期查询条件（整行铺满）──────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Row(
            children: [
              const Text(
                '学期',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: kTextMain,
                ),
              ),
              const SizedBox(width: 10),
              // 下拉框占满整行剩余宽度，学期文案再长也能完整显示。
              Expanded(
                child: GlassDropdown(
                  value: state.examTerm,
                  items: items,
                  displayNames: displayNames,
                  expand: true,
                  onChanged: (t) {
                    if (t == state.examTerm) return; // 没变则不重复查询
                    notifier.refreshExams(term: t);
                  },
                ),
              ),
              if (state.loading) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ),
        // ── 考试列表 / 空态 ───────────────────────────────
        Expanded(child: _buildList(exams)),
      ],
    );
  }

  Widget _buildList(List exams) {
    if (exams.isEmpty) return const EmptyView(text: '暂无考试信息');
    final now = DateTime.now();
    // 按考试时间排序后反转 → 时间较晚的在前（降序）。
    final sorted = [...exams]
      ..sort((a, b) {
        final ta = _parseTime(a.time);
        final tb = _parseTime(b.time);
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return ta.compareTo(tb);
      });
    final ordered = sorted.reversed.toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      itemCount: ordered.length,
      itemBuilder: (_, i) {
        final e = ordered[i];
        final done = _parseTime(e.time)?.isBefore(now) ?? false;
        return Reveal(
          duration: const Duration(milliseconds: 320),
          offset: const Offset(0, 14),
          minScale: 0.98,
          child: ExamCard(exam: e, done: done),
        );
      },
    );
  }

  // 把 xnxqid（如 2025-2026-2）显示成易读文案；空串显示「本学期」。
  String _termLabel(String t) {
    if (t.isEmpty) return '本学期';
    final m = RegExp(r'^(\d{4})-(\d{4})-(\d)$').firstMatch(t);
    if (m == null) return t;
    return '${m.group(1)}-${m.group(2)}学年 第${m.group(3)}学期';
  }

  DateTime? _parseTime(String s) {
    final m = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})')
        .firstMatch(s);
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
    );
  }
}
