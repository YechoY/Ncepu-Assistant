// app.dart —— 根组件 + 启动路由逻辑。
//
// 本文件包含三个关键 Widget：
//   1. HdjwApp   ：最外层的 MaterialApp（主题、语言、首页）。
//   2. _Gate     ：启动“门卫”，决定进 加载中 / 登录页 / 主界面。
//   3. _MainShell：登录后的主界面外壳（顶栏 + 4 个 Tab + 底部胶囊导航）。
//
// Dart 约定：以下划线 `_` 开头的类/变量是「库私有」的，只能在本文件内使用，
// 不会暴露给其它文件 import，相当于其它语言的 private。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; // 提供中文等系统语言包
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pages/classrooms_page.dart';
import 'pages/exams_page.dart';
import 'pages/full_timetable_page.dart';
import 'pages/grades_page.dart';
import 'pages/login_page.dart';
import 'pages/timetable_page.dart';
import 'providers/app_state.dart';
import 'providers/auth_state.dart';
import 'providers/data_state.dart';
import 'theme.dart';
import 'widgets/capsule_nav.dart';
import 'widgets/glass_background.dart';
import 'widgets/offline_banner.dart';
import 'widgets/top_bar.dart';

// StatelessWidget：无内部状态的 Widget。它的 UI 完全由构造参数决定，
// 一旦创建就不变。HdjwApp 只是配置一下整个 App，不需要自己维护状态，所以用无状态的即可。
class HdjwApp extends StatelessWidget {
  // 构造函数。`super.key` 把 key 传给父类；key 用于 Flutter 识别/复用 Widget，
  // 这里用不到具体值，但保留是良好习惯。const 构造函数能让实例被编译期优化。
  const HdjwApp({super.key});

  // build 方法：所有 Widget 的核心，返回「这个组件长什么样」的 Widget 树。
  // Flutter 会在需要刷新时反复调用 build。
  // `=> 表达式` 是 Dart 的箭头语法，等价于 `{ return 表达式; }`。
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '华电教务助手',
    debugShowCheckedModeBanner: false, // 关掉右上角那个 debug 红色横幅
    theme: buildTheme(), // 来自 theme.dart 的全局主题
    // 配置中文 locale，让 showDatePicker 等系统控件显示中文
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    // 这三个「本地化代理」负责把 Material/Widgets/Cupertino 组件里的文字翻译成对应语言。
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const _Gate(), // App 打开后显示的第一个页面 = 启动门卫
  );
}

// ConsumerStatefulWidget：Riverpod 提供的「有状态 + 能读 Provider」的 Widget。
// - StatefulWidget 能保存会变化的内部状态（这里的 phase / offline）。
// - Consumer 版本额外给了 ref，用来读取/监听 Provider。
class _Gate extends ConsumerStatefulWidget {
  const _Gate();
  // 有状态 Widget 分成两部分：Widget 本体（不可变配置）+ State（可变状态）。
  // createState 负责创建对应的 State 对象。
  @override
  ConsumerState<_Gate> createState() => _GateState();
}

// enum：枚举，表示启动的三种阶段。用枚举比用字符串/数字更安全、可读。
enum _Phase { boot, login, main }

// State 类才是真正存放可变状态和逻辑的地方。
class _GateState extends ConsumerState<_Gate> {
  _Phase phase = _Phase.boot; // 当前阶段，初始是「启动中」
  bool offline = false; // 是否处于离线模式

  // initState：State 创建后只调用一次，适合做初始化（发起启动流程）。
  @override
  void initState() {
    super.initState(); // 记得先调用父类实现
    _start(); // 触发异步启动流程（注意没 await，让它在后台跑）
  }

  // 启动流程（记住密码优先）：
  //   - 勾了「记住账号密码」→ 直接进主界面并展示缓存，随后后台联网登录并刷新；
  //     无网/缓存空也保持在主界面（首次联网后即可离线使用）。
  //   - 没勾「记住」→ 不保留任何数据（清空本地缓存），直接进登录页。
  Future<void> _start() async {
    final data = ref.read(dataStateProvider.notifier);
    final authSvc = ref.read(authServiceProvider);

    // 读取「是否记住账号密码」。没记住就不保留任何数据。
    final remembered = await authSvc.getRemember().catchError((_) => false);
    if (!remembered) {
      // 未勾记住：清掉可能残留的本地缓存与账号，回登录页。
      await data.clearAll().catchError((_) {});
      if (mounted) setState(() => phase = _Phase.login);
      return;
    }

    // 记住了：先把本地缓存读出来（离线也能立即展示），并直接进主界面。
    await data.loadFromCache();
    if (mounted) {
      setState(() {
        phase = _Phase.main;
        offline = true; // 先按“展示缓存”处理；后台联网成功会摘掉横幅
      });
    }

    // 后台联网登录 + 刷新（有校园网时才会成功；无网则继续用缓存留在主界面）。
    _backgroundRefresh();
  }

