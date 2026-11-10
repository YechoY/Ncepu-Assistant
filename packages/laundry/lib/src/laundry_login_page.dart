// laundry/laundry_login_page.dart —— 洗衣服务登录页（玻璃 UI）。
// U净平台：手机号 + 短信验证码两步（无图形验证码，AFS 人机验证以固定参数绕过）。
// 登录成功凭证自动持久化（secure storage），下次进入免重登。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:glass_ui/theme.dart';
import 'package:glass_ui/widgets/glass_background.dart';
import 'package:glass_ui/widgets/glass_card.dart';
import 'package:glass_ui/widgets/glass_loading.dart';
import 'package:glass_ui/widgets/glass_snackbar.dart';
import 'laundry_auth_state.dart';
import 'laundry_home_page.dart';

class LaundryLoginPage extends ConsumerStatefulWidget {
  const LaundryLoginPage({super.key});
  @override
  ConsumerState<LaundryLoginPage> createState() => _LaundryLoginPageState();
}

class _LaundryLoginPageState extends ConsumerState<LaundryLoginPage> {
  final _phone = TextEditingController();
  final _code = TextEditingController();

  bool _sending = false;
  bool _submitting = false;
  int _countdown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phone.text.trim();
    if (phone.length != 11) {
      showGlassSnackBar(context, '请输入 11 位手机号');
      return;
    }
    setState(() => _sending = true);
    try {
      await ref.read(laundryApiProvider).requestCaptcha(phone);
      if (!mounted) return;
      showGlassSnackBar(context, '验证码已发送');
      _startCountdown();
    } catch (e) {
      if (mounted) showGlassSnackBar(context, '发送失败: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startCountdown() {
    setState(() => _countdown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _countdown = _countdown - 1);
      if (_countdown <= 0) t.cancel();
    });
  }

  Future<void> _submit() async {
    final phone = _phone.text.trim();
    final code = _code.text.trim();
    if (phone.length != 11) {
      showGlassSnackBar(context, '请输入 11 位手机号');
      return;
    }
    if (code.isEmpty) {
      showGlassSnackBar(context, '请输入短信验证码');
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(laundryAuthProvider.notifier).login(phone, code);
      if (!mounted) return;
      showGlassSnackBar(context, '登录成功');
      // 替换路由：登录后不再保留登录页
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LaundryHomePage()),
      );
    } catch (e) {
      if (mounted) showGlassSnackBar(context, '登录失败: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 返回按钮（全局玻璃样式，图标用洗衣模块深粉）
                  Align(
                    alignment: Alignment.centerLeft,
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
                          color: kLaundryDeep,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // 标题卡
                  GlassCard(
                    radius: 22,
                    padding: const EdgeInsets.symmetric(
                        vertical: 22, horizontal: 18),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: kLaundry,
                                boxShadow: [
                                  BoxShadow(
                                    color: kGlassShadow,
                                    blurRadius: 14,
                                    offset: Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.local_laundry_service_rounded,
                                size: 25,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              '洗衣服务',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: kInk,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'U净平台 · 手机验证码登录',
                          style: TextStyle(
                            fontSize: 12,
                            color: kTextMuted.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // 输入卡
                  GlassCard(
                    radius: 22,
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('手机号'),
                        _glassField(
                          controller: _phone,
                          hint: '请输入手机号',
                          keyboardType: TextInputType.phone,
                          maxLength: 11,
                        ),
                        const SizedBox(height: 12),
                        _fieldLabel('短信验证码'),
                        Row(
                          children: [
                            Expanded(
                              child: _glassField(
                                controller: _code,
                                hint: '验证码',
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _sendCodeButton(),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  // 登录按钮
                  _loginButton(),
                ],
              ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: kTextMuted,
      ),
    ),
  );

  Widget _glassField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    int? maxLength,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.55),
        border: Border.all(color: kGlassBorder),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLength: maxLength,
        style: const TextStyle(fontSize: 14.5, color: kTextMain),
        decoration: InputDecoration(
          border: InputBorder.none,
          counterText: '',
          hintText: hint,
          hintStyle: TextStyle(
            fontSize: 13.5,
            color: kTextMuted.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }

  Widget _sendCodeButton() {
    final disabled = _sending || _countdown > 0;
    return GestureDetector(
      onTap: disabled ? null : _sendCode,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: disabled
              ? kTextMuted.withValues(alpha: 0.15)
              : kLaundryDeep.withValues(alpha: 0.9),
        ),
        child: Text(
          _countdown > 0 ? '$_countdown s' : (_sending ? '发送中' : '发验证码'),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: disabled ? kTextMuted : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _loginButton() {
    return GestureDetector(
      onTap: _submitting ? null : _submit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kLaundry, kLaundryDeep],
          ),
          boxShadow: [
            BoxShadow(
              color: kLaundryDeep.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: _submitting
            ? const GlassLoading(size: 20, color: Colors.white)
            : const Text(
                '登录',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 4,
                ),
              ),
      ),
    );
  }
}
