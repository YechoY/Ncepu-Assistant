import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course_cell.dart';
import '../models/exam.dart';
import '../models/grade.dart';
import '../models/timetable_row.dart';
import 'app_state.dart';

final dataStateProvider = NotifierProvider<DataNotifier, DataState>(
  DataNotifier.new,
);

class DataState {
  final List<TimetableRow> timetable;
  final String timetableWeek; // 周一日期 yyyy-MM-dd
  final List<Grade> grades;
  final List<Exam> exams;
  final int? currentWeek;
  final String currentWeekBase; // 获取 currentWeek 时对应的周一
  final int? totalWeeks; // 本学期总周数
  final bool loading;
  final String? notice;
  final bool online; // 本会话是否成功联网取到过数据（用于离线横幅显隐）
  final String examTerm; // 考试页当前选中的学期（xnxqid，如 2025-2026-2）；空=当前学期
  // 各页数据「最后更新时间」（毫秒时间戳，来自缓存写入时间）；null=没有该数据。
  final int? timetableUpdatedAt;
  final int? gradesUpdatedAt;
  final int? examsUpdatedAt;
  const DataState({
    this.timetable = const [],
    this.timetableWeek = '',
    this.grades = const [],
    this.exams = const [],
    this.currentWeek,
    this.currentWeekBase = '',
    this.totalWeeks,
    this.loading = false,
    this.notice,
    this.online = false,
    this.examTerm = '',
    this.timetableUpdatedAt,
    this.gradesUpdatedAt,
    this.examsUpdatedAt,
  });
  // 说明：notice 需要能被「清空回 null」，普通的 `x ?? this.x` 做不到（传 null 会保留旧值）。
  // 因此用一个哨兵对象 _unset 作为「未传参」的标记：只有显式传了 notice（哪怕是 null）才覆盖。
  DataState copyWith({
    List<TimetableRow>? timetable,
    String? timetableWeek,
    List<Grade>? grades,
    List<Exam>? exams,
    int? currentWeek,
    String? currentWeekBase,
    int? totalWeeks,
    bool? loading,
    Object? notice = _unset,
    bool? online,
    String? examTerm,
    int? timetableUpdatedAt,
    int? gradesUpdatedAt,
    int? examsUpdatedAt,
  }) => DataState(
    timetable: timetable ?? this.timetable,
    timetableWeek: timetableWeek ?? this.timetableWeek,
    grades: grades ?? this.grades,
    exams: exams ?? this.exams,
    currentWeek: currentWeek ?? this.currentWeek,
    currentWeekBase: currentWeekBase ?? this.currentWeekBase,
    totalWeeks: totalWeeks ?? this.totalWeeks,
    loading: loading ?? this.loading,
    notice: identical(notice, _unset) ? this.notice : notice as String?,
    online: online ?? this.online,
    examTerm: examTerm ?? this.examTerm,
    timetableUpdatedAt: timetableUpdatedAt ?? this.timetableUpdatedAt,
    gradesUpdatedAt: gradesUpdatedAt ?? this.gradesUpdatedAt,
    examsUpdatedAt: examsUpdatedAt ?? this.examsUpdatedAt,
  );
}

// copyWith 的「未传参」哨兵：区分「没传 notice」和「显式传了 notice: null」。
const Object _unset = Object();

/// 把「最后更新时间」的毫秒时间戳格式化成友好文案，供各页头部显示。
/// null（还没有该数据）→ 返回“未更新”。
/// - 今天：只显示时:分，如「今天 17:21」
/// - 今年内的其它天：显示 月-日 时:分，如「08-31 17:21」
/// - 不同年（跨年后才打开）：补上年份，如「2025-08-31 17:21」，避免看不出是哪一年
String formatUpdatedAt(int? ms) {
  if (ms == null) return '未更新';
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final hm = '${two(t.hour)}:${two(t.minute)}';
  if (t.year == now.year && t.month == now.month && t.day == now.day) {
    return '今天 $hm';
  }
  if (t.year != now.year) {
    return '${t.year}-${two(t.month)}-${two(t.day)} $hm';
  }
  return '${two(t.month)}-${two(t.day)} $hm';
}

String mondayOf(DateTime d) {
  final m = d.subtract(Duration(days: d.weekday - 1));
  return '${m.year.toString().padLeft(4, '0')}-${m.month.toString().padLeft(2, '0')}-${m.day.toString().padLeft(2, '0')}';
}

