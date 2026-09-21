// huish/huish_home_page.dart —— 饮水首页：扫码大按钮 + 分组设备列表 + 账单入口。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme.dart';
import '../../widgets/glass_background.dart';
import '../../widgets/glass_card.dart';
import 'huish_auth_state.dart';
import 'device_prefs.dart';
import 'huish_bill_page.dart';
import 'huish_device_page.dart';
import 'huish_add_device_page.dart';

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
  final Set<String> _collapsed = {};
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
      final devs = data['favos'] ?? data['devices'] ?? data['device'] ?? [];
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
      final group = _groups.contains(custom.groupId)
          ? custom.groupId
          : 'default';
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
    if (custom != null && custom.customName.isNotEmpty) {
      return custom.customName;
    }
    if (d is Map<String, dynamic>) {
      final name = d['name'] ?? d['title'] ?? d['addr_name'] ?? '';
      return name.toString();
    }
    return '饮水机';
  }

  void _tapDevice(dynamic d) {
    final id = _deviceId(d);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            HuishDevicePage(deviceId: id, deviceName: _deviceName(d)),
      ),
    );
  }

  Future<void> _addDevice() async {
    final did = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const HuishAddDevicePage()),
    );
    if (did == null || did.isEmpty || !mounted) return;
    await _load(); // 添加/收藏成功 → 刷新设备列表
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
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
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

  // ── 分组管理 ─────────────────────────────────────────────

  Future<String?> _textInputDialog(String title, String initial) {
    return showDialog<String>(
      context: context,
      barrierColor: const Color(0x402E3350),
      builder: (_) {
        final c = TextEditingController(text: initial);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(title, style: const TextStyle(fontSize: 16)),
          content: TextField(controller: c, autofocus: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, c.text.trim()),
              child: const Text('确定', style: TextStyle(color: kPrimary)),
            ),
          ],
        );
      },
    );
  }

  Widget _sheetContainer({required Widget child}) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A2E3350),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sheetAction(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color color = kInk,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: kPrimary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 19, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 设备操作：重命名 / 移动到分组
  Future<void> _showDeviceActions(dynamic d) async {
    final id = _deviceId(d);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _sheetContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '「${_deviceName(d)}」',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: kInk,
              ),
            ),
            const SizedBox(height: 12),
            _sheetAction(Icons.edit_note_rounded, '重命名', () {
              Navigator.of(context).pop();
              _renameDevice(d);
            }),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 6),
              child: Text(
                '移动到分组',
                style: TextStyle(fontSize: 11.5, color: kTextMuted),
              ),
            ),
            ..._groups.map((g) {
              final current = _customs[id]?.groupId ?? 'default';
              return _sheetAction(
                g == 'default' ? Icons.home_rounded : Icons.folder_rounded,
                g == 'default' ? '默认' : g,
                () async {
                  Navigator.of(context).pop();
                  await DevicePrefs.updateDeviceCustom(id, groupId: g);
                  _customs = await DevicePrefs.loadDeviceCustoms();
                  if (mounted) setState(() {});
                },
                color: current == g ? kPrimary : kInk,
                trailing: current == g
                    ? const Icon(Icons.check_rounded, size: 18, color: kPrimary)
                    : null,
              );
            }),
          ],
        ),
      ),
    );
  }

  // 分组管理：新建 / 重命名 / 删除
  Future<void> _manageGroups() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        List<String> sheetGroups = List.from(_groups);
        final grouped = _groupDevices();
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            Future<void> refresh() async {
              sheetGroups = await DevicePrefs.loadGroups();
              setSheetState(() {});
              setState(() {});
            }

            return _sheetContainer(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '分组管理',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: kInk,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () async {
                          final name = await _textInputDialog('新建分组', '');
                          if (name == null || name.isEmpty) return;
                          final ok = await DevicePrefs.addGroup(name);
                          if (!ok) return;
                          await refresh();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: kPrimary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add_rounded,
                                size: 15,
                                color: kPrimary,
                              ),
                              SizedBox(width: 3),
                              Text(
                                '新建',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: kPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...sheetGroups.map((g) {
                    final isDefault = g == 'default';
                    final count = grouped[g]?.length ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Material(
                        color: kPrimary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isDefault
                                    ? Icons.home_rounded
                                    : Icons.folder_rounded,
                                size: 19,
                                color: kPrimary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  isDefault ? '默认 ($count)' : '$g ($count)',
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: kInk,
                                  ),
                                ),
                              ),
                              if (!isDefault) ...[
                                GestureDetector(
                                  onTap: () async {
                                    final nn = await _textInputDialog(
                                      '重命名分组',
                                      g,
                                    );
                                    if (nn == null || nn.isEmpty) return;
                                    await DevicePrefs.renameGroup(g, nn);
                                    await refresh();
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: Icon(
                                      Icons.edit_rounded,
                                      size: 18,
                                      color: kTextMuted,
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      barrierColor: const Color(0x402E3350),
                                      builder: (_) => AlertDialog(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                        title: const Text(
                                          '删除分组',
                                          style: TextStyle(fontSize: 16),
                                        ),
                                        content: Text(
                                          '「$g」内的 $count 台设备将移回默认分组，确定删除？',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('取消'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text(
                                              '删除',
                                              style: TextStyle(
                                                color: Color(0xFFB85450),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok != true) return;
                                    await DevicePrefs.deleteGroup(g);
                                    await refresh();
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: Icon(
                                      Icons.delete_outline_rounded,
                                      size: 18,
                                      color: Color(0xFFB85450),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
    _groups = await DevicePrefs.loadGroups();
    if (mounted) setState(() {});
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
                padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
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
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '饮水服务',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: kInk,
                            ),
                          ),
                          Text(
                            '惠生活 798',
                            style: TextStyle(fontSize: 11.5, color: kTextMuted),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _tapBill,
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
                          Icons.receipt_long_rounded,
                          size: 19,
                          color: kPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _logout,
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
                          Icons.logout_rounded,
                          size: 18,
                          color: Color(0xFFB85450),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: _ErrorView(error: _error!, onRetry: _load),
                      )
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
          // 添加设备大按钮
          GestureDetector(
            onTap: _addDevice,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '添加设备',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '扫描机身二维码或手动输入设备码',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 28,
                      color: Colors.white70,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Text(
                '我的设备',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: kInk,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _manageGroups,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune_rounded, size: 13, color: kTextMuted),
                      SizedBox(width: 4),
                      Text(
                        '分组',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: kTextMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
                    if (collapsed) {
                      _collapsed.remove(gid);
                    } else {
                      _collapsed.add(gid);
                    }
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          collapsed ? Icons.expand_more : Icons.expand_less,
                          size: 18,
                          color: kTextMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          gid == 'default' ? '默认' : gid,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: kTextMuted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: kPrimary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${list.length}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: kPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!collapsed) ...[
                  ...list.map(
                    (d) => _DeviceCard(
                      customName: _deviceName(d),
                      onTap: () => _tapDevice(d),
                      onEdit: () => _showDeviceActions(d),
                    ),
                  ),
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
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const HuishBillPage()));
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
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
  final String customName;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  const _DeviceCard({
    required this.customName,
    required this.onTap,
    required this.onEdit,
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
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF4BA3C7).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.water_drop_rounded,
                  size: 22,
                  color: Color(0xFF4BA3C7),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  customName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: kInk,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.edit_note_rounded,
                  size: 18,
                  color: kTextMuted,
                ),
                onPressed: onEdit,
                tooltip: '重命名 / 分组',
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 7,
                ),
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
                child: const Text(
                  '取水',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
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
        Icon(
          Icons.wifi_off_rounded,
          size: 48,
          color: kTextMuted.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 12),
        Text(
          '加载失败',
          style: TextStyle(color: kTextMuted.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: 4),
        Text(
          error,
          style: TextStyle(
            fontSize: 12,
            color: kTextMuted.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: onRetry,
          style: FilledButton.styleFrom(backgroundColor: kPrimary),
          child: const Text('重试'),
        ),
      ],
    );
  }
}