  // 后台刷新：探测网络，能上网就用记住的账号静默登录并按需刷新数据。
  // 全程 try/catch 吞掉异常——它只是“锦上添花”，任何失败都不应影响已经进入的主界面。
  Future<void> _backgroundRefresh() async {
    try {
      final online = await ref
          .read(onlineProvider.future)
          .catchError((_) => false);
      if (online) {
        final ok = await ref.read(authStateProvider.notifier).tryAutoLogin();
        if (ok) {
          await ref.read(dataStateProvider.notifier).dailyRefreshIfNeeded();
          // 登录成功后摘掉“离线/缓存”横幅（loggedIn 也会让 build 判定进入正常态）。
          if (mounted) setState(() => offline = false);
        }
      }
    } catch (_) {
      // 静默忽略：继续用缓存数据。
    }
    // 收尾：能进到这里说明用户已「记住账号」（_start 已校验），属于“首次联网后可离线”场景。
    // 因此即使当前无网/缓存为空（课表只缓存当周，跨周本就为空）也保持在主界面，不强制回登录页；
    // 待有校园网时后台会自动登录并刷新。只在“确实没记住账号”时才应处于登录页，那种情况根本走不到这里。
  }

  @override
  Widget build(BuildContext context) {
    // ref.watch：监听 authStateProvider，登录态一变化就自动重建本组件。
    // （read 是“读一次”，watch 是“持续监听并触发重建”，这是两者关键区别。）
    final auth = ref.watch(authStateProvider);
    // 界面阶段以 phase 为准（_start 已按“是否记住账号”决定 main/login）；
    // 额外地，只要本会话真正联网登录成功(loggedIn)，无论如何都进主界面。
    // 注意：不能写成“未 loggedIn 就登录页”，否则“记住账号、断网看缓存”这种
    // 已经把 phase 设为 main 的场景会被误判回登录页（正是断网被踢的根因）。
    final _Phase p;
    if (auth.loggedIn) {
      p = _Phase.main;
    } else {
      p = phase; // boot / main / login 均由启动流程决定
    }
    // switch 表达式（Dart 3 新语法）：根据 p 的枚举值直接返回对应的 Widget。
    // `=>` 后是每个分支的返回值，比传统 switch-case 更简洁。
    return switch (p) {
      _Phase.boot => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ), // 转圈加载
      _Phase.login => const LoginPage(),
      _Phase.main => _MainShell(offline: offline),
    };
  }
}

