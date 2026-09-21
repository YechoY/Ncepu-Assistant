// app.dart —— 根组件 + 启动路由逻辑。
//
// 本文件包含三个关键 Widget：
//   1. HdjwApp   ：最外层的 MaterialApp（主题、语言、首页）。
//   2. _Gate     ：启动“门卫”，决定进 加载中 / 登录页 / 主界面。
//   3. _MainShell：登录后的主界面外壳（顶栏 + 4 个 Tab + 底部胶囊导航）。
//
// Dart 约定：以下划线 `_` 开头的类/变量是「库私有」的，只能在本文件内使用，
// 不会暴露给其它文件 import，相当于其它语言的 private。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard：复制下载链接
import 'package:flutter_localizations/flutter_localizations.dart'; // 提供中文等系统语言包
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http; // GitHub API 查询最新版本
import 'package:open_filex/open_filex.dart'; // 打开下载完成的 APK 触发安装
import 'package:package_info_plus/package_info_plus.dart'; // 运行时读取版本号
import 'package:path_provider/path_provider.dart'; // APK 下载临时目录
import 'package:url_launcher/url_launcher.dart'; // 前往浏览器下载新版本

import 'pages/classrooms_page.dart';
import 'pages/exams_page.dart';
import 'pages/full_timetable_page.dart';
import 'pages/grades_page.dart';
import 'pages/module_nav_page.dart';
import 'pages/timetable_page.dart';
import 'providers/auth_state.dart';
import 'providers/data_state.dart';
import 'theme.dart';
import 'widgets/capsule_nav.dart';
import 'widgets/glass_background.dart';
import 'widgets/glass_card.dart';
import 'widgets/glass_snackbar.dart';
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
    title: '掌上华电',
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
  @override
  ConsumerState<_Gate> createState() => _GateState();
}

class _GateState extends ConsumerState<_Gate> {
  bool _booting = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _booting = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(
        body: GlassBackground(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return const ModuleNavPage();
  }
}

// 登录后的主界面外壳。也是有状态的（要记住当前选中的是哪个 Tab）。
// 注意：从 _Gate 改名为公开的 MainShell，因为学习服务登录页需要 push 它。
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key}); // 不再需要 offline 参数（入口已统一到模块导航页）
  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
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

  // 退出登录：清数据 + pop 回模块导航页（不再让 _Gate 切回 LoginPage）。
  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x402E3350),
      builder: (_) => const _GlassDialog(
        title: '退出学习服务',
        content: Text(
          '退出将清除本地教务登录信息，需要重新输入账号密码才能登录，确定吗？',
          style: TextStyle(fontSize: 12.5, height: 1.55, color: kTextMuted),
        ),
        cancelText: '取消',
        confirmText: '退出',
        destructive: true,
        popResult: true,
      ),
    );
    if (ok == true) {
      await ref.read(authStateProvider.notifier).logout();
      if (mounted) Navigator.of(context).pop(); // 回模块导航页
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                      color: kPrimary,
                    ),
                  ),
                ),
              ),
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
                onUserTap: () => showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  barrierColor: const Color(0x4D2E3350),
                  builder: (_) => _UserMenuSheet(onLogout: _logout),
                ),
              ),
              if (state.notice != null) OfflineBanner(text: state.notice!),
              // Expanded：在 Column/Row 里「占满剩余空间」。
              // IndexedStack：把所有子页面都建出来叠在一起，只显示 index 指定的那个。
              // 好处是切 Tab 时其它页面不会被销毁，滚动位置/输入内容都能保留。
              // 外层再包一层 _TabFade：切页时新页面淡入 + 轻微放大，
              // 既符合玻璃风的轻盈感，也掩盖了页面首帧光栅化可能造成的顿挫。
              Expanded(
                child: IndexedStack(
                  index: tab,
                  children: [
                    for (var i = 0; i < pages.length; i++)
                      _TabFade(active: i == tab, child: pages[i]),
                  ],
                ),
              ),
              // 底部 4 标签胶囊导航；点击时 setState 改 tab，触发重建切页。
              CapsuleNav(index: tab, onTap: (i) => setState(() => tab = i)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 关于弹窗里的单行声明：普通文字灰、关键词墨紫加粗，强化「非官方」的醒目度。
class _AboutLine extends StatelessWidget {
  final String text;
  final String bold;
  final String? tail;
  const _AboutLine({this.text = '', required this.bold, this.tail});
  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: 13.5, height: 1.55, color: kTextMuted),
        children: [
          if (text.isNotEmpty) TextSpan(text: text),
          TextSpan(
            text: bold,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: kInk,
            ),
          ),
          if (tail != null) TextSpan(text: tail),
        ],
      ),
    );
  }
}

