import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/data_state.dart';
import '../widgets/empty_view.dart';
import '../widgets/exam_card.dart';

class ExamsPage extends ConsumerWidget {
  const ExamsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exams = ref.watch(dataStateProvider).exams;
    if (exams.isEmpty) return const EmptyView(text: '暂无考试安排');
    final now = DateTime.now();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      itemCount: exams.length,
      itemBuilder: (_, i) {
        final e = exams[i];
        final done = _parseTime(e.time)?.isBefore(now) ?? false;
        return ExamCard(exam: e, done: done);
      },
    );
  }

  DateTime? _parseTime(String s) {
    final m = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})').firstMatch(s);
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
