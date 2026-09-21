// huish/huish_device_page.dart —— 取水控制页。
//
// 核心：本次接水量大字显示（取水中动态跳动 + 取完常驻），
// 参考项目的"本次接水 = 当前累计 - 开始时累计"计算逻辑原封不动。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme.dart';
import '../../widgets/glass_background.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/glass_snackbar.dart';
import '../huish_api_client.dart';
import '../huish_auth_state.dart';

class HuishDevicePage extends ConsumerStatefulWidget {
  final String deviceId;
  final String deviceName;
  const HuishDevicePage({super.key, required this.deviceId, required this.deviceName});
  @override
  ConsumerState<HuishDevicePage> createState() => _HuishDevicePageState();
}

class _HuishDevicePageState extends ConsumerState<HuishDevicePage> {
  bool _loading = true;
  bool _error = false;
  bool _running = false;
  double _currentOut = 0;
  double _startOut = 0;
  double _balance = 0;
  String _unit = '升';
  String _addr = '';
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final api = ref.read(huishApiClientProvider);
      final home = await api.getDeviceHome(widget.deviceId);
      final status = await api.getDeviceStatus(widget.deviceId);
      if (!mounted) return;
      if (!home.isSuccess || !status.isSuccess) {
        setState(() { _error = true; _loading = false; });
        return;
      }
      final homeData = home.dataMap ?? {};
      final statusData = status.dataMap ?? {};
      final bm = homeData['bm'] as Map<String, dynamic>?;
      _unit = bm?['unit'] as String? ?? '升';
      final addr = homeData['addr'] as Map<String, dynamic>?;
      _addr = addr?['detail']?.toString() ?? '';
      final wallet = homeData['wallet'] as Map<String, dynamic>?;
      _balance = (wallet?['olCash'] as num?)?.toDouble() ?? 0;
      final device = statusData['device'] as Map<String, dynamic>?;
      final gene = device?['gene'] as Map<String, dynamic>?;
      if (gene != null) {
        _currentOut = (gene['out'] as num?)?.toDouble() ?? 0;
        final status = gene['status'] as int? ?? 99;
        _running = status == 1;
        if (_running) _startOut = _currentOut;
      }
      setState(() { _loading = false; });
      if (_running) _startPolling();
    } catch (_) {
      if (mounted) setState(() { _error = true; _loading = false; });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  Future<void> _poll() async {
    if (!_running) return;
    try {
      final api = ref.read(huishApiClientProvider);
      final resp = await api.getDeviceStatus(widget.deviceId);
      if (!mounted || !resp.isSuccess) return;
      final device = resp.dataMap?['device'] as Map<String, dynamic>?;
      final gene = device?['gene'] as Map<String, dynamic>?;
      if (gene != null) {
        final out = (gene['out'] as num?)?.toDouble() ?? _currentOut;
        setState(() {
          _currentOut = out;
          final status = gene['status'] as int? ?? 99;
          if (status != 1) {
            _running = false;
            _pollTimer?.cancel();
          }
        });
      }
    } catch (_) {}
  }

  double get _thisUse => _currentOut - _startOut;

  Future<void> _start() async {
    setState(() => _running = true);
    _startOut = _currentOut;
    try {
      final api = ref.read(huishApiClientProvider);
      final resp = await api.startDevice(widget.deviceId);
      if (!mounted) return;
      if (!resp.isSuccess) {
        showGlassSnackBar(context, '启动失败 (code: ${resp.code})');
        setState(() => _running = false);
        return;
      }
      _startPolling();
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(context, '启动失败: $e');
        setState(() => _running = false);
      }
    }
  }

  Future<void> _stop() async {
    _pollTimer?.cancel();
    try {
      final api = ref.read(huishApiClientProvider);
      final resp = await api.stopDevice(widget.deviceId);
      if (!mounted) return;
      setState(() => _running = false);
      if (resp.isSuccess) {
        showGlassSnackBar(context, '设备已停止');
      }
      await _load(); // 刷新状态/余额
    } catch (e) {
      if (mounted) {
        setState(() => _running = false);
        showGlassSnackBar(context, '设备已停止（网络异常）');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error
                  ? Center(child: _ErrorView(onRetry: _load))
                  : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 38, height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: kPrimary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(widget.deviceName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kInk)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // 大号接水量卡片
          GlassCard(
            radius: 24,
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    _running ? Icons.water_drop : Icons.water_drop_outlined,
                    key: ValueKey(_running),
                    size: 56,
                    color: _running ? const Color(0xFF4BA3C7) : kTextMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _running ? '正在接水…' : (_thisUse > 0 ? '本次已接' : '已停止'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _running ? const Color(0xFF4BA3C7) : kTextMuted,
                  ),
                ),
                const SizedBox(height: 10),
                // 本次接水量大字
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    _running || _thisUse > 0
                        ? '${_thisUse.toStringAsFixed(1)} $_unit'
                        : '0.0 $_unit',
                    key: ValueKey(_thisUse.toStringAsFixed(1)),
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      color: kInk,
                      height: 1.1,
                      shadows: [
                        Shadow(
                          color: kPrimary.withValues(alpha: 0.15),
                          offset: const Offset(0, 2),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_running) ...[
                  const SizedBox(height: 4),
                  const Text('3 秒刷新', style: TextStyle(fontSize: 11, color: kTextMuted)),
                ],
                const SizedBox(height: 18),
                // 统计信息行
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStat('累计出水', '${_currentOut.toStringAsFixed(1)} $_unit'),
                    Container(width: 1, height: 36, color: kGlassGridLine),
                    _buildStat('账户余额', '¥${_balance.toStringAsFixed(2)}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 取水/停水按钮
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _running ? null : _start,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4BA3C7),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 6,
                shadowColor: const Color(0xFF4BA3C7).withValues(alpha: 0.4),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 26),
              label: Text(_running ? '取水进行中…' : '开始取水', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _running ? _stop : null,
              style: FilledButton.styleFrom(
                backgroundColor: _running ? const Color(0xFFB85450) : Colors.white.withValues(alpha: 0.5),
                foregroundColor: _running ? Colors.white : kTextMuted,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 0,
              ),
              icon: const Icon(Icons.stop_rounded, size: 24),
              label: const Text('停止取水', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          // 设备信息
          if (_addr.isNotEmpty) ...[
            const SizedBox(height: 20),
            GlassCard(
              radius: 18,
              padding: const EdgeInsets.all(14),
              live: false,
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 16, color: kPrimary),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_addr, style: const TextStyle(fontSize: 12.5, color: kTextMain))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kInk)),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(fontSize: 11.5, color: kTextMuted)),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.wifi_off_rounded, size: 48, color: kTextMuted),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
}
