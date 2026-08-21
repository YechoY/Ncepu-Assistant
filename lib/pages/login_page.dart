import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_state.dart';
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
  bool autoLogin = false;
  bool submitting = false;

  Future<void> _submit() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入学号和密码')));
      return;
    }
    setState(() => submitting = true);
    final ok = await ref
        .read(authStateProvider.notifier)
        .login(_user.text.trim(), _pass.text, remember: remember, autoLogin: autoLogin);
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
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE8F1FF), Color(0xFFF7F9FD)],
          ),
        ),
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
                  gradient: const LinearGradient(colors: [Color(0xFF7DB4FF), kPrimaryDark]),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.local_florist, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 12),
              const Text(
                '华电教务助手',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1E3A8A)),
              ),
              const SizedBox(height: 4),
              const Text(
                '请使用教务系统账号登录',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 26),
              _field(_user, '学号', obscure: false),
              const SizedBox(height: 12),
              _field(_pass, '密码', obscure: true),
              const SizedBox(height: 16),
              Row(
                children: [
                  _check('记住账号密码', remember, (v) => setState(() => remember = v)),
                  const SizedBox(width: 18),
                  _check('自动登录', autoLogin && remember, (v) {
                    if (!remember) return;
                    setState(() => autoLogin = v);
                  }),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: kPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  submitting ? '登录中…' : '登 录',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
    );
  }

  Widget _field(TextEditingController c, String hint, {required bool obscure}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5E9F0)),
        ),
        child: TextField(
          controller: c,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: hint,
            border: InputBorder.none,
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9AA3AD)),
          ),
        ),
      );

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) => GestureDetector(
        onTap: () => onChanged(!value),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 15,
              height: 15,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: value ? kPrimary : Colors.white,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: value ? kPrimary : const Color(0xFFCBD5E1)),
              ),
              child: value ? const Icon(Icons.check, size: 11, color: Colors.white) : null,
            ),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF374151))),
          ],
        ),
      );
}