/// 判断远端 tag 是否比本地版本新：tag 形如 `v1.0.0+8`，
/// 有 `+构建号` 时优先比构建号（整数，最可靠）；否则按 主.次.补 逐段比较。
bool _isRemoteNewer(String tag, String localVersion, int localBuild) {
  var t = tag;
  if (t.startsWith('v') || t.startsWith('V')) t = t.substring(1);
  if (t.contains('+')) {
    final code = int.tryParse(t.split('+').last);
    if (code != null) return code > localBuild;
    t = t.split('+').first;
  }
  final remote = t.split('.').map((e) => int.tryParse(e.trim()) ?? 0).toList();
  final local = localVersion
      .split('.')
      .map((e) => int.tryParse(e.trim()) ?? 0)
      .toList();
  for (var i = 0; i < 3; i++) {
    final r = i < remote.length ? remote[i] : 0;
    final l = i < local.length ? local[i] : 0;
    if (r != l) return r > l;
  }
  return false;
}

/// 关于弹窗：免责声明 + 版本号 + 检查更新一体。
/// 检查失败时提供「复制在线链接」，用户可在浏览器手动打开 Releases 页。
class AppAboutDialog extends StatefulWidget {
  const AppAboutDialog({super.key});

  @override
  State<AppAboutDialog> createState() => AppAboutDialogState();
}

class AppAboutDialogState extends State<AppAboutDialog> {
  static const _releasesUrl =
      'https://github.com/YechoY/Ncepu-Assistant/releases/latest';

