// huish/huish_home_page.dart —— 饮水首页：扫码大按钮 + 分组设备列表 + 账单入口。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme.dart';
import '../../widgets/glass_background.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/glass_snackbar.dart';
import '../huish_api_client.dart';
import '../huish_auth_state.dart';
import 'device_prefs.dart';
import 'huish_bill_page.dart';
import 'huish_device_page.dart';

class HuishHomePage extends ConsumerStatefulWidget {
  const HuishHomePage({super.key});
  @override
  ConsumerState<HuishHomePage> createState() => _HuishHomePageState();
}

class _HuishHomePageState extends ConsumerState<HuishHomePage> {
  bool _loading = true;
  String? _error;
  List<dynamic> _devices = [];
  Map<String, DeviceCustomInfo> _customs = {};
  List<String> _groups = ['default'];
  Set<String> _collapsed = {};
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(huishApiClientProvider);
      final master = await api.getMaster();
      if (!mounted) return;
      if (!master.isSuccess) {
        setState(() {
          _error = '加载失败 (code: ${master.code})';
          _loading = false;
        });
        return;
      }
      final data = master.dataMap ?? {};
      final devs = data['devices'] ?? data['device'] ?? [];
      setState(() {
        _devices = devs is List ? devs : [devs];
        _loading = false;
      });
      _customs = await DevicePrefs.loadDeviceCustoms();
      _groups = await DevicePrefs.loadGroups();
      // 默认所有分组展开（除了 default 也展开）
      setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  // 按分组整理设备：Map<groupId, List<device>>
  Map<String, List<dynamic>> _groupDevices() {
    final result = <String, List<dynamic>>{};
    for (final g in _groups) {
      result[g] = [];
    }
    for (final d in _devices) {
      final id = _deviceId(d);
      final custom = _customs[id] ?? DeviceCustomInfo.empty();
      final group = _groups.contains(custom.groupId) ? custom.groupId : 'default';
      result[group]!.add(d);
    }
    // 空分组只留 default（其他空的不显示）
    result.removeWhere((k, v) => k != 'default' && v.isEmpty);
    return result;
  }

  String _deviceId(dynamic d) {
    if (d is Map<String, dynamic>) {
      return (d['id'] ?? d['did'] ?? d['deviceId'] ?? '').toString();
    }
    return d.toString();
  }

  String _deviceName(dynamic d) {
    final id = _deviceId(d);
    final custom = _customs[id];
    if (custom != null && custom.customName.isNotEmpty) return custom.customName;
    if (d is Map<String, dynamic>) {
      final name = d['name'] ?? d['title'] ?? d['addr_name'] ?? '';
      return name.toString();
    }
    return '饮水机';
  }

  String _deviceAddr(dynamic d) {
    if (d is Map<String, dynamic>) {
      final addr = d['addr'];
      if (addr is Map) {
        final detail = addr['detail'] ?? addr['name'] ?? '';
        return detail.toString();
      }
      return d['addr_name']?.toString() ?? '';
    }
    return '';
  }

