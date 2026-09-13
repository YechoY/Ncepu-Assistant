// notification_service.dart —— 上课提醒的本地通知服务（单例）。
//
// 基于 flutter_local_notifications：zonedSchedule 注册的是系统级闹钟
// （Android AlarmManager），App 进程不需要存活，到点由系统发广播弹通知。
// 手机重启后系统闹钟会被清空，由 WorkManager 每日任务（reminder_jobs.dart）重排兜底。

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String channelId = 'lesson_reminder';
  static const String channelName = '上课提醒';
  static const String channelDesc = '上课前 20 分钟提醒上课';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _inited = false;

  /// 初始化时区（固定中国时区，避免设备时区设置影响上课时间）、通知插件与渠道。
  /// UI 与 WorkManager 后台 isolate 都会调用，幂等。
  Future<void> init() async {
    if (_inited) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
    );

    // high/max 重要性才有提示音、震动与横幅（ heads-up ）。
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDesc,
        importance: Importance.max,
      ),
    );
    _inited = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// 是否已具备「精确闹钟」能力（Android 12+）。不影响功能开关：
  /// 拿不到时调度自动降级为非精确闹钟（Doze 下可能延迟几分钟）。
  Future<bool> exactAlarmsAllowed() async {
    await init();
    final a = _android;
    if (a == null) return true;
    return (await a.canScheduleExactNotifications()) ?? true;
  }

  /// 首次开启提醒时调用：申请通知运行时权限（Android 13+）；
  /// 精确闹钟缺失则跳转系统「闹钟和提醒」授权页（会短暂离开 App）。
  /// 返回「通知权限是否拿到」——这是提醒能否展示的硬条件；精确闹钟不阻塞开启。
  Future<bool> requestPermissions() async {
    await init();
    final a = _android;
    if (a == null) return true;

    // 13 以下安装即有通知权限，插件在低版本上返回 true。
    final granted = await a.requestNotificationsPermission() ?? true;

    // 精确闹钟：声明 USE_EXACT_ALARM 的设备通常安装即授予；个别 ROM 仍需手动开。
    final exact = (await a.canScheduleExactNotifications()) ?? true;
    if (!exact) {
      // 跳系统设置页，用户操作完返回 App；是否真的授权由后续调度时再判断。
      await a.requestExactAlarmsPermission();
    }
    return granted;
  }

  /// 在 [when] 时刻弹一条上课通知。
  /// 优先精确闹钟；无权限/被 ROM 拦截时降级非精确闹钟，保证至少能排上。
  Future<void> scheduleLesson({
    required int id,
    required DateTime when,
    required String title,
    required String body,
  }) async {
    await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: Importance.max,
        priority: Priority.high,
      ),
    );
    final tzTime = tz.TZDateTime.from(when, tz.local);
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tzTime,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        // iOS 参数（本项目仅安卓）：按绝对时间解释，不随用户改时区而漂移。
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tzTime,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  /// 取消全部已排通知（关闭提醒 / 退出登录时）。
  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }
}