List<Map<String, dynamic>> ttToJson(List<TimetableRow> rows) => rows
    .map(
      (r) => {
        'section': r.section,
        'cells': r.cells.map((c) => c.toJson()).toList(),
      },
    )
    .toList();

List<TimetableRow> ttFromJson(dynamic v) => (v as List)
    .map(
      (r) => TimetableRow(
        section: r['section'] as String,
        cells: (r['cells'] as List)
            .map((c) => CourseCell.fromJson(c as Map<String, dynamic>))
            .toList(),
      ),
    )
    .toList();

class DataNotifier extends Notifier<DataState> {
  @override
  DataState build() => const DataState();

  Future<void> dailyRefreshIfNeeded({bool force = false}) async {
    final cache = ref.read(cacheServiceProvider);
    final api = ref.read(apiClientProvider);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final last = await cache.loadJson('last_daily_update');
    // 无论今天刷没刷新，都先恢复缓存的 currentWeek（否则"第X周课表"永远显示不出来）
    final cachedWeek = await cache.loadJson('current_week');
    final cachedBase = await cache.loadJson('current_week_base');
    if (cachedWeek != null && cachedBase != null) {
      state = state.copyWith(
        currentWeek: cachedWeek as int,
        currentWeekBase: cachedBase as String,
      );
    }
    if (!force && last == today) {
      // 今日已刷新过但缓存里没有 current_week：补一次获取，保证周次能显示
      if (cachedWeek == null || cachedBase == null) {
        final info = await api.fetchSemesterInfo();
        if (info != null) {
          final base = mondayOf(DateTime.now());
          await cache.saveJson('current_week', info.current);
          await cache.saveJson('current_week_base', base);
          if (info.total != null)
            await cache.saveJson('total_weeks', info.total as int);
          state = state.copyWith(
            currentWeek: info.current,
            currentWeekBase: base,
            totalWeeks: info.total,
          );
        }
      }
      return;
    }
    state = state.copyWith(loading: true);
    final week = mondayOf(DateTime.now());
    try {
      final tt = await api.fetchTimetable(week);
      await cache.saveJson('timetable_$week', ttToJson(tt));
      // 联网成功：标记 online=true，用于摘掉离线横幅
      state = state.copyWith(
        timetable: tt,
        timetableWeek: week,
        online: true,
        timetableUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
    final info = await api.fetchSemesterInfo();
    if (info != null) {
      await cache.saveJson('current_week', info.current);
      await cache.saveJson('current_week_base', week);
      if (info.total != null)
        await cache.saveJson('total_weeks', info.total as int);
      state = state.copyWith(
        currentWeek: info.current,
        currentWeekBase: week,
        totalWeeks: info.total,
      );
    }
    try {
      final g = await api.fetchGrades();
      await cache.saveJson('grades', g.map((e) => e.toJson()).toList());
      state = state.copyWith(
        grades: g,
        online: true,
        gradesUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
    try {
      final e = await api.fetchExams();
      await cache.saveJson('exams', e.map((x) => x.toJson()).toList());
      state = state.copyWith(
        exams: e,
        online: true,
        examsUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
    await cache.saveJson('last_daily_update', today);
    state = state.copyWith(loading: false);
  }

  /// 加载指定周(周一日期)的课表。
  /// [force] 为 true 时（点刷新按钮）强制联网重查，不走“有缓存就直接返回”的捷径，
  /// 这样刷新后更新时间才会跟着变；联网失败仍回退到缓存。
  Future<void> loadTimetable(String monday, {bool force = false}) async {
    final cache = ref.read(cacheServiceProvider);
    final api = ref.read(apiClientProvider);
    final key = 'timetable_$monday';
    final cached = await cache.loadJson(key, ttlDays: 30);
    // 非强制刷新时：若有非空缓存直接用，避免每次切周都联网。
    if (!force && cached != null) {
      final cachedRows = ttFromJson(cached);
      if (cachedRows.isNotEmpty) {
        state = state.copyWith(
          timetable: cachedRows,
          timetableWeek: monday,
          timetableUpdatedAt: await cache.updatedAt(key),
        );
        return;
      }
    }
    try {
      final tt = await api.fetchTimetable(monday);
      await cache.saveJson(key, ttToJson(tt));
      state = state.copyWith(
        timetable: tt,
        timetableWeek: monday,
        notice: null,
        online: true,
        timetableUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // 联网失败：若之前有非空缓存则兜底显示缓存，否则提示
      if (cached != null) {
        final cachedRows = ttFromJson(cached);
        if (cachedRows.isNotEmpty) {
          state = state.copyWith(
            timetable: cachedRows,
            timetableWeek: monday,
            timetableUpdatedAt: await cache.updatedAt(key),
          );
          return;
        }
      }
      state = state.copyWith(
        timetable: const [],
        timetableWeek: monday,
        notice: '该周暂无缓存，联网后可查看',
      );
    }
  }

  Future<void> refreshGrades() async {
    final cache = ref.read(cacheServiceProvider);
    final api = ref.read(apiClientProvider);
    state = state.copyWith(loading: true);
    try {
      final g = await api.fetchGrades();
      await cache.saveJson('grades', g.map((e) => e.toJson()).toList());
      state = state.copyWith(
        grades: g,
        loading: false,
        notice: null,
        online: true,
        gradesUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      state = state.copyWith(loading: false, notice: '获取失败，已显示缓存数据');
    }
  }

  // 考试缓存键：当前学期（默认）沿用 'exams'，指定学期则用 'exams_<term>'。
  // 这样可离线保留每个学期各自查过的考试，切回来无需重新联网。
  String _examCacheKey(String term) => term.isEmpty ? 'exams' : 'exams_$term';

  /// 刷新考试安排。
  /// [term] 指定学期（xnxqid，如 2025-2026-2）；不传/空串表示当前学期。
  Future<void> refreshExams({String? term}) async {
    final t = term ?? state.examTerm;
    final cache = ref.read(cacheServiceProvider);
    final api = ref.read(apiClientProvider);
    // 切换学期时先记录选中项，并尝试展示该学期的缓存，避免加载期间显示上一学期数据。
    final cached = await cache.loadJson(_examCacheKey(t));
    state = state.copyWith(
      loading: true,
      examTerm: t,
      exams: cached is List
          ? cached.map((e) => Exam.fromJson(e as Map<String, dynamic>)).toList()
          : <Exam>[],
      examsUpdatedAt: await cache.updatedAt(_examCacheKey(t)),
    );
    try {
      final e = await api.fetchExams(term: t.isEmpty ? null : t);
      await cache.saveJson(_examCacheKey(t), e.map((x) => x.toJson()).toList());
      state = state.copyWith(
        exams: e,
        loading: false,
        notice: null,
        online: true,
        examsUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      state = state.copyWith(loading: false, notice: '获取失败，已显示缓存数据');
    }
  }

  /// 供考试页下拉框使用：可选学期列表。
  /// 来源：成绩数据里出现过的学期（去重、降序，最近学期在前）；
  /// 若当前选中学期不在其中也补进去，保证下拉能显示当前项。
  List<String> availableExamTerms() {
    final set = <String>{};
    for (final g in state.grades) {
      final t = g.term.trim();
      if (t.isNotEmpty) set.add(t);
    }
    if (state.examTerm.isNotEmpty) set.add(state.examTerm);
    final list = set.toList()
      ..sort((a, b) => b.compareTo(a)); // 字符串降序，如 2026-2027-1 排在前
    return list;
  }

  /// 清空所有本地缓存并重置内存状态（用于「未记住密码」启动或退出登录）。
  Future<void> clearAll() async {
    await ref.read(cacheServiceProvider).clearAll();
    state = const DataState();
  }

  Future<void> loadFromCache() async {
    final cache = ref.read(cacheServiceProvider);
    final week = mondayOf(DateTime.now());
    final tt = await cache.loadJson('timetable_$week', ttlDays: 30);
    final g = await cache.loadJson('grades');
    final e = await cache.loadJson('exams');
    final curWeek = await cache.loadJson('current_week');
    final curBase = await cache.loadJson('current_week_base');
    // 各页「最后更新时间」= 对应缓存键的写入时间。
    final ttAt = await cache.updatedAt('timetable_$week');
    final gAt = await cache.updatedAt('grades');
    final eAt = await cache.updatedAt('exams');
    state = state.copyWith(
      timetable: tt == null ? const [] : ttFromJson(tt),
      timetableWeek: week,
      grades: g == null
          ? const []
          : (g as List)
                .map((x) => Grade.fromJson(x as Map<String, dynamic>))
                .toList(),
      exams: e == null
          ? const []
          : (e as List)
                .map((x) => Exam.fromJson(x as Map<String, dynamic>))
                .toList(),
      currentWeek: curWeek as int?,
      currentWeekBase: curBase as String? ?? '',
      timetableUpdatedAt: ttAt,
      gradesUpdatedAt: gAt,
      examsUpdatedAt: eAt,
    );
  }
}
