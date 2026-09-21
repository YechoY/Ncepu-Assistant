import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/timetable_row.dart';
import '../providers/data_state.dart';
import '../theme.dart';
import '../widgets/course_card.dart';
import '../widgets/empty_view.dart';
import '../widgets/glass_card.dart';
import '../widgets/glass_snackbar.dart';

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
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: kPrimary),
                  onPressed: week.isEmpty
                      ? null
                      : () async {
                          await ref
                              .read(dataStateProvider.notifier)
                              .loadTimetable(
                                mondayOf(
                                  DateTime.parse(week)
                                      .add(const Duration(days: -7)),
                                ),
                              );
                          if (!context.mounted) return;
                          final st = ref.read(dataStateProvider);
                          if (st.notice != null) {
                            showGlassSnackBar(context, st.notice!);
                          } else {
                            showGlassSnackBar(
                              context,
                              '已切换到${_weekLabel(st)}\n${_dateRange(st.timetableWeek)}',
                            );
                          }
                        },
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        _weekLabel(state),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: kPrimary,
                        ),
                      ),
                      if (week.isNotEmpty)
                        Text(
                          _dateRange(week),
                          style: const TextStyle(
                            fontSize: 11,
                            color: kTextMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.calendar_month, color: kPrimary),
                  onPressed: () async {
                    final cur = ref.read(dataStateProvider).timetableWeek;
                    final initial = cur.isNotEmpty
                        ? DateTime.parse(cur)
                        : DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: initial,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      helpText: '选择日期查看当周课表',
                    );
                    if (picked == null || !context.mounted) return;
                    final monday = mondayOf(picked);
                    await ref
                        .read(dataStateProvider.notifier)
                        .loadTimetable(monday);
                    if (!context.mounted) return;
                    final st = ref.read(dataStateProvider);
                    if (st.notice != null) {
                      showGlassSnackBar(context, st.notice!);
                    } else {
                      showGlassSnackBar(
                        context,
                        '已切换到${_weekLabel(st)}\n${_dateRange(st.timetableWeek)}',
                      );
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: kPrimary),
                  onPressed: week.isEmpty
                      ? null
                      : () async {
                          await ref
                              .read(dataStateProvider.notifier)
                              .loadTimetable(
                                mondayOf(
                                  DateTime.parse(week)
                                      .add(const Duration(days: 7)),
                                ),
                              );
                          if (!context.mounted) return;
                          final st = ref.read(dataStateProvider);
                          if (st.notice != null) {
                            showGlassSnackBar(context, st.notice!);
                          } else {
                            showGlassSnackBar(
                              context,
                              '已切换到${_weekLabel(st)}\n${_dateRange(st.timetableWeek)}',
                            );
                          }
                        },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: state.timetable.isEmpty
              ? const EmptyView(text: '暂无课表，联网后自动更新')
              : _grid(state.timetable, state.timetableWeek),
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

  Widget _grid(List<TimetableRow> rows, String monday) {
    return _TimetableGrid(rows: rows, monday: monday);
  }
}

/// 课表网格：左侧节次列固定 + 右侧星期/课程横向滚动，打开时自动聚焦今天列，今天列高亮。
class _TimetableGrid extends StatefulWidget {
  final List<TimetableRow> rows;
  final String monday; // 当前周的周一日期（YYYY-MM-DD），用于算每天日期
  const _TimetableGrid({required this.rows, required this.monday});

  @override
  State<_TimetableGrid> createState() => _TimetableGridState();
}

class _TimetableGridState extends State<_TimetableGrid> {
  final ScrollController _hScroll = ScrollController();
  static const _colW = 96.0; // 每列宽度（星期列）
  static const _secW = 62.0; // 左侧节次列宽度
  static const _cellH = 76.0; // 每个课程格高度
  static const _rowGap = 10.0; // 行间距（节次之间）
  static const _headH = 44.0; // 星期标头高度（左右两侧共用，保证节次水平对齐）
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  // 一行网格的总宽度：7 列 ×（列宽 + 左右 margin 3×2），用于换时段分隔线
  static const double _gridW = 7 * (_colW + 6);

  /// 五大节对应的时间段（华电作息）。
  /// key = TimetableRow.section 中的节次名（支持「第一大节」/「1-2」两种格式）。
  static const _sectionTimes = <String, String>{
    '第一大节': '08:00–09:40',
    '第二大节': '10:00–11:40',
    '第三大节': '14:30–16:10',
    '第四大节': '16:30–18:10',
    '第五大节': '19:30–21:10',
    '1-2': '08:00–09:40',
    '3-4': '10:00–11:40',
    '5-6': '14:30–16:10',
    '7-8': '16:30–18:10',
    '9-10': '19:30–21:10',
  };