// 登录后的主界面外壳。也是有状态的（要记住当前选中的是哪个 Tab）。
class _MainShell extends ConsumerStatefulWidget {
  final bool offline; // 是否离线（由 _Gate 传进来）
  const _MainShell({required this.offline}); // required 表示这个命名参数必传
  @override
  ConsumerState<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<_MainShell> {
  int tab = 0; // 当前 Tab 下标：0课表 1成绩 2考试 3教室

  // static const：类级别的编译期常量（所有实例共享，不随对象创建）。四个页面的标题。
  static const titles = ['我的课表', '课程成绩', '考试安排', '空闲教室'];

  @override
  void initState() {
    super.initState();
    // 进入主界面后的自动刷新（节流，缓存优先，不打扰）：
    // addPostFrameCallback：注册一个「本帧渲染完成后」再执行的回调，
    // 之所以不在 initState 里直接调用，是因为此时界面还没画出来，
    // 等首帧画完再触发网络刷新，体验更顺、也避免在 build 过程中改状态报错。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 不强制刷新：周课表/学期周次按天节流（今天刷过就跳过），
      // 成绩、当前学期考试缓存 7 天内直接用；各类数据都可由右上角按钮手动刷新。
      // 每次启动还会顺带清理本周之前的历史周课表缓存（在该方法内部完成）。
      if (ref.read(authStateProvider).loggedIn) {
        ref.read(dataStateProvider.notifier).dailyRefreshIfNeeded();
      }
    });
  }

  // 退出登录：先弹确认框，确认后清数据并跳回登录页。
  Future<void> _logout() async {
    // showDialog 返回一个 Future<bool?>：用户点了哪个按钮通过 Navigator.pop 带回来。
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('退出登录', style: TextStyle(fontSize: 16)),
        content: const Text(
          '退出将清除本地登录信息，需要重新输入账号密码才能登录，确定吗？',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), // 关闭对话框并返回 false
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true), // 返回 true
            child: const Text('退出', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authStateProvider.notifier).logout(); // 清账号密码 + 缓存
      // 又是 async 后用 context，先判 mounted 更安全。
      if (mounted) {
        // pushAndRemoveUntil：跳到登录页并「清空」整个页面栈（第二个参数恒 false = 全部移除），
        // 这样用户按返回键也回不到已登出的主界面。
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (_) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 四个 Tab 对应的页面实例。用 IndexedStack 承载（见下），能保留各页状态。
    final pages = [
      const TimetablePage(),
      const GradesPage(),
      const ExamsPage(),
      const ClassroomsPage(),
    ];
    final user = ref.watch(authStateProvider); // 监听登录信息（姓名/班级）
    final state = ref.watch(dataStateProvider); // 监听数据状态（是否有提示 notice）
    // 顶部用户胶囊要显示的文字：优先「姓名 · 班级」，否则学号，否则“未登录”。
    // 这是 Dart 的三元表达式嵌套写法。
    final userLabel = user.name.isNotEmpty
        ? '${user.name} · ${user.className}'
        : user.username.isNotEmpty
        ? user.username
        : '未登录';
    // Scaffold：Material 页面骨架，提供 body、appBar、底部栏等标准结构。
    return Scaffold(
      body: GlassBackground(
        // 自定义的渐变毛玻璃背景
        child: SafeArea(
          // 避开刘海、状态栏、底部手势条等系统区域
          child: Column(
            // 纵向排列：顶栏 → (离线条) → 页面内容 → 底部导航
            children: [
              TopBar(
                title: titles[tab],
                // 标题下方显示该页数据的最后更新时间（教室页数据不缓存，其时间在页内显示）。
                subtitle: switch (tab) {
                  0 => '更新：${formatUpdatedAt(state.timetableUpdatedAt)}',
                  1 => '更新：${formatUpdatedAt(state.gradesUpdatedAt)}',
                  2 => '更新：${formatUpdatedAt(state.examsUpdatedAt)}',
                  _ => null,
                },
                showRefresh: tab != 3, // 空闲教室页(3)不显示刷新按钮（它每次实时查）
                // 仅课表页(0)在标题栏放一个「全部课表」入口，点击进入整学期课表页。
                trailing: tab == 0
                    ? TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const FullTimetablePage(),
                          ),
                        ),
                        icon: const Icon(
                          Icons.grid_view_rounded,
                          size: 16,
                          color: kPrimary,
                        ),
                        label: const Text(
                          '全部',
                          style: TextStyle(
                            fontSize: 12,
                            color: kPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      )
                    : null,
                // onRefresh 根据当前 Tab 决定刷新哪块数据。用 switch 表达式返回不同的回调函数。
                onRefresh: switch (tab) {
                  0 => () {
                    final week = ref.read(dataStateProvider).timetableWeek;
                    if (week.isNotEmpty) {
                      // 点刷新：强制联网重查当周课表，使更新时间刷新
                      ref
                          .read(dataStateProvider.notifier)
                          .loadTimetable(week, force: true);
                    }
                  },
                  1 =>
                    () => ref.read(dataStateProvider.notifier).refreshGrades(),
                  _ =>
                    () => ref
                        .read(dataStateProvider.notifier)
                        .refreshExams(force: true), // _ 是默认分支：手动刷新强制联网
                },
                userName: userLabel,
                // 点用户胶囊 → 从底部弹出「关于 / 退出登录」菜单。
                onUserTap: () => showModalBottomSheet(
                  context: context,
                  builder: (_) =>
                      _UserMenuSheet(onAbout: _about, onLogout: _logout),
                ),
              ),
              // 集合内 if：只有条件成立时才把这个 Widget 放进 children 列表。
              // 离线横幅：进入时按缓存展示(widget.offline=true)，一旦本会话成功联网
              // (state.online=true，登录/手动刷新任一成功都会置位)就自动摘掉。
              if (widget.offline && !state.online) const OfflineBanner(),
              if (state.notice != null)
                OfflineBanner(text: state.notice!), // 临时提示（如“获取失败”）
              // Expanded：在 Column/Row 里「占满剩余空间」。
              // IndexedStack：把所有子页面都建出来叠在一起，只显示 index 指定的那个。
              // 好处是切 Tab 时其它页面不会被销毁，滚动位置/输入内容都能保留。
              Expanded(
                child: IndexedStack(index: tab, children: pages),
              ),
              // 底部 4 标签胶囊导航；点击时 setState 改 tab，触发重建切页。
              CapsuleNav(index: tab, onTap: (i) => setState(() => tab = i)),
            ],
          ),
        ),
      ),
    );
  }

  // 关于对话框。
  void _about() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('华电教务助手', style: TextStyle(fontSize: 17)),
        content: const Text(
          '华北电力大学教务系统助手\n版本 1.0.0\n数据来自 jwxt.ncepu.edu.cn',
          style: TextStyle(fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }
}

/// 用户胶囊弹出的底部菜单。
class _UserMenuSheet extends StatelessWidget {
  final VoidCallback onAbout;
  final VoidCallback onLogout;
  const _UserMenuSheet({required this.onAbout, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于', style: TextStyle(fontSize: 14)),
            onTap: () {
              Navigator.pop(context); // 先关掉底部菜单
              onAbout();
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              '退出登录',
              style: TextStyle(fontSize: 14, color: Colors.red),
            ),
            onTap: () {
              Navigator.pop(context); // 先关掉底部菜单
              onLogout();
            },
          ),
        ],
      ),
    );
  }
}
