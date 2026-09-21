// huish/huish_add_device_page.dart —— 添加设备页（扫码 / 手动输入，参照上游 add_device_screen）。
//
// 上游同款两段式流程：getDeviceQr(设备码) 查询设备信息 → 用户确认后
// favoriteDevice 收藏绑定 → pop(设备码) 回首页刷新列表。
// 400/409 = 设备已在列表或已绑定，同样返回设备码让首页刷新。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../theme.dart';
import '../../widgets/glass_background.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/glass_snackbar.dart';
import 'huish_auth_state.dart';

class HuishAddDevicePage extends ConsumerStatefulWidget {
  const HuishAddDevicePage({super.key});
  @override
  ConsumerState<HuishAddDevicePage> createState() => _HuishAddDevicePageState();
}

class _HuishAddDevicePageState extends ConsumerState<HuishAddDevicePage> {
  final MobileScannerController _ctrl = MobileScannerController();
  final TextEditingController _codeCtrl = TextEditingController();

  bool _manualMode = false;
  bool _torch = false;
  bool _looking = false; // 查询中
  bool _done = false; // 已完成，停止重复识别
  Map<String, dynamic>? _result; // getDeviceQr 的 dataMap
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  /// 从二维码内容提取设备 ID：裸数字 / URL 参数 / 任意位置的 10-20 位数字。
  String? _extractDeviceId(String code) {
    if (RegExp(r'^\d{10,20}$').hasMatch(code)) return code;

    final uri = Uri.tryParse(code);
    if (uri != null) {
      final id = uri.queryParameters['id'];
      if (id != null && id.isNotEmpty) return id;
      final did = uri.queryParameters['did'];
      if (did != null && did.isNotEmpty) return did;
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        final last = segments.last;
        if (RegExp(r'^\d{10,20}$').hasMatch(last)) return last;
      }
    }

