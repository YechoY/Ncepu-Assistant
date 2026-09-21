// huish/huish_scan_page.dart —— 扫码绑定设备页。
//
// mobile_scanner 识别二维码 → 提取设备 ID → getDeviceQr 绑定 →
// pop(设备ID) 回首页，首页刷新后直接进取水页。
// 400/409 = 设备已在列表/已绑定，同样视为成功进入。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../widgets/glass_snackbar.dart';
import 'huish_auth_state.dart';

class HuishScanPage extends ConsumerStatefulWidget {
  const HuishScanPage({super.key});
  @override
  ConsumerState<HuishScanPage> createState() => _HuishScanPageState();
}

class _HuishScanPageState extends ConsumerState<HuishScanPage> {
  final MobileScannerController _ctrl = MobileScannerController();
  bool _binding = false;
  bool _done = false;
  bool _torch = false;

  @override
  void dispose() {
    _ctrl.dispose();
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
    if (_binding || _done) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;

    final did = _extractDeviceId(code);
    if (did == null || did.isEmpty) return;

    setState(() => _binding = true);
    try {
      final api = ref.read(huishApiClientProvider);
      final resp = await api.getDeviceQr(did);
      if (!mounted) return;
      if (resp.isSuccess || resp.code == 400 || resp.code == 409) {
        setState(() => _done = true);
        Navigator.of(context).pop(did);
      } else {
        setState(() => _binding = false);
        showGlassSnackBar(context, '绑定失败 (code: ${resp.code})，请重试');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _binding = false);
      showGlassSnackBar(context, '网络异常，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _ctrl,
            onDetect: _onDetect,
            errorBuilder: (_, error, _) => _ScanErrorView(
              message:
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? '相机权限被拒绝，请到系统设置中授权'
                  : '相机启动失败，请重试',
            ),
          ),
          // 扫描框
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _done
                      ? const Color(0xFF5E9C80)
                      : Colors.white.withValues(alpha: 0.85),
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          // 顶栏：返回 + 手电筒
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  GestureDetector(
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
                        _torch
                            ? Icons.flash_on_rounded
                            : Icons.flash_off_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 绑定中遮罩
          if (_binding)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      '正在绑定设备…',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
          // 底部提示
          Positioned(
            bottom: 70,
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
