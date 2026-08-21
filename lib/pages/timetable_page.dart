import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/timetable_row.dart';
import '../providers/data_state.dart';
import '../theme.dart';
import '../widgets/course_card.dart';
import '../widgets/empty_view.dart';

class TimetablePage extends ConsumerWidget {
  const TimetablePage({super.key});

  static const sections = ['1-2', '3-4', '5-6', '7-8', '9-10'];
  static const weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dataStateProvider);
    final week = state.timetableWeek;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: kPrimary),
                onPressed: week.isEmpty ? null : () => _shift(ref, -1),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      _weekLabel(state),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: kTextMain,
                      ),
                    ),
                    if (week.isNotEmpty)
                      Text(
                        _dateRange(week),
                        style: const TextStyle(fontSize: 9, color: kTextMuted),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: kPrimary),
                onPressed: week.isEmpty ? null : () => _shift(ref, 1),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              const SizedBox(width: 22),
              for (final d in weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: TextStyle(
                        fontSize: 10,
                        color: d == '六' || d == '日'
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: state.timetable.isEmpty
              ? const EmptyView(text: '暂无课表，联网后自动更新')
              : _grid(state.timetable),
        ),
      ],
    );
  }

  String _weekLabel(DataState state) {
    final week = state.timetableWeek;
    if (week.isEmpty) return '选择周次';
    final w = _weekOf(state, week);
    return w == null ? '本周课表' : '第 $w 周';
  }

  int? _weekOf(DataState state, String monday) {
    if (state.currentWeek == null || state.currentWeekBase.isEmpty) return null;
    final base = DateTime.parse(state.currentWeekBase);
    final target = DateTime.parse(monday);
    return state.currentWeek! + ((target.difference(base).inDays) / 7).round();
  }

  String _dateRange(String monday) {
    final m = DateTime.parse(monday);
    final s = m.add(const Duration(days: 6));
    String f(DateTime d) =>
        '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
    return '${monday.substring(0, 4)} · ${f(m)} - ${f(s)}';
  }

  void _shift(WidgetRef ref, int delta) {
    final cur = ref.read(dataStateProvider).timetableWeek;
    if (cur.isEmpty) return;
    final d = DateTime.parse(cur).add(Duration(days: 7 * delta));
    ref.read(dataStateProvider.notifier).loadTimetable(mondayOf(d));
  }

  Widget _grid(List<TimetableRow> rows) {
    final bySection = {for (final r in rows) r.section: r};
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          for (final s in sections)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Center(
                        child: Text(
                          s,
                          style: const TextStyle(fontSize: 8, color: Color(0xFF9AA3AD)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    for (var i = 0; i < 7; i++) Expanded(child: _cell(bySection[s], i)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(TimetableRow? row, int col) {
    final cell = row != null && col < row.cells.length ? row.cells[col] : null;
    if (cell == null || cell.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(left: 2), child: CourseCard(cell: cell));
  }
}
