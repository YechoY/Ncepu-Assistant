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
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
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
                      colors: [Color(0xFF7DB4FF), kPrimaryDark],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: kPrimary.withValues(alpha: 0.3),
                        blurRadius: 18,
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
                  '华电教务助手',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '请使用教务系统账号登录',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 26),
                GlassCard(
                  radius: 20,
                  opacity: 0.18,
                  padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
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
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _check(
                            '记住账号密码',
                            remember,
                            (v) => setState(() => remember = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _loginButton(),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '需连接校园网或 VPN',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
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
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 6,
        shadowColor: kPrimary.withValues(alpha: 0.4),
      ),
      child: Text(
        submitting ? '登录中…' : '登 录',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
      color: Colors.white.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
    ),
    child: TextField(
      controller: c,
      obscureText: obscure,
      decoration: InputDecoration(
        hintText: hint,
        border: InputBorder.none,
        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9AA3AD)),
        suffixIcon: onToggleVisible == null
            ? null
            : IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: const Color(0xFF9AA3AD),
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
              width: 15,
              height: 15,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: value ? kPrimary : Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: value ? kPrimary : const Color(0xFFCBD5E1),
                ),
              ),
              child: value
                  ? const Icon(Icons.check, size: 11, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF374151)),
            ),
          ],
        ),
      );
}
