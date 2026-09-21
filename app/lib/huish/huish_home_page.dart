// huish/huish_home_page.dart —— 饮水首页：扫码大按钮 + 分组设备列表 + 账单入口。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme.dart';
import '../../widgets/glass_background.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/glass_dialog.dart';
import '../../widgets/glass_snackbar.dart';
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
  Map<String, List<String>> _order = {}; // 分组内设备拖拽顺序
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
      _order = await DevicePrefs.loadDeviceOrder();
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
    // 组内按用户拖拽顺序排列
    result.forEach((g, list) {
      final ord = _order[g];
      if (ord == null || ord.isEmpty) return;
      int rank(dynamic d) {
        final i = ord.indexOf(_deviceId(d));
        return i < 0 ? 1 << 30 : i;
      }

      list.sort((a, b) => rank(a).compareTo(rank(b)));
    });
    // 空分组只留 default（其他空的不显示）
    result.removeWhere((k, v) => k != 'default' && v.isEmpty);
    return result;
  }

  // 长按拖拽排序：更新该组顺序并持久化（onReorderItem 已自动修正 newIndex）
  void _reorderDevices(
    String gid,
    List<dynamic> list,
    int oldIndex,
    int newIndex,
  ) {
    setState(() {
      final ids = list.map(_deviceId).toList();
      if (oldIndex < 0 ||
          oldIndex >= ids.length ||
          newIndex < 0 ||
          newIndex >= ids.length) {
        return;
      }
      final item = ids.removeAt(oldIndex);
      ids.insert(newIndex, item);
      _order = {..._order, gid: ids};
    });
    DevicePrefs.saveDeviceOrder(_order);
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
    final r = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const HuishAddDevicePage()),
    );
    if (r == null || !mounted) return;
    final did = r['did'] as String? ?? '';
    if (did.isEmpty) return;
    final fav = r['fav'] as bool? ?? false;
    if (fav) await _load(); // 已收藏 → 刷新设备列表
    if (!mounted) return;
    // 扫码后直接进入取水页（无论是否收藏）
    final name = (r['name'] as String?) ?? _currentDeviceName(did);
    final inList = _devices.any((d) => _deviceId(d) == did);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HuishDevicePage(
          deviceId: did,
          deviceName: name,
          alreadyFav: inList,
        ),
      ),
    );
  }

  String _currentDeviceName(String did) {
    for (final d in _devices) {
      if (_deviceId(d) == did) return _deviceName(d);
    }
    final custom = _customs[did];
    if (custom != null && custom.customName.isNotEmpty) {
      return custom.customName;
    }
    return '饮水机';
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

  // 删除设备（取消收藏 + 清本地偏好）
  Future<void> _deleteDevice(dynamic d) async {
    final id = _deviceId(d);
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x402E3350),
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('删除设备', style: TextStyle(fontSize: 16)),
        content: Text('将从设备列表移除「${_deviceName(d)}」，确定？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Color(0xFFB85450))),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final api = ref.read(huishApiClientProvider);
      final resp = await api.favoriteDevice(id, remove: true);
      if (!mounted) return;
      if (resp.isSuccess) {
        await DevicePrefs.removeDevice(id);
        _devices = _devices.where((e) => _deviceId(e) != id).toList();
        _customs = await DevicePrefs.loadDeviceCustoms();
        if (mounted) showGlassSnackBar(context, '已删除设备');
      } else if (mounted) {
        showGlassSnackBar(context, '删除失败 (code: ${resp.code})');
      }
    } catch (_) {
      if (mounted) showGlassSnackBar(context, '网络异常，请重试');
    }
    if (mounted) setState(() {});
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(icon, size: 21, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
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

  // 设备操作：重命名 / 移动到分组 / 删除（居中弹窗）
  Future<void> _showDeviceActions(dynamic d) async {
    final id = _deviceId(d);
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0x402E3350),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: _sheetContainer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '「${_deviceName(d)}」',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15.5,
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
                    style: TextStyle(fontSize: 12.5, color: kTextMuted),
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
                        ? const Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: kPrimary,
                          )
                        : null,
                  );
                }),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 8, 4, 6),
                  child: Text(
                    '更多操作',
                    style: TextStyle(fontSize: 12.5, color: kTextMuted),
                  ),
                ),
                _sheetAction(Icons.delete_outline_rounded, '删除设备', () {
                  Navigator.of(context).pop();
                  _deleteDevice(d);
                }, color: const Color(0xFFB85450)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 分组管理：新建 / 重命名 / 删除（居中弹窗）
  Future<void> _manageGroups() async {
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0x402E3350),
      builder: (dialogCtx) {
        List<String> sheetGroups = List.from(_groups);
        return StatefulBuilder(
          builder: (dialogCtx, setSheetState) {
            final grouped = _groupDevices();
            Future<void> refresh({bool close = false}) async {
              sheetGroups = await DevicePrefs.loadGroups();
              setSheetState(() {});
              setState(() {});
              if (close && dialogCtx.mounted) {
                Navigator.of(dialogCtx).pop();
              }
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: _sheetContainer(
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
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
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
                              await refresh(close: true); // 新建完成自动关闭
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
                                    size: 16,
                                    color: kPrimary,
                                  ),
                                  SizedBox(width: 3),
                                  Text(
                                    '新建',
                                    style: TextStyle(
                                      fontSize: 13,
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
                                    size: 21,
                                    color: kPrimary,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      isDefault ? '默认 ($count)' : '$g ($count)',
                                      style: const TextStyle(
                                        fontSize: 15,
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
                                          size: 20,
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
                                              borderRadius:
                                                  BorderRadius.circular(18),
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
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  false,
                                                ),
                                                child: const Text('取消'),
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  true,
                                                ),
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
                                          size: 20,
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
                ),
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
                    color: kHuish.withValues(alpha: 0.28),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kHuish, kHuishDeep],
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
                            '扫码取水',
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
              const Text(
                '长按拖动排序',
                style: TextStyle(fontSize: 11, color: kTextMuted),
              ),
              const SizedBox(width: 10),
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
                          size: 22,
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
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    buildDefaultDragHandles: true,
                    proxyDecorator: (child, index, animation) =>
                        ScaleTransition(
                          scale: Tween<double>(
                            begin: 1,
                            end: 1.04,
                          ).animate(animation),
                          child: child,
                        ),
                    onReorderItem: (oldIndex, newIndex) =>
                        _reorderDevices(gid, list, oldIndex, newIndex),
                    children: [
                      for (final d in list)
                        Padding(
                          key: ValueKey(_deviceId(d)),
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _DeviceCard(
                            customName: _deviceName(d),
                            onTap: () => _tapDevice(d),
                            onEdit: () => _showDeviceActions(d),
                          ),
                        ),
                    ],
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
      builder: (_) => const GlassDialog(
        title: '退出生活服务',
        content: Text(
          '退出将清除本地饮水登录信息，需要重新输入手机号验证码才能登录，确定吗？',
          style: TextStyle(fontSize: 12.5, height: 1.55, color: kTextMuted),
        ),
        cancelText: '取消',
        confirmText: '退出',
        destructive: true,
        popResult: true,
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
    return GestureDetector(
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
                color: kHuish.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.water_drop_rounded,
                size: 22,
                color: kHuish,
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
            GestureDetector(
              onTap: onEdit,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                child: const Icon(
                  Icons.edit_note_rounded,
                  size: 18,
                  color: kTextMuted,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
              decoration: BoxDecoration(
                color: kHuish,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: kHuish.withValues(alpha: 0.35),
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
