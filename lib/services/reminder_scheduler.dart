// reminder_scheduler.dart —— 上课提醒重排逻辑（UI 侧与 WorkManager 后台共用）。
//
// 数据来源：周课表缓存 timetable_<周一>（周课表接口返回的是该周「实际」课程，含调课结果，
// 比整学期课表的周次区间更准）。UI 侧缺缓存时会联网补拉本周/下周并写缓存；
// 后台任务只读缓存、不联网（后台没有登录态）。
//
// 重排策略：每次先 cancelAll 再排「从现在起未来 7 天」的课程，保证幂等不重复。
// 已过提醒时刻（上课前 20 分钟）的课程自动跳过。

import 'package:shared_preferences/shared_preferences.dart';

import '../models/timetable_row.dart';
import '../providers/data_state.dart' show mondayOf, ttFromJson, ttToJson;
import '../providers/settings_state.dart';
import 'api_client.dart';
import 'cache_service.dart';
import 'lesson_times.dart';
import 'notification_service.dart';

class ReminderScheduler {
  ReminderScheduler._();

  /// 简单节流：进主界面、loadFromCache、手动刷新可能在几秒内连续触发，避免重复联网/重排。
  static DateTime? _lastRun;

  /// 本次进程已联网补拉过的周（周一 key），避免同一周反复请求。
  static final Set<String> _fetched = {};

  /// 放开 10 秒节流（改设置、首次开启需要立即重排时调用）。
  static void resetThrottle() => _lastRun = null;

  /// UI 侧入口（进主界面后、课表数据更新后调用）。
  /// [enabled] 为 false（用户没开提醒）时什么都不做。
  static Future<void> onUiDataChanged({
    required bool enabled,
    required int leadMinutes,
    required ApiClient api,
    required CacheService cache,
  }) async {
    if (!enabled) return;
    final now = DateTime.now();
    if (_lastRun != null &&
        now.difference(_lastRun!) < const Duration(seconds: 10)) {
      return;
    }
    _lastRun = now;
    await _run(
      now: now,
      api: api,
      cache: cache,
      allowNetwork: true,
      leadMinutes: leadMinutes,
    );
  }

  /// WorkManager 后台入口：只依赖本地缓存，不联网、不节流（每天就跑一两次）。
  /// 提前分钟数与开关一起存在 SharedPreferences，后台直接读。
  static Future<void> rescheduleFromCache(CacheService cache) async {
    await NotificationService.instance.init();
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(SettingsNotifier.reminderEnabledKey) ?? false;
    if (!enabled) return;
    final lead =
        prefs.getInt(SettingsNotifier.reminderLeadKey) ??
        lessonReminderLeadMinutes;
    await _run(
      now: DateTime.now(),
      api: null,
      cache: cache,
      allowNetwork: false,
      leadMinutes: lead,
    );
  }

  static Future<void> _run({
    required DateTime now,
    required ApiClient? api,
    required CacheService cache,
    required bool allowNetwork,
    required int leadMinutes,
  }) async {
    final today = DateTime(now.year, now.month, now.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    final nextMonday = thisMonday.add(const Duration(days: 7));

    // 收集本周、下周课表：缓存优先；UI 侧缺缓存时联网补拉并回写，供后台日后使用。
    final rowsByMonday = <String, List<TimetableRow>>{};
    var networkFailed = false; // 有联网失败时放开节流，允许登录完成后立即重试
    for (final m in [thisMonday, nextMonday]) {
      final key = mondayOf(m);
      var rows = await _loadCached(cache, key);
      if ((rows == null || rows.isEmpty) &&
          allowNetwork &&
          api != null &&
          !_fetched.contains(key)) {
        try {
          final fresh = await api.fetchTimetable(key);
          if (fresh.isNotEmpty) {
            await cache.saveJson('timetable_$key', ttToJson(fresh));
            rows = fresh;
            // 只有真正拉到数据才记入“已补拉”；失败（如冷启动时会话尚未恢复）
            // 不标记，登录完成后的下一次重排仍会重试。
            _fetched.add(key);
          } else {
            networkFailed = true;
          }
        } catch (_) {
          networkFailed = true; // 离线/会话失效：下周排不上就算了，本周缓存仍可能有效
        }
      }
      if (rows != null && rows.isNotEmpty) rowsByMonday[key] = rows;
    }
    // 有失败就别占着节流窗口——自动登录成功、课表刷新后会立刻触发下一次重排。
    if (networkFailed) _lastRun = null;

    // 全量重排：本应用只有这一类通知，cancelAll 最简单且保证幂等。
    await NotificationService.instance.cancelAll();
    for (var i = 0; i < 7; i++) {
      final day = today.add(Duration(days: i));
      final rows = rowsByMonday[mondayOf(day)];
      if (rows == null) continue;
      await _scheduleDay(day, rows, now, leadMinutes);
    }
  }

  static Future<List<TimetableRow>?> _loadCached(
    CacheService cache,
    String monday,
  ) async {
    final raw = await cache.loadJson('timetable_$monday', ttlDays: 30);
    if (raw is! List) return null;
    final rows = ttFromJson(raw);
    return rows.isEmpty ? null : rows;
  }

  /// 排某一天 5 个大节的课程提醒。
  static Future<void> _scheduleDay(
    DateTime day,
    List<TimetableRow> rows,
    DateTime now,
    int leadMinutes,
  ) async {
    final weekday = day.weekday; // DateTime：1=周一 … 7=周日，与课表列对齐
    for (final row in rows) {
      if (weekday - 1 >= row.cells.length) continue;
      final cell = row.cells[weekday - 1];
      if (cell.name.isEmpty) continue;

      final firstSection = _firstLessonOfSection(row.section);
      if (firstSection == null) continue;
      final startMin = lessonStartMinutes[firstSection];
      if (startMin == null) continue; // 未知节次作息，不排

      final start = DateTime(
        day.year,
        day.month,
        day.day,
        startMin ~/ 60,
        startMin % 60,
      );
      final remindAt = start.subtract(Duration(minutes: leadMinutes));
      if (!remindAt.isAfter(now)) continue; // 提醒时刻已过（含正在上课），跳过

      await NotificationService.instance.scheduleLesson(
        id: _notificationId(day, firstSection),
        when: remindAt,
        title: '$leadMinutes 分钟后有课',
        body: cell.location.isEmpty
            ? cell.name
            : '${cell.name} · ${cell.location}',
      );
    }
  }

  /// 周课表行首 section 实际是中文大节名「第一大节」…「第五大节」，
  /// 映射为该大节的首小节号（1/3/5/7/9），与 lessonStartMinutes 的 key 对齐；
  /// 同时兼容形如 "1-2" 的写法。
  static int? _firstLessonOfSection(String section) {
    const cn = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
      '十': 10,
    };
    final m = RegExp(r'第([一二三四五六七八九十])大节').firstMatch(section);
    if (m != null) {
      final big = cn[m.group(1)!];
      if (big == null) return null;
      return (big - 1) * 2 + 1; // 第1大节→第1小节，第2大节→第3小节……
    }
    return int.tryParse(section.split('-').first);
  }

  /// 通知 ID 用「日期序号 × 10 + 大节首节次」，同一课程每次重排得到相同 ID。
  /// 2024 年起算，2030 年前绝对值都远小于 int32 上限。
  static int _notificationId(DateTime day, int firstSection) {
    final ordinal = DateTime(
      day.year,
      day.month,
      day.day,
    ).difference(DateTime(2024, 1, 1)).inDays;
    return ordinal * 10 + firstSection;
  }
}