  /// 检查阶段：idle 未检查 | checking 检查中 | fail 失败 | latest 已最新 | newer 有新版
  /// downloading 下载中 | ready 下载完成待安装 | dlfail 下载失败
  String _phase = 'idle';
  PackageInfo? _info;
  String _tag = ''; // 远端最新 tag（含 v 前缀）
  String _body = ''; // Release 更新说明
  String _htmlUrl = ''; // Release 页面地址
  String _apkUrl = ''; // APK 附件直链（Release 资产）
  double _progress = 0; // 下载进度 0.0-1.0
  bool _copied = false;
  HttpClientRequest? _dlReq; // 进行中的下载请求，用于取消
  HttpClient? _dlClient; // 进行中的下载客户端，取消时强制断开连接
  bool _cancelled = false; // 区分「用户主动取消」与「下载真失败」

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((v) {
      if (mounted) setState(() => _info = v);
    });
  }

  Future<void> _check() async {
    setState(() => _phase = 'checking');
    Map<String, dynamic>? release;
    try {
      final res = await http
          .get(
            Uri.parse(
              'https://api.github.com/repos/YechoY/Ncepu-Assistant/releases/latest',
            ),
            headers: const {
              'User-Agent': 'hdjw_assistant', // GitHub API 要求 UA
              'Accept': 'application/vnd.github+json',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        release =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      }
    } catch (_) {
      // 网络异常/超时：展示失败态
    }
    if (!mounted) return;
    final info = _info;
    if (release == null || info == null) {
      setState(() {
        _phase = 'fail';
        _copied = false;
      });
      return;
    }
    final tag = (release['tag_name'] as String? ?? '').trim();
    final body = (release['body'] as String? ?? '').trim();
    final htmlUrl = release['html_url'] as String? ?? '';
    // 解析 Release 附件里的 APK 直链（应用内下载用；没有则退回浏览器方案）
    var apkUrl = '';
    final assets = release['assets'] as List? ?? const [];
    for (final a in assets) {
      final name = (a['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.apk')) {
        apkUrl = a['browser_download_url'] as String? ?? '';
        break;
      }
    }
    final newer = _isRemoteNewer(
      tag,
      info.version,
      int.tryParse(info.buildNumber) ?? 0,
    );
    setState(() {
      _tag = tag.startsWith('v') ? tag : 'v$tag';
      _body = body;
      _htmlUrl = htmlUrl;
      _apkUrl = apkUrl;
      _phase = newer ? 'newer' : 'latest';
    });
  }

  /// APK 本地保存路径（临时目录，文件名带 tag 防止新旧版本混淆）。
  Future<String> _apkPath() async {
    final dir = await getTemporaryDirectory();
    final safeTag = _tag.replaceAll(RegExp(r'[^0-9A-Za-z.]'), '_');
    return '${dir.path}/update_$safeTag.apk';
  }

  /// 应用内下载 APK（带进度），完成后进入 ready 待安装。
  Future<void> _startDownload() async {
    if (_apkUrl.isEmpty) return;
    // Android 8+ 需先授予「安装未知应用」权限，否则下载完也无法安装。
    try {
      const ch = MethodChannel('app_installer');
      final can = await ch.invokeMethod<bool>('canRequestInstall');
      if (can != true) {
        await ch.invokeMethod('openInstallSetting');
        if (!mounted) return;
        showGlassSnackBar(context, '请允许「安装未知应用」后重新点击下载');
        return;
      }
    } catch (_) {
      // MethodChannel 不可用（低版本系统等）时直接尝试下载与安装。
    }
    setState(() {
      _phase = 'downloading';
      _progress = 0;
      _cancelled = false;
    });
    HttpClient? client;
    Timer? watch;
    try {
      final path = await _apkPath();
      final file = File(path);
      if (await file.exists()) await file.delete();
      client = HttpClient();
      _dlClient = client;
      final req = await client.getUrl(Uri.parse(_apkUrl));
      req.headers.set('User-Agent', 'hdjw_assistant');
      _dlReq = req;
      // 连接超时：国内直连 GitHub 的 TLS 握手经常挂起，15s 连不上判失败
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final total = res.contentLength;
      var received = 0;
      final sink = file.openWrite();
      // 停滞/总时长检测：每 5s 巡检——
      //   20s 内收到的字节无增长（连接挂起/断流）→ 判失败；
      //   整体超过 180s 未完成（网络极慢滴流，空闲超时抓不住）→ 判失败。
      // abort 抛异常后统一走 catch 进入「下载失败」。
      {
        final startedAt = DateTime.now();
        var lastBytes = 0;
        var lastProgressAt = startedAt;
        watch = Timer.periodic(const Duration(seconds: 5), (t) {
          final now = DateTime.now();
          if (received != lastBytes) {
            lastBytes = received;
            lastProgressAt = now;
          }
          final stalled = now.difference(lastProgressAt).inSeconds >= 20;
          final tooLong = now.difference(startedAt).inSeconds >= 180;
          if (stalled || tooLong) {
            t.cancel();
            _dlReq?.abort(const HttpException('下载超时'));
            _dlClient?.close(force: true);
          }
        });
      }
      await for (final chunk in res.timeout(const Duration(seconds: 30))) {
        received += chunk.length;
        sink.add(chunk);
        // 进度变化超过 1% 才刷新，避免 setState 过频
        if (total > 0 && mounted) {
          final p = received / total;
          if (p - _progress >= 0.01) setState(() => _progress = p);
        }
      }
      await sink.close();
      if (total > 0 && received < total) throw Exception('下载不完整');
      if (!mounted) return;
      setState(() => _phase = 'ready');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _cancelled ? 'newer' : 'dlfail';
        _progress = 0;
      });
    } finally {
      watch?.cancel();
      _dlReq = null;
      _dlClient = null;
      client?.close(force: true);
    }
  }

  /// 取消下载：abort 请求并强制断开底层连接。
  /// 仅 abort 不带 error 时，已建立的响应流可能静默继续（取消看似无效果），
  /// 所以带 error 让 await for 立即抛出，再 forceClose 兜底断开 socket。
  void _cancelDownload() {
    _cancelled = true;
    _dlReq?.abort(const HttpException('下载已取消'));
    _dlClient?.close(force: true);
  }

  /// 打开下载完成的 APK，交给系统安装器。
  Future<void> _install() async {
    try {
      final path = await _apkPath();
      await OpenFilex.open(
        path,
        type: 'application/vnd.android.package-archive',
      );
    } catch (_) {
      if (mounted) showGlassSnackBar(context, '安装失败，请用「复制在线链接」到浏览器下载');
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(const ClipboardData(text: _releasesUrl));
    if (!mounted) return;
    setState(() => _copied = true);
    Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        // 限高 75% 屏高：内容（尤其检查更新状态区变长后）超出时可滚动，
        // 弹窗不会被屏幕下缘遮住。
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: GlassCard(
          radius: 22,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '掌上华电',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: kInk,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const _AboutLine(
                        text: '① ',
                        bold: '非官方应用',
                        tail: '，由学生个人 vibecoding 独立开发，仅供学习交流',
                      ),
                      const SizedBox(height: 4),
                      const _AboutLine(
                        text: '② 数据来自华电（保定）教务系统官网，账号密码等数据',
                        bold: '仅保存在本机',
                        tail: '，不上传、不同步至任何第三方服务器',
                      ),
                      const SizedBox(height: 4),
                      const _AboutLine(
                        text: '③ 不用于任何商业用途，使用产生的一切后果',
                        bold: '由使用者自行承担',
                      ),
                      const SizedBox(height: 4),
                      const _AboutLine(
                        text: '④ 在法律允许的范围内，开发者保留对本声明的',
                        bold: '最终解释权',
                        tail: '；如与法律法规相冲突，以法律法规为准',
                      ),
                      const SizedBox(height: 12),
                      if (info != null)
                        _AboutLine(text: '当前版本 ', bold: 'v${info.version}'),
                      const SizedBox(height: 10),
                      _updateArea(),
                    ],
                  ),
                ),
              ),
              // 「好的」固定在弹窗底部，不随内容滚动
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: _pill(
                  '好的',
                  bg: kPrimary.withValues(alpha: 0.92),
                  textColor: Colors.white,
                  onTap: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 版本号下方的检查更新区域，随检查阶段变化。
  Widget _updateArea() {
    switch (_phase) {
      case 'checking':
        return const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: kPrimary,
              ),
            ),
            SizedBox(width: 10),
            Text('正在检查更新…', style: TextStyle(fontSize: 12.5, color: kTextMain)),
          ],
        );
      case 'fail':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '检查失败：无法连接 GitHub（可能被网络拦截或不稳定）',
              style: TextStyle(fontSize: 12.5, height: 1.5, color: kTextMuted),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill(
                  _copied ? '已复制，请到浏览器打开' : '复制在线链接',
                  bg: Colors.white.withValues(alpha: 0.55),
                  textColor: kTextMain,
                  onTap: _copyLink,
                ),
                _pill(
                  '重试',
                  bg: kPrimary.withValues(alpha: 0.92),
                  textColor: Colors.white,
                  onTap: _check,
                ),
              ],
            ),
          ],
        );
      case 'latest':
        return Row(
          children: [
            const Expanded(
              child: Text(
                '已是最新版本。',
                style: TextStyle(fontSize: 12.5, color: kTextMuted),
              ),
            ),
            _pill(
              '重新检查',
              bg: Colors.white.withValues(alpha: 0.55),
              textColor: kTextMain,
              onTap: _check,
            ),
          ],
        );
      case 'newer':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AboutLine(text: '发现新版本 ', bold: _tag),
            if (_body.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kPrimary.withValues(alpha: 0.2)),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: SingleChildScrollView(
                    child: Text(
                      _body,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.55,
                        color: kTextMain,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_apkUrl.isNotEmpty)
                  _pill(
                    '应用内下载',
                    bg: kPrimary.withValues(alpha: 0.92),
                    textColor: Colors.white,
                    onTap: _startDownload,
                  )
                else
                  _pill(
                    '前往下载',
                    bg: kPrimary.withValues(alpha: 0.92),
                    textColor: Colors.white,
                    onTap: () {
                      if (_htmlUrl.isNotEmpty) {
                        launchUrl(
                          Uri.parse(_htmlUrl),
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                  ),
                _pill(
                  _copied ? '已复制，请到浏览器打开' : '复制在线链接',
                  bg: Colors.white.withValues(alpha: 0.55),
                  textColor: kTextMain,
                  onTap: _copyLink,
                ),
              ],
            ),
          ],
        );
      case 'downloading':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '正在下载更新包…',
                    style: TextStyle(fontSize: 12.5, color: kTextMain),
                  ),
                ),
                Text(
                  '${(_progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: kPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.55),
                valueColor: const AlwaysStoppedAnimation(kPrimary),
              ),
            ),
            const SizedBox(height: 10),
            _pill(
              '取消下载',
              bg: Colors.white.withValues(alpha: 0.55),
              textColor: kTextMain,
              onTap: _cancelDownload,
            ),
          ],
        );
      case 'ready':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '下载完成，可开始安装。',
              style: TextStyle(fontSize: 12.5, color: kTextMain),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill(
                  '安装',
                  bg: kPrimary.withValues(alpha: 0.92),
                  textColor: Colors.white,
                  onTap: _install,
                ),
                _pill(
                  _copied ? '已复制，请到浏览器打开' : '复制在线链接',
                  bg: Colors.white.withValues(alpha: 0.55),
                  textColor: kTextMain,
                  onTap: _copyLink,
                ),
              ],
            ),
          ],
        );
      case 'dlfail':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '下载失败，网络可能不稳定，请稍后重试。',
              style: TextStyle(fontSize: 12.5, color: kTextMain),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill(
                  '重试',
                  bg: kPrimary.withValues(alpha: 0.92),
                  textColor: Colors.white,
                  onTap: _startDownload,
                ),
                _pill(
                  _copied ? '已复制，请到浏览器打开' : '复制在线链接',
                  bg: Colors.white.withValues(alpha: 0.55),
                  textColor: kTextMain,
                  onTap: _copyLink,
                ),
              ],
            ),
          ],
        );
      default: // idle
        return SizedBox(
          width: double.infinity,
          child: _pill(
            '检查更新',
            bg: Colors.white.withValues(alpha: 0.55),
            textColor: kTextMain,
            onTap: _check,
          ),
        );
    }
  }

  /// 弹窗内的小型胶囊按钮（与 _GlassDialog 的按钮同款视觉）。
  Widget _pill(
    String label, {
    required Color bg,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: kSpring,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

/// 统一的玻璃拟态弹窗：透明 Dialog + GlassCard 面板，替代系统 AlertDialog。
/// [cancelText] 为空时只显示一个确认按钮（铺满整行）；否则「取消 + 确认」并排。
/// [destructive] = 确认按钮用柔和红（退出登录等危险操作）。
/// 点确认 → `Navigator.pop(context, [popResult])`，由 showDialog 的返回值接住。
class _GlassDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final String confirmText;
  final String? cancelText;
  final bool destructive;
  final Object? popResult;
  const _GlassDialog({
    required this.title,
    required this.content,
    required this.confirmText,
    this.cancelText,
    this.destructive = false,
    this.popResult,
  });

  @override
  Widget build(BuildContext context) {
    final tone = destructive ? const Color(0xFFB85450) : kPrimary;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: GlassCard(
        radius: 22,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: kInk,
              ),
            ),
            const SizedBox(height: 8),
            content,
            const SizedBox(height: 16),
            if (cancelText == null)
              _pill(
                context,
                confirmText,
                Colors.white,
                bg: tone.withValues(alpha: 0.92),
                onTap: () => Navigator.pop(context, popResult),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _pill(
                      context,
                      cancelText!,
                      kTextMain,
                      bg: Colors.white.withValues(alpha: 0.5),
                      // 取消：只关弹窗，返回 null
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _pill(
                      context,
                      confirmText,
                      Colors.white,
                      bg: tone.withValues(alpha: 0.92),
                      onTap: () => Navigator.pop(context, popResult),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _pill(
    BuildContext context,
    String label,
    Color textColor, {
    required Color bg,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: kSpring,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

/// Tab 切换时的淡入 + 轻微缩放过渡。
/// 只有「从非激活变为激活」的那一页会播放动画（forward from 0）；
/// 首次进入时激活的首屏直接显示（控制器初值 1），不做多余动画。
class _TabFade extends StatefulWidget {
  final bool active;
  final Widget child;
  const _TabFade({required this.active, required this.child});

  @override
  State<_TabFade> createState() => _TabFadeState();
}

class _TabFadeState extends State<_TabFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: widget.active ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _TabFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: kSpring);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
        child: widget.child,
      ),
    );
  }
}

/// 用户胶囊弹出的底部菜单：浮起玻璃卡 + 菜单项卡片（与下拉面板选项同款视觉）。
class _UserMenuSheet extends StatelessWidget {
  final VoidCallback onLogout;
  const _UserMenuSheet({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: GlassCard(
          radius: 22,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuTile(
                icon: Icons.logout_rounded,
                label: '退出学习服务',
                destructive: true,
                onTap: () {
                  Navigator.pop(context);
                  onLogout();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部菜单的单个选项：圆角大、可点区域铺满整行，与 GlassDropdown 选项同款。
class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// 危险操作（退出登录）：图标与文字用柔和红。
  final bool destructive;
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final tone = destructive ? const Color(0xFFB85450) : kPrimary;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: kSpring,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              // 图标坐在同色系浅色圆片上，与全局徽章视觉一致
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 15, color: tone),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: destructive ? tone : kTextMain,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 17,
                color: kTextMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
