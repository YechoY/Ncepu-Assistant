import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course_cell.dart';
import '../models/exam.dart';
import '../models/grade.dart';
import '../models/timetable_row.dart';
import '../services/cache_service.dart';
import 'app_state.dart';
import 'auth_state.dart';

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
  /// 成绩/考试缓存有效期：7 天内启动 App 直接用缓存、不联网；超过 7 天才自动刷新，
  /// 其余情况靠各页刷新按钮手动更新。
  static const int gradesCacheDays = 7;
  static const int examsCacheDays = 7;

  @override
  DataState build() => const DataState();

  /// 确保存在可用的教务系统登录会话。
  /// 离线启动直接进主界面的场景下，启动时的后台登录没有执行成功，
  /// ApiClient 里没有任何会话 Cookie——此时直接联网请求数据，
  /// 教务系统返回的是登录页 HTML，会被解析成**空列表**（不抛异常！），
  /// 不仅看不到数据，还会把空数据写进缓存、毁掉离线兜底。
  /// 因此每次联网取数前先确认会话：未登录则用记住的账号静默登录一次。
  Future<bool> _ensureLogin() async {
    if (ref.read(authStateProvider).loggedIn) return true;
    return ref.read(authStateProvider.notifier).tryAutoLogin();
  }

  /// 启动后的按需刷新（后台静默，失败不打扰）：
  /// - 周课表/学期周次：保持「每天首次启动刷新一次」的粒度（last_daily_update）；
  /// - 成绩/考试：各自缓存超过 7 天（或从无缓存）才联网；
  /// - 每次启动顺带清理本周之前的历史周课表缓存。
  /// [force]（手动刷新）时忽略上述节流，三类数据全部重查。
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
    // 清理上周及更早的周课表缓存（只保留本周及以后）。
    await _cleanupOldTimetableCache(cache);

    final ttDue = force || last != today;
    final gradesDue =
        force || await _isCacheStale(cache, 'grades', gradesCacheDays);
    final examsDue =
        force || await _isCacheStale(cache, 'exams', examsCacheDays);
    if (!ttDue && !gradesDue && !examsDue) {
      // 今日课表已刷新、成绩考试缓存也新鲜：仅在缺周次信息时补一次获取。
      if (cachedWeek == null || cachedBase == null) {
        final info = await api.fetchSemesterInfo();
        if (info != null) {
          final base = mondayOf(DateTime.now());
          await cache.saveJson('current_week', info.current);
          await cache.saveJson('current_week_base', base);
          if (info.total != null) {
            await cache.saveJson('total_weeks', info.total as int);
          }
          state = state.copyWith(
            currentWeek: info.current,
            currentWeekBase: base,
            totalWeeks: info.total,
          );
        }
      }
      return;
    }
    // 有数据要联网取：先确保会话可用（否则全变成空数据并污染缓存）。
    if (ttDue || gradesDue || examsDue) {
      final ok = await _ensureLogin();
      if (!ok) {
        // 手动刷新给个提示；后台静默刷新保持安静。
        if (force) {
          state = state.copyWith(notice: '暂无法连接校园网，正在使用缓存数据');
        }
        return;
      }
    }
    state = state.copyWith(loading: true);
    if (ttDue) {
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
        if (info.total != null) {
          await cache.saveJson('total_weeks', info.total as int);
        }
        state = state.copyWith(
          currentWeek: info.current,
          currentWeekBase: week,
          totalWeeks: info.total,
        );
      }
      await cache.saveJson('last_daily_update', today);
    }
    if (gradesDue) {
      try {
        final g = await api.fetchGrades();
        await cache.saveJson('grades', g.map((e) => e.toJson()).toList());
        state = state.copyWith(
          grades: g,
          online: true,
          gradesUpdatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      } catch (_) {}
    }
    if (examsDue) {
      try {
        final e = await api.fetchExams();
        await cache.saveJson('exams', e.map((x) => x.toJson()).toList());
        state = state.copyWith(
          exams: e,
          online: true,
          examsUpdatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      } catch (_) {}
    }
    state = state.copyWith(loading: false);
  }

  /// 缓存是否「需要刷新」：从无缓存（null）视为需要；否则比较是否已超过 [days] 天。
  Future<bool> _isCacheStale(CacheService cache, String key, int days) async {
    final at = await cache.updatedAt(key);
    if (at == null) return true;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at)) >
        Duration(days: days);
  }

  /// 删除本周周一之前的所有周课表缓存（上周及更早）。
  /// 键名后缀是定长 yyyy-MM-dd，字典序与时间序一致，可直接字符串比较。
  /// 顺带清理旧版本曾为历史学期考试写入的 `exams_<term>` 缓存（现已不再使用）。
  Future<void> _cleanupOldTimetableCache(CacheService cache) async {
    final currentMonday = mondayOf(DateTime.now());
    final keys = await cache.keysWithPrefix('timetable_');
    for (final k in keys) {
      final d = k.substring('timetable_'.length);
      if (d.length == 10 && d.compareTo(currentMonday) < 0) {
        await cache.delete(k);
      }
    }
    for (final k in await cache.keysWithPrefix('exams_')) {
      await cache.delete(k);
    }
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
      // 会话可能还没建立（离线启动场景），先确保登录；失败等同联网失败走缓存兜底。
      if (!await _ensureLogin()) throw Exception('未连接校园网');
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
      // 会话可能还没建立（离线启动场景），先确保登录；失败按获取失败处理。
      if (!await _ensureLogin()) throw Exception('未连接校园网');
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

  // 注：历史学期考试按需求不缓存，仅当前学期使用固定键 'exams'。

  /// 刷新考试安排。
  /// [term] 指定学期（xnxqid，如 2025-2026-2）；不传/空串表示当前学期。
  /// - 其他学期（手动切换过去）：实时联网查询、不缓存（按需求不自动查、不留缓存）；
  /// - 当前学期：缓存 7 天内直接展示，[force]=true（手动刷新）或超 7 天/无缓存才联网。
  Future<void> refreshExams({String? term, bool force = false}) async {
    final t = term ?? state.examTerm;
    final cache = ref.read(cacheServiceProvider);
    final api = ref.read(apiClientProvider);

    // 其他学期：仅手动切换时实时查询，不走缓存。
    if (t.isNotEmpty) {
      state = state.copyWith(
        loading: true,
        examTerm: t,
        exams: const [],
        examsUpdatedAt: null,
      );
      try {
        // 会话可能还没建立，先确保登录；失败按获取失败处理。
        if (!await _ensureLogin()) throw Exception('未连接校园网');
        final e = await api.fetchExams(term: t);
        state = state.copyWith(
          exams: e,
          loading: false,
          notice: null,
          online: true,
          examsUpdatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      } catch (_) {
        state = state.copyWith(loading: false, notice: '获取失败，请确认已连接校园网后重试');
      }
      return;
    }

    // 当前学期：缓存优先（7 天）。
    const key = 'exams';
    final cached = await cache.loadJson(key);
    final cachedAt = await cache.updatedAt(key);
    final cachedList = cached is List
        ? cached.map((e) => Exam.fromJson(e as Map<String, dynamic>)).toList()
        : <Exam>[];
    state = state.copyWith(
      loading: true,
      examTerm: t,
      exams: cachedList,
      examsUpdatedAt: cachedAt,
    );
    // 非手动刷新且有 7 天内的非空缓存：直接用，不联网。
    final fresh =
        cachedAt != null &&
        DateTime.now().difference(
              DateTime.fromMillisecondsSinceEpoch(cachedAt),
            ) <=
            const Duration(days: examsCacheDays);
    if (!force && cachedList.isNotEmpty && fresh) {
      state = state.copyWith(loading: false, notice: null);
      return;
    }
    try {
      // 会话可能还没建立，先确保登录；失败按获取失败处理。
      if (!await _ensureLogin()) throw Exception('未连接校园网');
      final e = await api.fetchExams();
      await cache.saveJson(key, e.map((x) => x.toJson()).toList());
      state = state.copyWith(
        exams: e,
        loading: false,
        notice: null,
        online: true,
        examsUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      state = state.copyWith(
        loading: false,
        notice: cachedList.isNotEmpty ? '获取失败，已显示缓存数据' : null,
      );
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
