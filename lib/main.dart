// main.dart —— 整个 App 的入口文件。
//
// Flutter/Dart 的程序入口是顶层函数 `main()`（和 C/Java 的 main 一样）。
// Flutter App 一定要在 main 里调用 runApp()，把「根 Widget」交给框架去渲染。

// import：引入外部包或本项目其它文件。
// - `package:xxx/...` 是引用 pub.dev 上的第三方包（在 pubspec.yaml 里声明过）。
// - 相对路径（如 'app.dart'）引用的是本项目 lib/ 下的文件。
import 'package:flutter/material.dart'; // Material Design 组件库（Widget、主题、颜色等）
import 'package:flutter_riverpod/flutter_riverpod.dart'; // 状态管理框架 Riverpod
import 'package:path_provider/path_provider.dart'; // 拿到手机上「应用专属目录」的路径
import 'package:shared_preferences/shared_preferences.dart'; // 读取提醒开关等简单设置
import 'package:workmanager/workmanager.dart'; // 上课提醒的每日后台重排任务

import 'app.dart'; // 根组件 HdjwApp
import 'providers/app_state.dart'; // 里面定义了 cacheServiceProvider（缓存服务的“插座”）
import 'providers/settings_state.dart'; // SettingsNotifier.reminderEnabledKey
import 'services/cache_service.dart'; // SQLite 缓存服务
import 'services/notification_service.dart'; // 本地通知服务（上课提醒）
import 'services/reminder_jobs.dart'; // WorkManager 后台回调与任务注册

// Dart 里 async 函数返回 Future；main 需要 await 一些异步初始化，所以声明成 `Future<void> async`。
Future<void> main() async {
  // 只要在 runApp 之前调用了异步代码（比如下面读文件目录、打开数据库），
  // 就必须先手动初始化 Flutter 引擎与 Widget 绑定，否则会报错。
  WidgetsFlutterBinding.ensureInitialized();

  // 上课提醒：初始化通知渠道与中国时区；注册 WorkManager 后台入口。
  // 两者都要在 App 启动早期就绪，保证后台任务与开机恢复可用。
  await NotificationService.instance.init();
  await Workmanager().initialize(reminderCallbackDispatcher);

  // 获取「应用文档目录」——这是系统分配给本 App 的私有目录，卸载 App 时会一起清除，
  // 适合存数据库、缓存等。await 表示等这个异步操作完成再往下走。
  final dir = await getApplicationDocumentsDirectory();

  // 在这个目录下打开（或首次创建）SQLite 缓存数据库。
  // 放在 runApp 之前打开，是为了让缓存服务「就绪后」再注入给整个 App 使用。
  final cache = await CacheService.open(dir.path);

  // 若上次已开启上课提醒，启动时确保每日后台任务在位（keep：已注册则不重复创建）。
  // 手机重启后 App 首次被系统/用户拉起时，靠这里重新挂上任务。
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(SettingsNotifier.reminderEnabledKey) ?? false) {
    await registerReminderJob();
  }

  // runApp 启动 App，参数是根 Widget。
  runApp(
    // ProviderScope 是 Riverpod 的根容器：所有 Provider（全局状态/服务）都必须
    // 被它包在里面才能使用。它一般就放在整棵 Widget 树的最外层。
    ProviderScope(
      // overrides：用「已经创建好的实例」去覆盖某个 Provider 的默认实现。
      // app_state.dart 里 cacheServiceProvider 默认会抛异常（因为缓存必须异步打开，
      // Provider 本身不能 await）。这里把上面打开好的 cache 注入进去，
      // 之后任何地方 ref.read(cacheServiceProvider) 拿到的都是同一个实例。
      overrides: [cacheServiceProvider.overrideWithValue(cache)],
      // child：真正的应用根组件。const 表示这是编译期常量，Flutter 可以复用它、减少重建。
      child: const HdjwApp(),
    ),
  );
}
