// huish/huish_login_page.dart —— 饮水服务登录页（玻璃 UI）。
//
// 手机号 + 图形验证码 + 短信验证码三步流程。
// 成功后 push HuishHomePage；pop 回模块导航页。

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme.dart';
import '../../widgets/glass_background.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/glass_snackbar.dart';
import 'huish_auth_state.dart';
import 'huish_home_page.dart';

class HuishLoginPage extends ConsumerStatefulWidget {
  const HuishLoginPage({super.key});
  @override
  ConsumerState<HuishLoginPage> createState() => _HuishLoginPageState();
}

class _HuishLoginPageState extends ConsumerState<HuishLoginPage> {
  final _phone = TextEditingController();
  final _captcha = TextEditingController();
  final _sms = TextEditingController();

  double _captchaS = 0;
  Uint8List? _captchaBytes;

  bool _sending = false;
  bool _submitting = false;
  int _countdown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadCaptcha();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _captcha.dispose();
    _sms.dispose();
    super.dispose();
  }

  Future<void> _loadCaptcha() async {
    try {
      final api = ref.read(huishApiClientProvider);
      final r = await api.getCaptcha();
      if (!mounted) return;
      setState(() {
        _captchaS = r.s;
        _captchaBytes = Uint8List.fromList(r.imageBytes);
      });
    } catch (e) {
      if (mounted) showGlassSnackBar(context, '加载验证码失败: $e');
    }
  }

  Future<void> _sendSms() async {
    final phone = _phone.text.trim();
    final code = _captcha.text.trim();
    if (phone.length != 11) {
      showGlassSnackBar(context, '请输入 11 位手机号');
      return;
    }
    if (code.isEmpty) {
      showGlassSnackBar(context, '请输入图形验证码');
      return;
    }
    setState(() => _sending = true);
    try {
      final api = ref.read(huishApiClientProvider);
      final resp = await api.sendSmsCode(
        phone: phone,
        captchaCode: code,
        captchaS: _captchaS,
      );
      if (!mounted) return;
      if (resp.isSuccess) {
        showGlassSnackBar(context, '验证码已发送');
        _startCountdown();
      } else {
        showGlassSnackBar(context, '发送失败 (code: ${resp.code})');
        await _loadCaptcha();
      }
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(context, '发送失败: $e');
        _loadCaptcha();
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startCountdown() {
    setState(() => _countdown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _countdown <= 1) {
        t.cancel();
        if (mounted) setState(() => _countdown = 0);
        return;
      }
      setState(() => _countdown--);
    });
  }

  Future<void> _login() async {
    final phone = _phone.text.trim();
    final sms = _sms.text.trim();
    if (phone.length != 11) {
      showGlassSnackBar(context, '请输入 11 位手机号');
      return;
    }
    if (sms.isEmpty) {
      showGlassSnackBar(context, '请输入短信验证码');
      return;
    }
    setState(() => _submitting = true);
    final ok = await ref
        .read(huishAuthStateProvider.notifier)
        .login(phone, sms);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HuishHomePage()),
      );
    } else {
      final err = ref.read(huishAuthStateProvider).error;
      showGlassSnackBar(context, err ?? '登录失败');
      await _loadCaptcha();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                        color: kPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF4BA3C7), Color(0xFF2E6B8C)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4BA3C7).withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.water_drop_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '惠生活 798',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: kInk,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '请使用手机号验证码登录',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: kTextMuted),
                ),
                const SizedBox(height: 26),
                GlassCard(
                  radius: 24,
                  padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
                  child: Column(
                    children: [
                      _field(_phone, '手机号', keyboard: TextInputType.phone),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(child: _field(_captcha, '图形验证码')),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: _loadCaptcha,
                            child: Container(
                              height: 46,
                              width: 110,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.65),
                                ),
                              ),
                              child: _captchaBytes != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: Image.memory(
                                        _captchaBytes!,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, _, _) => const Center(
                                          child: Icon(
                                            Icons.refresh,
                                            color: kPrimary,
                                          ),
                                        ),
                                      ),
                                    )
                                  : const Center(
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: kPrimary,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(child: _field(_sms, '短信验证码')),
                          const SizedBox(width: 10),
                          SizedBox(
                            height: 46,
                            child: _countdown > 0
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.4,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      '${_countdown}s',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: kTextMuted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                : ElevatedButton(
                                    onPressed: _sending ? null : _sendSms,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: kPrimary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                      ),
                                    ),
                                    child: Text(
                                      _sending ? '发送中…' : '获取验证码',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          onPressed: _submitting ? null : _login,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF4BA3C7),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            elevation: 6,
                            shadowColor: const Color(0xFF4BA3C7)
                                .withValues(alpha: 0.4),
                          ),
                          child: Text(
                            _submitting ? '登录中…' : '登 录',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '数据来自第三方接口，与惠生活798无隶属关系',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: kTextMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String hint, {
    TextInputType? keyboard,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
    ),
    child: TextField(
      controller: c,
      keyboardType: keyboard,
      decoration: InputDecoration(
        hintText: hint,
        border: InputBorder.none,
        hintStyle: const TextStyle(fontSize: 13, color: kTextMuted),
      ),
    ),
  );
}
