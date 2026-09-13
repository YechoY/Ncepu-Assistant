import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/timetable_row.dart';
import '../providers/data_state.dart';
import '../theme.dart';
import '../widgets/course_card.dart';
import '../widgets/empty_view.dart';
import '../widgets/glass_card.dart';

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
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
          child: GlassCard(
            radius: 16,
            opacity: 0.16,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
                          color: kPrimary,
                        ),
                      ),
                      if (week.isNotEmpty)
                        Text(
                          _dateRange(week),
                          style: const TextStyle(
                            fontSize: 9,
                            color: kTextMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.calendar_month, color: kPrimary),
                  onPressed: () => _pickDate(ref),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: kPrimary),
                  onPressed: week.isEmpty ? null : () => _shift(ref, 1),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
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
    if (w == null) return '本周课表';
    final total = state.totalWeeks;
    return total != null ? '第 $w 周课表（共 $total 周）' : '第 $w 周课表';
  }

  int? _weekOf(DataState state, String monday) {
    if (state.currentWeek == null || state.currentWeekBase.isEmpty) {
      return null;
    }
    final base = DateTime.parse(state.currentWeekBase);
    final target = DateTime.parse(monday);
    final w =
        state.currentWeek! + ((target.difference(base).inDays) / 7).round();

    return w;
  }

  String _dateRange(String monday) {
    final m = DateTime.parse(monday);
    final s = m.add(const Duration(days: 6));
    String f(DateTime d) => '${d.month}月${d.day}日';
    return '${m.year}年 ${f(m)}-${f(s)}';
  }

  void _shift(WidgetRef ref, int delta) {
    final cur = ref.read(dataStateProvider).timetableWeek;
    if (cur.isEmpty) return;
    final d = DateTime.parse(cur).add(Duration(days: 7 * delta));
    ref.read(dataStateProvider.notifier).loadTimetable(mondayOf(d));
  }

  Future<void> _pickDate(WidgetRef ref) async {
    // 桌面版支持点日期选课表对应周。这里用系统日期选择器，选中后取所在周的周一查询。
    final cur = ref.read(dataStateProvider).timetableWeek;
    final initial = cur.isNotEmpty ? DateTime.parse(cur) : DateTime.now();
    final picked = await showDatePicker(
      context: ref.context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '选择日期查看当周课表',
    );
    if (picked == null) return;
    final monday = mondayOf(picked);
    ref.read(dataStateProvider.notifier).loadTimetable(monday);
  }

  Widget _grid(List<TimetableRow> rows) {
    return _TimetableGrid(rows: rows);
  }
}

/// 课表网格：左侧节次列固定 + 右侧星期/课程横向滚动，打开时自动聚焦今天列，今天列高亮。
class _TimetableGrid extends StatefulWidget {
  final List<TimetableRow> rows;
  const _TimetableGrid({required this.rows});

  @override
  State<_TimetableGrid> createState() => _TimetableGridState();
}

class _TimetableGridState extends State<_TimetableGrid> {
  final ScrollController _hScroll = ScrollController();
  static const _colW = 96.0; // 每列宽度（星期列）
  static const _secW = 56.0; // 左侧节次列宽度
  static const _cellH = 76.0; // 每个课程格高度
  static const _rowGap = 10.0; // 行间距（节次之间）
  static const _headH = 26.0; // 星期标头高度（左右两侧共用，保证节次水平对齐）
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  bool _didAutoScroll = false;

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  void _autoscrollIfNeeded() {
    if (_didAutoScroll || !_hScroll.hasClients) return;
    final todayCol = DateTime.now().weekday - 1;
    // 每列实际间距 = 列宽 + 左右各 3 的 margin。让今天列大致居中。
    const pitch = _colW + 6;
    final viewport = MediaQuery.of(context).size.width;
    final target = todayCol * pitch + pitch / 2 - viewport / 2;
    _hScroll.jumpTo(target.clamp(0.0, _hScroll.position.maxScrollExtent));
    _didAutoScroll = true;
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final bySection = {for (final r in rows) r.section: r};
    final secList = <String>[];
    for (final r in rows) {
      if (secList.contains(r.section)) continue;
      final s = r.section;
      if (s == '周/节次' ||
          s.contains('星期') ||
          s.contains('时间') ||
          s.contains('节次'))
        continue;
      secList.add(s);
    }
    if (secList.isEmpty) return const EmptyView(text: '暂无课表，联网后自动更新');
    final todayCol = DateTime.now().weekday - 1;
    // 首次渲染课表网格时自动聚焦今天列（_didAutoScroll 保证只聚焦一次，切换周次不会重复聚焦）
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoscrollIfNeeded());

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      padding: const EdgeInsets.only(left: 8, right: 4, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：节次列固定
          Column(
            children: [
              // 与右侧星期标头等高的占位，保证下方节次与课程格水平对齐
              const SizedBox(height: _headH + _rowGap),
              for (final s in secList)
                Padding(
                  padding: const EdgeInsets.only(bottom: _rowGap),
                  child: Container(
                    width: _secW,
                    height: _cellH,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: todayCol >= 0 && todayCol <= 6
                          ? kPrimary.withValues(alpha: 0.10)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        s,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF6B7280),
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // 右侧：星期标头 + 网格，横向滚动
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: _hScroll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: _rowGap),
                    child: SizedBox(
                      height: _headH,
                      child: Row(
                        children: [
                          for (var i = 0; i < 7; i++)
                            Container(
                              width: _colW,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: i == todayCol
                                    ? kPrimary.withValues(alpha: 0.16)
                                    : Colors.white.withValues(alpha: 0.35),
                              ),
                              child: Center(
                                child: Text(
                                  '周${_weekdays[i]}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: i == todayCol
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: (i == 5 || i == 6)
                                        ? const Color(0xFFDC2626)
                                        : const Color(0xFF374151),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  for (final s in secList)
                    Padding(
                      padding: const EdgeInsets.only(bottom: _rowGap),
                      child: SizedBox(
                        height: _cellH,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < 7; i++)
                              Container(
                                width: _colW,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: i == todayCol
                                      ? kPrimary.withValues(alpha: 0.06)
                                      : null,
                                ),
                                child: _cell(bySection[s], i),
                              ),
                          ],
                        ),
                      ),
                    ),
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
    return CourseCard(cell: cell);
  }
}