    final match = RegExp(r'(\d{10,20})').firstMatch(code);
    return match?.group(1);
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_looking || _done || _manualMode) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;
    final did = _extractDeviceId(code);
    if (did == null || did.isEmpty) return;
    await _lookup(did);
  }

  void _lookupManual() {
    final did = _codeCtrl.text.trim();
    if (did.isEmpty) {
      showGlassSnackBar(context, '请输入设备码');
      return;
    }
    _lookup(did);
  }

  Future<void> _lookup(String did) async {
    if (_looking) return;
    setState(() {
      _looking = true;
      _error = null;
    });
    try {
      final api = ref.read(huishApiClientProvider);
      final resp = await api.getDeviceQr(did);
      if (!mounted) return;
      if (resp.isSuccess) {
        setState(() {
          _result = resp.dataMap;
          _looking = false;
        });
      } else if (resp.code == 400 || resp.code == 409) {
        showGlassSnackBar(context, '设备已在列表中');
        _finish(did);
      } else {
        setState(() {
          _error =
              resp.dataMap?['msg'] as String? ?? '未找到设备 (code: ${resp.code})';
          _looking = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '网络异常，请重试';
        _looking = false;
      });
    }
  }

  Future<void> _favorite() async {
    final dev = _result?['dev'] as Map<String, dynamic>?;
    final did = dev?['id']?.toString() ?? '';
    if (did.isEmpty) return;
    try {
      final api = ref.read(huishApiClientProvider);
      final resp = await api.favoriteDevice(did);
      if (!mounted) return;
      if (resp.isSuccess) {
        showGlassSnackBar(context, '已收藏设备');
        _finish(did);
      } else {
        showGlassSnackBar(context, '收藏失败 (code: ${resp.code})');
      }
    } catch (_) {
      if (mounted) showGlassSnackBar(context, '网络异常，请重试');
    }
  }

  void _finish(String did) {
    setState(() => _done = true);
    Navigator.of(context).pop(did);
  }

  void _reset() {
    setState(() {
      _result = null;
      _error = null;
      _looking = false;
      _codeCtrl.clear();
    });
  }

  void _setMode(bool manual) {
    if (_manualMode == manual) return;
    setState(() {
      _manualMode = manual;
      _result = null;
      _error = null;
    });
    if (manual) {
      _ctrl.stop(); // 切到手动输入时释放相机
    }
    // 切回扫码时 MobileScanner autoStart 自动重启相机
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: Column(
            children: [
              // 顶部栏
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    GestureDetector(
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
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '添加设备',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: kInk,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 模式切换
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    _modeChip(
                      '扫码添加',
                      Icons.qr_code_scanner_rounded,
                      !_manualMode,
                      () => _setMode(false),
                    ),
                    const SizedBox(width: 8),
                    _modeChip(
                      '手动输入',
                      Icons.keyboard_rounded,
                      _manualMode,
                      () => _setMode(true),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: _result != null
                      ? _buildResultView()
                      : _error != null
                      ? _buildErrorView()
                      : _manualMode
                      ? _buildManualView()
                      : _buildScanView(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeChip(
    String label,
    IconData icon,
    bool selected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: _looking ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: kSpring,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? kPrimary.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected
                ? kPrimary.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.65),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? kPrimary : kTextMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? kPrimary : kTextMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 扫码视图 ─────────────────────────────────────────────

  Widget _buildScanView() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: Colors.black,
            child: MobileScanner(
              controller: _ctrl,
              onDetect: _onDetect,
              errorBuilder: (_, error, _) =>
                  _ScanErrorView(message: error.toString()),
            ),
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          // 手电筒
          Positioned(
            right: 16,
            bottom: 16,
            child: GestureDetector(
              onTap: () async {
                await _ctrl.toggleTorch();
                if (mounted) setState(() => _torch = !_torch);
              },
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _torch
                      ? const Color(0xFF4BA3C7).withValues(alpha: 0.85)
                      : Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  _torch ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          // 查询中遮罩
          if (_looking)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      '正在查询设备…',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
          // 底部提示
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Text(
              '将设备机身二维码对准框内',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 手动输入视图 ─────────────────────────────────────────

  Widget _buildManualView() {
    return Center(
      child: GlassCard(
        radius: 24,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.keyboard_rounded, size: 40, color: kPrimary),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                '输入设备码',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: kInk,
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Center(
              child: Text(
                '机身二维码下方的一串数字',
                style: TextStyle(fontSize: 12, color: kTextMuted),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: kInk,
              ),
              decoration: InputDecoration(
                hintText: '请输入设备码',
                hintStyle: const TextStyle(
                  fontSize: 14,
                  color: kTextMuted,
                  fontWeight: FontWeight.w400,
                ),
                prefixIcon: const Icon(
                  Icons.numbers_rounded,
                  size: 20,
                  color: kTextMuted,
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.55),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: kPrimary, width: 1.5),
                ),
              ),
              onSubmitted: (_) => _lookupManual(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 46,
              child: FilledButton.icon(
                onPressed: _looking ? null : _lookupManual,
                style: FilledButton.styleFrom(backgroundColor: kPrimary),
                icon: _looking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.search_rounded, size: 19),
                label: const Text('查询设备'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 查询结果视图 ─────────────────────────────────────────

  Widget _buildResultView() {
    final dev = _result?['dev'] as Map<String, dynamic>?;
    final name = (dev?['name'] ?? dev?['nickname'])?.toString() ?? '未知设备';
    final did = dev?['id']?.toString() ?? '';

    final addrRaw = dev?['addr'];
    String addrText = '';
    if (addrRaw is Map) {
      addrText = (addrRaw['detail'] ?? addrRaw['name'] ?? '').toString();
    } else if (addrRaw is String) {
      addrText = addrRaw;
    }

    return Center(
      child: GlassCard(
        radius: 24,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.water_drop_rounded,
              size: 40,
              color: Color(0xFF4BA3C7),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: kInk,
                ),
              ),
            ),
            if (addrText.isNotEmpty) ...[
              const SizedBox(height: 6),
              Center(
                child: Text(
                  addrText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: kTextMuted),
                ),
              ),
            ],
            if (did.isNotEmpty) ...[
              const SizedBox(height: 4),
              Center(
                child: Text(
                  '设备码 $did',
                  style: const TextStyle(fontSize: 12, color: kTextMuted),
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 46,
              child: FilledButton.icon(
                onPressed: _favorite,
                style: FilledButton.styleFrom(backgroundColor: kPrimary),
                icon: const Icon(Icons.bookmark_add_rounded, size: 19),
                label: const Text('收藏设备'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: TextButton(
                onPressed: _reset,
                child: const Text(
                  '返回重扫',
                  style: TextStyle(color: kTextMuted, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 错误视图 ─────────────────────────────────────────────

  Widget _buildErrorView() {
    return Center(
      child: GlassCard(
        radius: 24,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: Color(0xFFB85450),
            ),
            const SizedBox(height: 12),
            Text(
              _error ?? '未知错误',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, color: kTextMain),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 42,
              child: FilledButton(
                onPressed: _reset,
                style: FilledButton.styleFrom(backgroundColor: kPrimary),
                child: const Text('返回重试'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanErrorView extends StatelessWidget {
  final String message;
  const _ScanErrorView({required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              size: 48,
              color: Colors.white70,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
