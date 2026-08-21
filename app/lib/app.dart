import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pages/classrooms_page.dart';
import 'pages/exams_page.dart';
import 'pages/grades_page.dart';
import 'pages/login_page.dart';
import 'pages/timetable_page.dart';
import 'providers/app_state.dart';
import 'providers/auth_state.dart';
import 'providers/data_state.dart';
import 'theme.dart';
import 'widgets/capsule_nav.dart';
import 'widgets/offline_banner.dart';
import 'widgets/top_bar.dart';

class HdjwApp extends StatelessWidget {
  const HdjwApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '华电教务助手',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const _Gate(),
      );
}

class _Gate extends ConsumerStatefulWidget {
  const _Gate();
  @override
  ConsumerState<_Gate> createState() => _GateState();
}

enum _Phase { boot, login, main }

class _GateState extends ConsumerState<_Gate> {
  _Phase phase = _Phase.boot;
  bool offline = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final online = await ref.read(onlineProvider.future).catchError((_) => false);
    final auth = ref.read(authStateProvider.notifier);
    if (online) {
      final ok = await auth.tryAutoLogin();
      if (ok) {
        await ref.read(dataStateProvider.notifier).dailyRefreshIfNeeded();
        if (mounted) setState(() => phase = _Phase.main);
      } else {
        if (mounted) setState(() => phase = _Phase.login);
      }
    } else {
      await ref.read(dataStateProvider.notifier).loadFromCache();
      final state = ref.read(dataStateProvider);
      final hasCache = state.timetable.isNotEmpty ||
          state.grades.isNotEmpty ||
          state.exams.isNotEmpty;
      if (hasCache) {
        if (mounted) {
          setState(() {
            phase = _Phase.main;
            offline = true;
          });
        }
      } else {
        if (mounted) setState(() => phase = _Phase.login);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (phase) {
      _Phase.boot => const Scaffold(body: Center(child: CircularProgressIndicator())),
      _Phase.login => const LoginPage(),
      _Phase.main => _MainShell(offline: offline),
    };
  }
}

class _MainShell extends ConsumerStatefulWidget {
  final bool offline;
  const _MainShell({required this.offline});
  @override
  ConsumerState<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<_MainShell> {
  int tab = 0;

  static const titles = ['我的课表', '课程成绩', '考试安排', '空闲教室'];

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('退出登录', style: TextStyle(fontSize: 16)),
        content: const Text('退出将清除全部本地数据（缓存、账号密码），确定吗？', style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authStateProvider.notifier).logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (_) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const TimetablePage(),
      const GradesPage(),
      const ExamsPage(),
      const ClassroomsPage(),
    ];
    final user = ref.watch(authStateProvider);
    final state = ref.watch(dataStateProvider);
    final userLabel = user.name.isNotEmpty
        ? '${user.name} · ${user.className}'
        : user.username.isNotEmpty
            ? user.username
            : '未登录';
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(
              title: titles[tab],
              showRefresh: tab != 3,
              onRefresh: switch (tab) {
                0 => () {
                    final week = ref.read(dataStateProvider).timetableWeek;
                    if (week.isNotEmpty) {
                      ref.read(dataStateProvider.notifier).loadTimetable(week);
                    }
                  },
                1 => () => ref.read(dataStateProvider.notifier).refreshGrades(),
                _ => () => ref.read(dataStateProvider.notifier).refreshExams(),
              },
              userName: userLabel,
              onUserTap: () => showModalBottomSheet(
                context: context,
                builder: (_) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        title: const Text('关于', style: TextStyle(fontSize: 14)),
                        onTap: () {
                          Navigator.pop(context);
                          _about();
                        },
                      ),
                      ListTile(
                        title: const Text(
                          '退出登录',
                          style: TextStyle(fontSize: 14, color: Colors.red),
                        ),
                        onTap: _logout,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.offline) const OfflineBanner(),
            if (state.notice != null) OfflineBanner(text: state.notice!),
            Expanded(child: IndexedStack(index: tab, children: pages)),
            CapsuleNav(index: tab, onTap: (i) => setState(() => tab = i)),
          ],
        ),
      ),
    );
  }

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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('好的')),
        ],
      ),
    );
  }
}
