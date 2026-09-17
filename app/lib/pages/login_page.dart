import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_state.dart';
import '../widgets/glass_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/glass_snackbar.dart';
import '../theme.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool remember = false;
  bool submitting = false;
  bool _showPass = false;
  bool _agreed = false;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _prefillIfRemembered();
    _loadAgreement();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 读取本地「已同意免责声明」记录：同意过则默认勾上，之后不再打扰。
  Future<void> _loadAgreement() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _agreed = sp.getBool('disclaimer_agreed') ?? false);
    } catch (_) {}
  }

  /// 勾选/取消均立即持久化：取消后下次启动需重新勾选才能登录。
  Future<void> _toggleAgreed(bool v) async {
    setState(() => _agreed = v);
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('disclaimer_agreed', v);
    } catch (_) {}
  }

  Future<void> _prefillIfRemembered() async {
    try {
      final auth = ref.read(authServiceProvider);
      final remembered = await auth.getRemember();
      final acc = await auth.loadAccount();
      if (!mounted) return;
      setState(() {
        remember = remembered;
        // 记住状态才预填账号密码
        if (remembered && acc != null) {
          _user.text = acc.username;
          _pass.text = acc.password;
        }
      });
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (!_agreed) {
      showGlassSnackBar(context, '请先阅读并同意免责声明');
      // 免责声明勾选框在页面最底部，未勾选时滚过去引导用户查看
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 420),
          curve: kSpring,
        );
      }
      return;
    }
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      showGlassSnackBar(context, '请输入学号和密码');
      return;
    }
    setState(() => submitting = true);
    final ok = await ref
        .read(authStateProvider.notifier)
        .login(_user.text.trim(), _pass.text, remember: remember);
    if (!mounted) return;
    setState(() => submitting = false);
    final err = ref.read(authStateProvider).error;
    if (!ok && err != null) {
      showGlassSnackBar(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            controller: _scroll,
            // 底部留白 96：滚到底后勾选行高于浮动 SnackBar（约 72px），不被遮住
            padding: const EdgeInsets.fromLTRB(20, 48, 20, 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 30),
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [kPrimarySoft, kPrimary],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: kPrimary.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.local_florist,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '掌上华电',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: kInk,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '请使用教务系统账号登录',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: kTextMuted),
                ),
                const SizedBox(height: 26),
                GlassCard(
                  radius: 24,
                  padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
                  child: Column(
                    children: [
                      _field(_user, '学号', obscure: false),
                      const SizedBox(height: 14),
                      _field(
                        _pass,
                        '密码',
                        obscure: !_showPass,
                        onToggleVisible: () {
                          setState(() => _showPass = !_showPass);
                        },
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          _check(
                            '记住账号密码（可选）',
                            remember,
                            (v) => setState(() => remember = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _loginButton(),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '需连接校园网或 VPN',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: kTextMuted,
                  ),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  radius: 18,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Row(
                        children: [
                          Icon(Icons.info_outline, size: 15, color: kPrimary),
                          SizedBox(width: 6),
                          Text(
                            '免责声明',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: kInk,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        '① 本应用为非官方应用，由学生个人以 vibecoding 方式'
                        '独立开发，仅供学习交流使用，与华北电力大学（保定）官方无任何'
                        '隶属、合作或授权关系，官方不对本应用承担任何责任。\n'
                        '② 所有教务数据均来源于华电教务系统官网，相关数据的'
                        '版权归原网站及权利方所有；本应用仅作个人查询展示，'
                        '不用于任何商业用途。\n'
                        '③ 账号、密码等数据仅保存在本机本地存储，不上传、不同步'
                        '至任何第三方服务器，开发者无法获取；请妥善保管自己的'
                        '学号与密码。\n'
                        '④ 本应用不使用学校官方标识，若应用名称或内容涉及侵权，'
                        '请及时联系开发者，将第一时间更正或删除。\n'
                        '⑤ 本应用按「现状」提供，开发者不作任何担保；使用本应用'
                        '产生的一切后果由使用者自行承担。\n'
                        '⑥ 在法律允许的范围内，本软件开发者保留对本协议相关条款'
                        '的最终解释权；如本声明与法律法规相冲突，以法律法规为准。',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.55,
                          color: kTextMain,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _agreeRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 免责声明勾选行：置于声明卡下方，紫底描边胶囊样式，醒目且整行可点。
  Widget _agreeRow() {
    return GestureDetector(
      onTap: () => _toggleAgreed(!_agreed),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: kSpring,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: kPrimary.withValues(alpha: _agreed ? 0.14 : 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: kPrimary.withValues(alpha: _agreed ? 0.55 : 0.28),
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
                color: _agreed
                    ? kPrimary
                    : Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: _agreed ? kPrimary : kPrimary.withValues(alpha: 0.45),
                  width: 1.4,
                ),
              ),
              child: _agreed
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '我已阅读并同意上述免责声明',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _agreed ? kPrimary : kInk,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loginButton() {
    return FilledButton(
      onPressed: submitting ? null : _submit,
      style: FilledButton.styleFrom(
        backgroundColor: kPrimary,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        elevation: 6,
        shadowColor: kPrimary.withValues(alpha: 0.4),
      ),
      child: Text(
        submitting ? '登录中…' : '登 录',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String hint, {
    required bool obscure,
    VoidCallback? onToggleVisible,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
    ),
    child: TextField(
      controller: c,
      obscureText: obscure,
      decoration: InputDecoration(
        hintText: hint,
        border: InputBorder.none,
        hintStyle: const TextStyle(fontSize: 13, color: kTextMuted),
        suffixIcon: onToggleVisible == null
            ? null
            : IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: kTextMuted,
                ),
                onPressed: onToggleVisible,
              ),
      ),
    ),
  );

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) =>
      GestureDetector(
        onTap: () => onChanged(!value),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 19,
              height: 19,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: value ? kPrimary : Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: value ? kPrimary : const Color(0xFFCBD5E1),
                ),
              ),
              child: value
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: kTextMain,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
}
