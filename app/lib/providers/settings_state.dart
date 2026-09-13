// settings_state.dart —— 应用设置（上课提醒开关 + 提前提醒分钟数）。
//
// 设置持久化在 shared_preferences；开启提醒时注册 WorkManager 每日任务并立即重排一次，
// 关闭（或退出登录）时取消后台任务与全部已排通知；修改提前分钟数后立即重排。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/lesson_times.dart';
import '../services/notification_service.dart';
import '../services/reminder_jobs.dart';
import '../services/reminder_scheduler.dart';
import 'app_state.dart';

class SettingsState {
  final bool reminderEnabled;
  final int reminderLeadMinutes; // 提前多少分钟提醒（默认 20，可 10/20/自定义）
  const SettingsState({
    this.reminderEnabled = false,
    this.reminderLeadMinutes = lessonReminderLeadMinutes,
  });
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final Ref ref;
  SettingsNotifier(this.ref) : super(const SettingsState()) {
    load();
  }

  /// shared_preferences 的键（main.dart 启动、后台任务也要读，故公开）。
  static const String reminderEnabledKey = 'class_reminder_enabled';
  static const String reminderLeadKey = 'class_reminder_lead_minutes';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(reminderEnabledKey) ?? false;
    final lead = prefs.getInt(reminderLeadKey) ?? lessonReminderLeadMinutes;
    state = SettingsState(reminderEnabled: enabled, reminderLeadMinutes: lead);
  }

  /// 开启上课提醒：先请求权限，再注册后台任务并立即重排。
  /// granted=false 表示通知权限被拒（未开启）；exact=false 表示精确闹钟未授予（已开启但会降级）。
  Future<({bool granted, bool exact})> enable() async {
    final granted = await NotificationService.instance.requestPermissions();
    if (!granted) return (granted: false, exact: false);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(reminderEnabledKey, true);
    state = SettingsState(
      reminderEnabled: true,
      reminderLeadMinutes: state.reminderLeadMinutes,
    );

    await registerReminderJob();
    // 立即按当前课表排一次，不用等后台任务。
    await rescheduleIfEnabled(force: true);
    final exact = await NotificationService.instance.exactAlarmsAllowed();
    return (granted: true, exact: exact);
  }

  /// 关闭上课提醒：取消后台任务 + 清空所有已排通知。
  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(reminderEnabledKey, false);
    state = SettingsState(
      reminderEnabled: false,
      reminderLeadMinutes: state.reminderLeadMinutes,
    );
    await cancelReminderJob();
    await NotificationService.instance.cancelAll();
  }

  /// 修改提前提醒分钟数（10/20/自定义 1~180）：保存后立即重排。
  Future<void> setLeadMinutes(int minutes) async {
    final v = minutes.clamp(1, 180);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(reminderLeadKey, v);
    state = SettingsState(
      reminderEnabled: state.reminderEnabled,
      reminderLeadMinutes: v,
    );
    if (state.reminderEnabled) await rescheduleIfEnabled(force: true);
  }

  /// 课表数据变化 / 进主界面时调用：开关开着才重排。
  /// [force] 跳过 10 秒节流（改设置、首次开启时需要立即生效）。
  Future<void> rescheduleIfEnabled({bool force = false}) async {
    if (force) ReminderScheduler.resetThrottle();
    await ReminderScheduler.onUiDataChanged(
      enabled: state.reminderEnabled,
      leadMinutes: state.reminderLeadMinutes,
      api: ref.read(apiClientProvider),
      cache: ref.read(cacheServiceProvider),
    );
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) => SettingsNotifier(ref),
);
