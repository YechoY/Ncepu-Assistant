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
import 'huish_auth_state.dart';

class HuishDevicePage extends ConsumerStatefulWidget {
  final String deviceId;
  final String deviceName;
  final bool alreadyFav; // 是否已在"我的设备"列表
  const HuishDevicePage({
    super.key,
    required this.deviceId,
    required this.deviceName,
    this.alreadyFav = true,
  });
  @override
  ConsumerState<HuishDevicePage> createState() => _HuishDevicePageState();
}

class _HuishDevicePageState extends ConsumerState<HuishDevicePage> {
  bool _loading = true;
  bool _error = false;
  bool _running = false;
  bool _hasSession = false; // 本次页面内是否已有取水会话（防止把累计值当"本次"）
  double _currentOut = 0;
  double _startOut = 0;
  double _balance = 0;
  int _priceFen = 0; // 单价（分/升），gene.price
  String _unit = '升';
  String _addr = '';
  Timer? _pollTimer;
  bool _alreadyFav = true;
  double? _lastBillPayment; // 停止后从最新账单取的本次真实消费
  int _startTs = 0; // 本次开始时间（秒），用于匹配账单

  @override
  void initState() {
    super.initState();
    _alreadyFav = widget.alreadyFav;
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = false;
      });
    }
    try {
      final api = ref.read(huishApiClientProvider);
      final home = await api.getDeviceHome(widget.deviceId);
      final status = await api.getDeviceStatus(widget.deviceId);
      if (!mounted) return;
      if (!home.isSuccess || !status.isSuccess) {
        setState(() {
          _error = true;
          _loading = false;
        });
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
        _priceFen = (gene['price'] as num?)?.toInt() ?? 0;
        final status = gene['status'] as int? ?? 99;
        _running = status == 1;
        // 设备远端已在取水（如从别处启动）：以当前累计为本次起点，从 0 开始计
        if (_running && !_hasSession) {
          _startOut = _currentOut;
          _hasSession = true;
        }
      }
      setState(() {
        _loading = false;
      });
      if (_running) {
        _startPolling();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
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
        final still = gene['status'] as int? ?? 99;
        setState(() {
          _currentOut = out;
          _running = still == 1;
        });
        if (!_running) {
          // 服务端已停止（水接完/设备自停）
          _pollTimer?.cancel();
          _refreshBalance();
          _fetchLatestBill();
        }
      }
    } catch (_) {}
  }

  double get _thisUse =>
      _hasSession ? (_currentOut - _startOut).clamp(0, double.infinity) : 0;

  double get _thisCost => _thisUse * _priceFen / 100;

  String get _costLabel {
    final p = _lastBillPayment;
    if (p != null) return '¥${p.toStringAsFixed(2)}';
    if (_priceFen > 0) return '¥${_thisCost.toStringAsFixed(2)}';
    return '--';
  }

  Future<void> _start() async {
    _startOut = _currentOut;
    _hasSession = true;
    _lastBillPayment = null;
    _startTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    setState(() => _running = true);
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
        showGlassSnackBar(context, '已暂停出水');
      }
      // 只刷余额，不调 _load（避免覆盖本次会话数据）
      await _refreshBalance();
      await _fetchLatestBill(); // 取本次真实消费
    } catch (e) {
      if (mounted) {
        setState(() => _running = false);
        showGlassSnackBar(context, '已暂停出水（网络异常）');
      }
    }
  }

  // 只刷新余额，不影响本次接水量
  Future<void> _refreshBalance() async {
    try {
      final api = ref.read(huishApiClientProvider);
      final home = await api.getDeviceHome(widget.deviceId);
      if (!mounted || !home.isSuccess) return;
      final wallet = home.dataMap?['wallet'] as Map<String, dynamic>?;
      final bal = (wallet?['olCash'] as num?)?.toDouble() ?? _balance;
      final gene =
          (home.dataMap?['device'] as Map<String, dynamic>?)?['gene']
              as Map<String, dynamic>?;
      if (gene != null) {
        // 更新累计出水和单价，但不动 _startOut 和 _hasSession
        final out = (gene['out'] as num?)?.toDouble() ?? _currentOut;
        final price = (gene['price'] as num?)?.toInt() ?? _priceFen;
        setState(() {
          _currentOut = out;
          _priceFen = price;
          _balance = bal;
        });
      } else {
        setState(() => _balance = bal);
      }
    } catch (_) {}
  }

  // 停止后从最新按量账单取本次真实消费（type=21 且结算时间晚于本次开始）
  // 账单生成有延迟，重试 2s × 5 次
  Future<void> _fetchLatestBill({int attempt = 0}) async {
    if (_startTs == 0) return;
    if (attempt >= 5) return; // 最多 5 次
    try {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      final api = ref.read(huishApiClientProvider);
      final resp = await api.getBillList(page: 0, size: 5);
      if (!mounted || !resp.isSuccess) {
        _fetchLatestBill(attempt: attempt + 1);
        return;
      }
      for (final b in resp.dataList ?? const []) {
        if (b is! Map<String, dynamic>) continue;
        final type = b['type'] as int? ?? 0;
        final ctime = b['ctime'] as int? ?? 0;
        // 账单生成后 ctime 可能比 _startTs 略晚（秒级匹配）
        if (type == 21 && ctime >= _startTs - 5) {
          final pay = (b['payment'] as num?)?.toDouble();
          if (pay != null && mounted) {
            setState(() => _lastBillPayment = pay);
          }
          return; // 命中，停止重试
        }
      }
      // 未命中 → 继续重试
      _fetchLatestBill(attempt: attempt + 1);
    } catch (_) {
      if (attempt < 4) _fetchLatestBill(attempt: attempt + 1);
    }
  }

  // 退出取水：取水中先暂停出水再离开
  Future<void> _exit() async {
    if (_running) {
      _pollTimer?.cancel();
      try {
        final api = ref.read(huishApiClientProvider);
        await api.stopDevice(widget.deviceId);
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  // 添加到"我的设备"列表
  Future<void> _favoriteDevice() async {
    try {
      final api = ref.read(huishApiClientProvider);
      final resp = await api.favoriteDevice(widget.deviceId);
      if (!mounted) return;
      if (resp.isSuccess) {
        setState(() => _alreadyFav = true);
        showGlassSnackBar(context, '已添加到我的设备列表');
      } else if (resp.code == 400 || resp.code == 409) {
        setState(() => _alreadyFav = true);
        showGlassSnackBar(context, '设备已在列表中');
      } else {
        showGlassSnackBar(context, '添加失败 (code: ${resp.code})');
      }
    } catch (_) {
      if (mounted) showGlassSnackBar(context, '网络异常，请重试');
    }
  }

  // 移出"我的设备"列表
  Future<void> _unfavoriteDevice() async {
    try {
      final api = ref.read(huishApiClientProvider);
      final resp = await api.favoriteDevice(widget.deviceId, remove: true);
      if (!mounted) return;
      if (resp.isSuccess) {
        setState(() => _alreadyFav = false);
        showGlassSnackBar(context, '已从我的设备列表移除');
      } else {
        showGlassSnackBar(context, '移除失败 (code: ${resp.code})');
      }
    } catch (_) {
      if (mounted) showGlassSnackBar(context, '网络异常，请重试');
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
              Expanded(
                child: Text(
                  widget.deviceName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: kInk,
                  ),
                ),
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
                    color: _running ? kHuish : kTextMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _running
                      ? '正在接水…'
                      : _hasSession
                      ? '本次接水完成'
                      : '待取水',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _running ? kHuish : kTextMuted,
                  ),
                ),
                const SizedBox(height: 10),
                // 本次接水量大字
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    '${_thisUse.toStringAsFixed(1)} $_unit',
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
                  const Text(
                    '3 秒刷新',
                    style: TextStyle(fontSize: 11, color: kTextMuted),
                  ),
                ],
                const SizedBox(height: 18),
                // 统计信息行：本次消费（真实/估算/--）+ 累计出水 + 余额
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStat(
                      _lastBillPayment != null || _priceFen <= 0
                          ? '本次消费'
                          : '本次消费(估)',
                      _costLabel,
                    ),
                    Container(width: 1, height: 36, color: kGlassGridLine),
                    _buildStat(
                      '累计出水',
                      '${_currentOut.toStringAsFixed(1)} $_unit',
                    ),
                    Container(width: 1, height: 36, color: kGlassGridLine),
                    _buildStat('账户余额', '¥${_balance.toStringAsFixed(2)}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 开始取水 / 暂停取水（单击切换）
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _running ? _stop : _start,
              style: FilledButton.styleFrom(
                backgroundColor: _running
                    ? const Color(0xFFB85450)
                    : kHuishDeep,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: _running ? 0 : 6,
                shadowColor: kHuishDeep.withValues(alpha: 0.4),
              ),
              icon: Icon(
                _running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 26,
              ),
              label: Text(
                _running ? '暂停取水' : '开始取水',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 退出取水（中性灰，区别于收藏操作）
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _exit,
              style: OutlinedButton.styleFrom(
                foregroundColor: kTextMuted,
                side: BorderSide(color: kTextMuted.withValues(alpha: 0.35)),
                backgroundColor: Colors.white.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text(
                '退出取水',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // 添加/移出"我的设备"列表（深水蓝，与退出取水颜色区分）
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _alreadyFav ? _unfavoriteDevice : _favoriteDevice,
              style: OutlinedButton.styleFrom(
                foregroundColor: _alreadyFav
                    ? const Color(0xFFB85450)
                    : kHuishDeep,
                side: BorderSide(
                  color: _alreadyFav
                      ? const Color(0xFFB85450).withValues(alpha: 0.4)
                      : kHuish.withValues(alpha: 0.5),
                ),
                backgroundColor: Colors.white.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: Icon(
                _alreadyFav
                    ? Icons.bookmark_remove_rounded
                    : Icons.bookmark_add_rounded,
                size: 18,
              ),
              label: Text(
                _alreadyFav ? '从我的列表移除' : '添加到我的列表',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
                  const Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: kPrimary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _addr,
                      style: const TextStyle(fontSize: 12.5, color: kTextMain),
                    ),
                  ),
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
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: kInk,
          ),
        ),
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
