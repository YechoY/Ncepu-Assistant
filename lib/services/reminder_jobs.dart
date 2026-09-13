// reminder_jobs.dart —— WorkManager 后台任务：每天重排上课提醒。
//
// 作用：手机重启后系统闹钟会被清空，WorkManager 自带开机重新注册能力
// （需要 RECEIVE_BOOT_COMPLETED 权限），周期任务触发时在后台 isolate 里
// 读本地缓存课表重新排闹钟，全程不联网。任务执行时刻不精确无所谓
// （被 Doze 推迟几小时也不影响「当天课程已排好」这个结果）。

import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import 'cache_service.dart';
import 'reminder_scheduler.dart';

/// 周期任务的唯一名（WorkManager 去重/取消用）。
const String reminderRescheduleUniqueName = 'com.hdjw.lessonReminder.daily';

/// 任务标识（executeTask 回调里按它区分任务）。
const String reminderRescheduleTaskName = 'rescheduleLessonReminders';

/// WorkManager 的后台入口，必须是顶层函数并加 vm:entry-point，
/// 否则 release（AOT）编译后可能被树优化掉。
@pragma('vm:entry-point')
void reminderCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      // 后台 isolate 是独立执行环境：缓存库、通知插件都要在这里重新初始化。
      final dir = await getApplicationDocumentsDirectory();
      final cache = await CacheService.open(dir.path);
      await ReminderScheduler.rescheduleFromCache(cache);
      await cache.close();
      return true;
    } catch (_) {
      // 失败也返回 true（成功）：周期任务明天还会再跑，
      // 返回 false 会触发指数退避重试，反而堆积无意义的唤醒。
      return true;
    }
  });
}

/// 注册（或保持）每日重排任务。频率 12 小时是下限附近的折中：
/// 系统会按自身策略调整实际触发时间，这里只保证「一天内至少重排一次」。
Future<void> registerReminderJob() {
  return Workmanager().registerPeriodicTask(
    reminderRescheduleUniqueName,
    reminderRescheduleTaskName,
    frequency: const Duration(hours: 12),
    existingWorkPolicy: ExistingWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.not_required),
  );
}

/// 取消每日重排任务（关闭提醒 / 退出登录）。
Future<void> cancelReminderJob() =>
    Workmanager().cancelByUniqueName(reminderRescheduleUniqueName);