  void _tapDevice(dynamic d) {
    final id = _deviceId(d);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HuishDevicePage(
          deviceId: id,
          deviceName: _deviceName(d),
        ),
      ),
    );
  }

  void _scan() {
    // 扫码依赖 mobile_scanner，先加依赖
    showGlassSnackBar(context, '扫码功能即将上线');
  }

  Future<void> _renameDevice(dynamic d) async {
    final id = _deviceId(d);
    final name = await showDialog<String>(
      context: context,
      builder: (_) {
        final c = TextEditingController(text: _deviceName(d));
        return AlertDialog(
          title: const Text('重命名设备'),
          content: TextField(controller: c, autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(context, c.text.trim()),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    if (name != null && name.isNotEmpty) {
      await DevicePrefs.updateDeviceCustom(id, customName: name);
      _customs = await DevicePrefs.loadDeviceCustoms();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final huish = ref.watch(huishAuthStateProvider);
    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: Column(
            children: [
              // 顶部栏
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
                child: Row(
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
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('饮水服务', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kInk)),
                          Text('惠生活 798', style: TextStyle(fontSize: 11.5, color: kTextMuted)),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _tapBill,
                      child: Container(
                        width: 38, height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
                        ),
                        child: const Icon(Icons.receipt_long_rounded, size: 19, color: kPrimary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _logout,
                      child: Container(
                        width: 38, height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
                        ),
                        child: const Icon(Icons.logout_rounded, size: 18, color: Color(0xFFB85450)),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(child: _ErrorView(error: _error!, onRetry: _load))
                        : _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final grouped = _groupDevices();
    final groupNames = grouped.keys.toList();
    return RefreshIndicator(
      color: kPrimary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          // 扫码大按钮
          GestureDetector(
            onTap: _scan,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: kSpring,
              width: double.infinity,
              height: 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4BA3C7).withValues(alpha: 0.28),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF4BA3C7), Color(0xFF2E6B8C)],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                child: Row(
                  children: [
                    Container(
                      width: 56, height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 30),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('扫码取水', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                          SizedBox(height: 4),
                          Text('扫描设备二维码直接进入取水', style: TextStyle(fontSize: 12.5, color: Colors.white70, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, size: 28, color: Colors.white70),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('我的设备', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kInk)),
          const SizedBox(height: 10),
          ...groupNames.map((gid) {
            final list = grouped[gid]!;
            if (list.isEmpty) return const SizedBox.shrink();
            final collapsed = _collapsed.contains(gid);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => setState(() {
                    if (collapsed) _collapsed.remove(gid);
                    else _collapsed.add(gid);
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                    child: Row(
                      children: [
                        Icon(collapsed ? Icons.expand_more : Icons.expand_less, size: 18, color: kTextMuted),
                        const SizedBox(width: 4),
                        Text(
                          gid == 'default' ? '默认' : gid,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kTextMuted),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: kPrimary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('${list.length}', style: const TextStyle(fontSize: 11, color: kPrimary, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!collapsed) ...[
                  ...list.map((d) => _DeviceCard(
                        device: d,
                        customName: _deviceName(d),
                        addr: _deviceAddr(d),
                        onTap: () => _tapDevice(d),
                        onRename: () => _renameDevice(d),
                      )),
                  const SizedBox(height: 6),
                ],
              ],
            );
          }),
        ],
      ),
    );
  }

  Future<void> _tapBill() async {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HuishBillPage()),
    );
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x402E3350),
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('退出生活服务'),
        content: const Text('确定要退出饮水服务登录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出', style: TextStyle(color: Color(0xFFB85450))),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(huishAuthStateProvider.notifier).logout();
      if (mounted) Navigator.of(context).pop();
    }
  }
}

class _DeviceCard extends StatelessWidget {
  final dynamic device;
  final String customName;
  final String addr;
  final VoidCallback onTap;
  final VoidCallback onRename;
  const _DeviceCard({
    required this.device,
    required this.customName,
    required this.addr,
    required this.onTap,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: GlassCard(
          radius: 18,
          padding: const EdgeInsets.all(14),
          live: false,
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF4BA3C7).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.water_drop_rounded, size: 22, color: Color(0xFF4BA3C7)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kInk)),
                    if (addr.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(addr, style: const TextStyle(fontSize: 12, color: kTextMuted)),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_note_rounded, size: 18, color: kTextMuted),
                onPressed: onRename,
                tooltip: '重命名',
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF4BA3C7),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4BA3C7).withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Text('取水', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.wifi_off_rounded, size: 48, color: kTextMuted.withValues(alpha: 0.6)),
        const SizedBox(height: 12),
        Text('加载失败', style: TextStyle(color: kTextMuted.withValues(alpha: 0.7))),
        const SizedBox(height: 4),
        Text(error, style: TextStyle(fontSize: 12, color: kTextMuted.withValues(alpha: 0.6))),
        const SizedBox(height: 16),
        FilledButton(onPressed: onRetry, style: FilledButton.styleFrom(backgroundColor: kPrimary), child: const Text('重试')),
      ],
    );
  }
}
