import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_state.dart';
import '../widgets/glass_background.dart';
import '../widgets/glass_card.dart';
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

  @override
  void initState() {
    super.initState();
    _prefillIfRemembered();
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
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入学号和密码')));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
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
                            '记住账号密码',
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
                        '产生的一切后果由使用者自行承担。',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.55,
                          color: kTextMain,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