  bool _didAutoScroll = false;

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  void _autoscrollIfNeeded() {
    if (_didAutoScroll || !_hScroll.hasClients) return;
    final todayCol = DateTime.now().weekday - 1;
    // 每列实际间距 = 列宽 + 左右各 3 的 margin。让今天列精确居中。
    const pitch = _colW + 6;
    // 用滚动视图的真实可视宽度（已扣除页面左右 padding），而非整屏宽度
    final viewport = _hScroll.position.viewportDimension;
    final target = todayCol * pitch + pitch / 2 - viewport / 2;
    _hScroll.jumpTo(target.clamp(0.0, _hScroll.position.maxScrollExtent));
    _didAutoScroll = true;
  }

  /// 根据 section 名查时间段，没匹配返回 null。
  String? _timeFor(String section) {
    if (_sectionTimes.containsKey(section)) return _sectionTimes[section];
    // 兜底：尝试用正则提取「第X大节」
    final m = RegExp(r'第([一二三四五])大节').firstMatch(section);
    if (m != null) {
      const map = {
        '一': '第一大节',
        '二': '第二大节',
        '三': '第三大节',
        '四': '第四大节',
        '五': '第五大节',
      };
      return _sectionTimes[map[m.group(1)]];
    }
    return null;
  }

  /// 计算第 col 天的日期（col=0 = 周一）。
  /// 没有周一日期时返回空串。
  String _dateFor(int col) {
    if (widget.monday.isEmpty) return '';
    final m = DateTime.parse(widget.monday).add(Duration(days: col));
    return '${m.month}/${m.day}';
  }

  /// 是否为「换时段」边界：该节次之前要画分隔线。
  /// = 午休后（第三大节 14:30–16:10 之前）和 晚课后（第五大节 19:30–21:10 之前）。
  /// 判断的是"当前节次"的时间——如果当前是第三大节，说明它前面（第二大节之后）
  /// 是午休，需要画线分隔。
  bool _isPeriodBreak(String section) {
    final t = _timeFor(section);
    return t == '14:30–16:10' || t == '19:30–21:10';
  }

  /// 行间空隙：普通间隙只有间距；换时段间隙更高，中间一条细线贯穿整行。
  /// width 必须显式传——无宽度的 1px 容器在（横向滚动的）无界约束下宽度会变 0。
  Widget _gap(bool isBreak, double width) => SizedBox(
    height: isBreak ? 18.0 : _rowGap,
    child: isBreak
        ? Center(
            child: Container(width: width, height: 1, color: kGlassGridLine),
          )
        : null,
  );

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
    // 收集每门课出现在星期几，做「同天不同色」的颜色冲突消解。
    final courseDays = <String, Set<int>>{};
    for (final s in secList) {
      final row = bySection[s];
      if (row == null) continue;
      for (var col = 0; col < 7 && col < row.cells.length; col++) {
        final cell = row.cells[col];
        if (!cell.isEmpty) {
          (courseDays[cell.name] ??= <int>{}).add(col + 1);
        }
      }
    }
    final colorMap = assignCourseIndices(courseDays);
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
              // 与右侧星期标头等高的空位（保持留白），保证下方节次与课程格水平对齐
              const SizedBox(height: _headH + _rowGap),
              for (var i = 0; i < secList.length; i++) ...[
                // 与右侧网格在同位置插入同高的换时段分隔线，保证左右对齐
                if (i > 0) _gap(_isPeriodBreak(secList[i]), _secW),
                Container(
                  width: _secW,
                  height: _cellH,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: todayCol >= 0 && todayCol <= 6
                        ? kPrimary.withValues(alpha: 0.10)
                        : null,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          secList[i],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: kTextMain,
                            height: 1.1,
                          ),
                        ),
                        if (_timeFor(secList[i]) != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            _timeFor(secList[i])!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 9,
                              color: kTextMuted,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
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
                                    ? kPrimary.withValues(alpha: 0.22)
                                    : Colors.white.withValues(alpha: 0.35),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '周${_weekdays[i]}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: i == todayCol
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        color: (i == 5 || i == 6)
                                            ? kWeekend
                                            : kTextMain,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _dateFor(i),
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: i == todayCol
                                            ? kPrimary
                                            : kTextMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  for (var i = 0; i < secList.length; i++) ...[
                    // 与左侧节次列同位置的换时段分隔线（午休/晚课）
                    if (i > 0) _gap(_isPeriodBreak(secList[i]), _gridW),
                    SizedBox(
                      height: _cellH,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var j = 0; j < 7; j++)
                            Container(
                              width: _colW,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: j == todayCol
                                    ? kPrimary.withValues(alpha: 0.12)
                                    : null,
                              ),
                              child: _cell(bySection[secList[i]], j, colorMap),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(TimetableRow? row, int col, Map<String, int> colorMap) {
    final cell = row != null && col < row.cells.length ? row.cells[col] : null;
    if (cell == null || cell.isEmpty) return const SizedBox.shrink();
    return CourseCard(cell: cell, color: coursePalette[colorMap[cell.name]!]);
  }
}
