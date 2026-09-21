// module_nav_page.dart —— 模块导航页（新根路由）。
//
// 设计：两张大 GlassCard 各占一行（学习服务 / 生活服务），底部免责声明卡 +
// 勾选框（首次使用必须勾上），右上角关于/检查更新入口，右下角版本号。
// 未勾免责 → 卡片置灰不可点 + 玻璃提示。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app.dart';
import '../huish/huish_auth_state.dart';
import '../providers/auth_state.dart';
import '../providers/data_state.dart';
import '../theme.dart';
import '../widgets/glass_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/glass_snackbar.dart';
import '../huish/huish_home_page.dart';
import '../huish/huish_login_page.dart';
import 'login_page.dart';

class ModuleNavPage extends ConsumerStatefulWidget {
  const ModuleNavPage({super.key});
  @override
  ConsumerState<ModuleNavPage> createState() => _ModuleNavPageState();
}

class _ModuleNavPageState extends ConsumerState<ModuleNavPage> {
  bool _agreed = false;
  bool _loading = true;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadAgreement();
    _loadVersion();
  }

  Future<void> _loadAgreement() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _agreed = sp.getBool('nav_disclaimer_agreed') ?? false;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {}
  }

  Future<void> _toggleAgreed(bool v) async {
    setState(() => _agreed = v);
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('nav_disclaimer_agreed', v);
    } catch (_) {}
  }

  void _tapStudy() async {
    if (!_agreed) {
      showGlassSnackBar(context, '请先阅读并同意免责声明');
      return;
    }
    // 已登录 → 直接进 MainShell；未登录 → 先登录
    final authState = ref.read(authStateProvider);
    if (authState.loggedIn) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const MainShell()));
    } else {
      // 记住账号 → 预填 + 后台静默登录后自动进 MainShell
      final authSvc = ref.read(authServiceProvider);
      final remembered = await authSvc.getRemember().catchError((_) => false);
      final data = ref.read(dataStateProvider.notifier);
      if (remembered) {
        await data.loadFromCache();
        ref.read(authStateProvider.notifier).tryAutoLogin().then((ok) {
          if (ok && mounted) {
            ref.read(dataStateProvider.notifier).dailyRefreshIfNeeded();
          }
        });
        if (!mounted) return;
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const MainShell()));
      } else {
        if (!mounted) return;
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const LoginPage()));
      }
    }
  }

  Future<void> _tapLife() async {
    if (!_agreed) {
      showGlassSnackBar(context, '请先阅读并同意免责声明');
      return;
    }
    // token 恢复是异步的，必须等它完成后再判断登录态
    final notifier = ref.read(huishAuthStateProvider.notifier);
    await notifier.ensureRestored();
    if (!mounted) return;
    final huish = ref.read(huishAuthStateProvider);
    if (huish.loggedIn) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const HuishHomePage()));
    } else {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const HuishLoginPage()));
    }
  }

  void _showAbout() {
    showDialog(
      context: context,
      barrierColor: const Color(0x402E3350),
      builder: (_) => const AppAboutDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: GlassBackground(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: Column(
            children: [
              // 顶栏：标题 + 关于入口
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 20, 8),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [kPrimarySoft, kPrimary],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: kPrimary.withValues(alpha: 0.3),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.local_florist,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '掌上华电',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: kInk,
                              height: 1.2,
                            ),
                          ),
                          Text(
                            '华北电力大学 · 保定',
                            style: TextStyle(
                              fontSize: 12,
                              color: kTextMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _showAbout,
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
                          Icons.info_outline_rounded,
                          size: 20,
                          color: kPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // 两张服务卡：各占一行
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _ServiceCard(
                      icon: Icons.menu_book_rounded,
                      title: '学习服务',
                      subtitle: '课表 · 成绩 · 考试 · 教室',
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF6E77B5), Color(0xFF454C84)],
                      ),
                      enabled: _agreed,
                      onTap: _tapStudy,
                    ),
                    const SizedBox(height: 14),
                    _ServiceCard(
                      icon: Icons.water_drop_rounded,
                      title: '生活服务',
                      subtitle: '惠生活798 · 饮水',
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF4BA3C7), Color(0xFF2E6B8C)],
                      ),
                      enabled: _agreed,
                      onTap: _tapLife,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // 免责声明 + 勾选框
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: GlassCard(
                  radius: 18,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            size: 15,
                            color: kPrimary,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            '免责声明',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: kInk,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'v$_version',
                            style: const TextStyle(
                              fontSize: 11,
                              color: kTextMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '① 本应用为非官方应用，由学生个人以 vibecoding 方式独立开发，'
                        '仅供学习交流使用，与华北电力大学（保定）官方无任何隶属、合作或授权关系。\n'
                        '② 所有教务数据均来源于华电教务系统官网，相关数据的版权归原网站及权利方所有。\n'
                        '③ 账号、密码等数据仅保存在本机，不上传至任何第三方服务器。\n'
                        '④ 本应用不使用学校官方标识，若涉及侵权请及时联系更正或删除。\n'
                        '⑤ 本应用按「现状」提供，开发者不作任何担保；使用产生的一切后果由使用者自行承担。\n'
                        '⑥ 在法律允许的范围内，开发者保留对本协议的最终解释权。\n'
                        '⑦ 饮水服务数据来自 i.ilife798.com 第三方接口，与惠生活798无隶属或授权关系，接口可用性不做担保。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: kTextMain.withValues(alpha: 0.88),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _AgreeRow(agreed: _agreed, onToggle: _toggleAgreed),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Gradient gradient;
  final bool enabled;
  final VoidCallback onTap;
  const _ServiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: kSpring,
        width: double.infinity,
        height: 108,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: gradient.colors.first.withValues(
                alpha: enabled ? 0.25 : 0.08,
              ),
              blurRadius: enabled ? 20 : 8,
              offset: const Offset(0, 8),
            ),
          ],
          gradient: enabled
              ? gradient
              : LinearGradient(
                  colors: [Colors.grey.shade300, Colors.grey.shade400],
                ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 28,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgreeRow extends StatelessWidget {
  final bool agreed;
  final ValueChanged<bool> onToggle;
  const _AgreeRow({required this.agreed, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onToggle(!agreed),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: kSpring,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: kPrimary.withValues(alpha: agreed ? 0.14 : 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: kPrimary.withValues(alpha: agreed ? 0.55 : 0.28),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: kSpring,
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: agreed ? kPrimary : Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: agreed ? kPrimary : kPrimary.withValues(alpha: 0.45),
                  width: 1.4,
                ),
              ),
              child: agreed
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '我已阅读并同意上述免责声明',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: agreed ? kPrimary : kInk,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
