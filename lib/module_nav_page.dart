// module_nav_page.dart —— 模块导航页（新根路由）。
//
// 设计：两张大 GlassCard 各占一行（学习服务 / 生活服务），底部免责声明卡 +
// 勾选框（首次使用必须勾上），右上角关于/检查更新入口，右下角版本号。
// 未勾免责 → 卡片置灰不可点 + 玻璃提示。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/debug_log.dart';
import 'core/debug_log_page.dart';

import 'package:huish/huish.dart';
import 'package:laundry/laundry.dart';

import 'study/providers/auth_state.dart';
import 'study/providers/data_state.dart';

import 'package:glass_ui/theme.dart';
import 'package:glass_ui/widgets/glass_background.dart';
import 'package:glass_ui/widgets/glass_card.dart';
import 'package:glass_ui/widgets/glass_loading.dart';
import 'package:glass_ui/widgets/glass_snackbar.dart';

import 'study/pages/login_page.dart';

class ModuleNavPage extends ConsumerStatefulWidget {
  const ModuleNavPage({super.key});
  @override
  ConsumerState<ModuleNavPage> createState() => _ModuleNavPageState();
}

class _ModuleNavPageState extends ConsumerState<ModuleNavPage> {
  bool _agreed = false;
  bool _loading = true;
  String _version = '';
  // 免责卡展开状态：未同意时默认展开（先读再勾选），同意后默认收起
  bool _disclaimerExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadAgreement();
    _loadVersion();
    _autoCheckUpdate();
  }

  Future<void> _loadAgreement() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _agreed = sp.getBool('nav_disclaimer_agreed') ?? false;
        _disclaimerExpanded = !_agreed;
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

  /// 启动时静默检查更新（开关在「关于」弹窗里，默认开）。
  /// 有新版只弹一条提示，不主动弹窗打扰。
  Future<void> _autoCheckUpdate() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!(sp.getBool('auto_check_update') ?? true)) return;
      final r = await checkLatestRelease();
      if (!mounted || r == null || !r.newer) return;
      showGlassSnackBar(context, '发现新版本 ${r.tag}，点右上角「关于」更新');
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
    // 已登录 → 先加载缓存数据再进 MainShell；未登录 → 先登录
    final authState = ref.read(authStateProvider);
    if (authState.loggedIn) {
      await ref.read(dataStateProvider.notifier).loadFromCache();
      if (!mounted) return;
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

  Future<void> _tapLaundry() async {
    if (!_agreed) {
      showGlassSnackBar(context, '请先阅读并同意免责声明');
      return;
    }
    // 凭证恢复是异步的，等完成后再判断登录态
    await ref.read(laundryAuthProvider.notifier).ensureRestored();
    if (!mounted) return;
    final laundry = ref.read(laundryAuthProvider);
    if (laundry.loggedIn) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const LaundryHomePage()));
    } else {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const LaundryLoginPage()));
    }
  }

  void _showAbout() {
    showDialog(
      context: context,
      barrierColor: const Color(0x402E3350),
      builder: (_) => const AppAboutDialog(),
    );
  }

  Widget _disclaimerItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: kPrimary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: kTextMain.withValues(alpha: 0.82),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: GlassBackground(child: Center(child: GlassLoading())),
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
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '掌上华电',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
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
                      title: '饮水服务',
                      subtitle: '惠生活798 · 取水 · 消费记录',
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [kHuish, kHuishDeep],
                      ),
                      enabled: _agreed,
                      onTap: _tapLife,
                    ),
                    const SizedBox(height: 14),
                    _ServiceCard(
                      icon: Icons.local_laundry_service_rounded,
                      title: '洗衣服务',
                      subtitle: 'U净 · 扫码洗衣 · 订单跟踪',
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [kLaundry, kLaundryDeep],
                      ),
                      enabled: _agreed,
                      onTap: _tapLaundry,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              // 中部工具行：左侧引导文字 + 右侧开发者工具组（单行防溢出）
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Text(
                      '选择服务进入',
                      style: TextStyle(
                        fontSize: 14,
                        color: kTextMuted.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    _DebugSwitch(
                      active: AppDebugLog.instance.isEnabled,
                      onChanged: (v) {
                        AppDebugLog.instance.setEnabled(v).then((_) {
                          if (mounted) setState(() {});
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    _DebugPill(
                      icon: Icons.terminal,
                      label: '日志',
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const DebugLogPage(),
                          ),
                        );
                        // 日志页里可能切换了开关 → 返回后同步外层状态
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
              ),
              // 弹性区：免责卡始终贴底；高屏留白在上，矮屏压缩声明正文
              Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: GlassCard(
                      radius: 18,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(
                              () => _disclaimerExpanded = !_disclaimerExpanded,
                            ),
                            child: Row(
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
                                const SizedBox(width: 2),
                                AnimatedRotation(
                                  turns: _disclaimerExpanded ? 0.5 : 0,
                                  duration: const Duration(milliseconds: 250),
                                  curve: kSpring,
                                  child: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 16,
                                    color: kTextMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 声明正文：可展开/收起；全文上限高 170，超出滚动
                          Flexible(
                            child: AnimatedCrossFade(
                              firstChild: const SizedBox(
                                width: double.infinity,
                              ),
                              secondChild: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxHeight: 170,
                                  ),
                                  child: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _disclaimerItem(
                                          '本应用为非官方应用，由学生个人开发，仅供学习交流使用，'
                                          '与华北电力大学（保定）官方无任何隶属、合作或授权关系。',
                                        ),
                                        _disclaimerItem(
                                          '教务数据来源于华电教务系统官网，饮水服务数据来源于惠生活798'
                                          '第三方接口，洗衣服务数据来源于U净（Ujing）第三方接口；'
                                          '相关数据的版权归原平台及权利方所有，接口可用性不作担保。',
                                        ),
                                        _disclaimerItem(
                                          '账号、密码、登录凭证等数据仅加密保存在本机，'
                                          '不上传、不同步至任何第三方服务器。',
                                        ),
                                        _disclaimerItem(
                                          '洗衣下单产生的费用通过支付宝直接支付给服务提供商，'
                                          '开发者不经手、不托管任何资金，支付前请确认订单信息。',
                                        ),
                                        _disclaimerItem(
                                          '本应用不使用学校及第三方平台的官方标识，'
                                          '若涉及侵权请及时联系更正或删除。',
                                        ),
                                        _disclaimerItem(
                                          '本应用按「现状」提供，开发者不作任何明示或默示的担保；'
                                          '因使用本应用产生的一切后果由使用者自行承担。',
                                        ),
                                        _disclaimerItem(
                                          '本应用不用于任何商业用途；如学校或相关权利方提出要求，'
                                          '开发者将及时停止相关功能。',
                                        ),
                                        _disclaimerItem(
                                          '在法律允许的范围内，开发者保留对本声明的最终解释权；'
                                          '如与法律法规相冲突，以法律法规为准。',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              crossFadeState: _disclaimerExpanded
                                  ? CrossFadeState.showSecond
                                  : CrossFadeState.showFirst,
                              duration: const Duration(milliseconds: 280),
                              sizeCurve: kSpring,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _AgreeRow(agreed: _agreed, onToggle: _toggleAgreed),
                        ],
                      ),
                    ),
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

/// debug 滑动开关（与日志页同步，都读写 AppDebugLog.instance）
class _DebugSwitch extends StatelessWidget {
  final bool active;
  final ValueChanged<bool> onChanged;
  const _DebugSwitch({required this.active, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!active),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52,
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        alignment: active ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: active
              ? kTextMain.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.5),
          border: Border.all(
            color: active
                ? kTextMain.withValues(alpha: 0.45)
                : kPrimarySoft.withValues(alpha: 0.3),
          ),
        ),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? kTextMain : kTextMuted,
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.bug_report_rounded,
            size: 14,
            color: active ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }
}

/// 调试胶囊按钮（查看日志入口）
class _DebugPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _DebugPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white.withValues(alpha: 0.5),
          border: Border.all(color: kPrimarySoft.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: kTextMuted),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: kTextMuted,
              ),
            ),
          ],
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
