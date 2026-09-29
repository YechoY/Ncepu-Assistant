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

/// 设备运行状态（从 getDeviceStatus 的 gene.status 映射）
enum DeviceRuntimeStatus { idle, running, offline, unknown }

extension DeviceRuntimeStatusX on DeviceRuntimeStatus {
  String get label {
    switch (this) {
      case DeviceRuntimeStatus.idle:
        return '空闲';
      case DeviceRuntimeStatus.running:
        return '使用中';
      case DeviceRuntimeStatus.offline:
        return '离线';
      case DeviceRuntimeStatus.unknown:
        return '未知';
    }
  }

  Color get dotColor {
    switch (this) {
      case DeviceRuntimeStatus.idle:
        return const Color(0xFF5E9C80); // 柔绿
      case DeviceRuntimeStatus.running:
        return kHuish;
      case DeviceRuntimeStatus.offline:
        return const Color(0xFFB0B5C2); // 雾灰
      case DeviceRuntimeStatus.unknown:
        return const Color(0xFFD0D4DE); // 浅灰（加载中）
    }
  }

  static DeviceRuntimeStatus fromGeneStatus(int? status) {
    final s = status ?? -1;
    if (s == 99) return DeviceRuntimeStatus.idle;
    if (s == 1) return DeviceRuntimeStatus.running;
    return DeviceRuntimeStatus.offline;
  }
}

class HuishHomePage extends ConsumerStatefulWidget {
  const HuishHomePage({super.key});
  @override
  ConsumerState<HuishHomePage> createState() => _HuishHomePageState();
}

class _HuishHomePageState extends ConsumerState<HuishHomePage> {
  bool _loading = true;
  String? _error;
  List<dynamic> _devices = [];
  Map<String, DeviceRuntimeStatus> _statuses = {}; // did → 运行状态
  Map<String, DeviceCustomInfo> _customs = {};
  List<String> _groups = ['default'];
  final Set<String> _collapsed = {};
  Map<String, List<String>> _order = {}; // 分组内设备拖拽顺序
  Timer? _refreshTimer;
  // 一键取水
  String? _quickDeviceId;
  String? _quickDeviceName;
  bool _quickBusy = false;
  bool _quickOn = false; // 授权已开启（服务端 status 在实体键按下前仍为空闲）

  @override
  void initState() {
    super.initState();
    _loadQuickDevice();
    _load();
  }

  Future<void> _loadQuickDevice() async {
    _quickDeviceId = await DevicePrefs.getQuickDeviceId();
    _quickDeviceName = await DevicePrefs.getQuickDeviceName();
    _quickOn = await DevicePrefs.isQuickOn();
    if (mounted) setState(() {});
  }

  // 一键取水：选择快捷设备（从已有设备列表中选）
  Future<void> _pickQuickDevice() async {
    if (_devices.isEmpty) {
      showGlassSnackBar(context, '请先添加设备');
      return;
    }
    final grouped = _groupDevices();
    final allDevices = <MapEntry<String, String>>[]; // (id, name)
    for (final g in grouped.keys) {
      for (final d in grouped[g]!) {
        allDevices.add(MapEntry(_deviceId(d), _deviceName(d)));
      }
    }
    final selected = await showDialog<String>(
      context: context,
      barrierColor: const Color(0x402E3350),
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: _sheetContainer(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '选择一键取水设备',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: kInk,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '点击按钮即可远程授权出水，再点一次关闭',
                    style: TextStyle(fontSize: 12, color: kTextMuted),
                  ),
                  const SizedBox(height: 10),
                  ...allDevices.map((e) {
                    final isCurrent = e.key == _quickDeviceId;
                    return _sheetAction(
                      Icons.water_drop_outlined,
                      e.value,
                      () {
                        Navigator.of(ctx).pop(e.key);
                      },
                      color: isCurrent ? kPrimary : kInk,
                      trailing: isCurrent
                          ? const Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: kPrimary,
                            )
                          : null,
                    );
                  }),
                  if (_quickDeviceId != null) ...[
                    const SizedBox(height: 4),
                    _sheetAction(
                      Icons.link_off_rounded,
                      '取消绑定',
                      () => Navigator.of(ctx).pop('__clear__'),
                      color: const Color(0xFFB85450),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
    if (selected == null) return;
    if (selected == '__clear__') {
      await DevicePrefs.clearQuickDevice();
      await DevicePrefs.setQuickOn(false);
      _quickDeviceId = null;
      _quickDeviceName = null;
      _quickOn = false;
      if (mounted) showGlassSnackBar(context, '已取消一键取水绑定');
    } else {
      final name = allDevices.firstWhere((e) => e.key == selected).value;
      await DevicePrefs.setQuickDevice(selected, name);
      _quickDeviceId = selected;
      _quickDeviceName = name;
      if (mounted) showGlassSnackBar(context, '已绑定「$name」');
    }
    if (mounted) setState(() {});
  }

  // 一键取水：启动/停止
  Future<void> _quickToggle() async {
    final did = _quickDeviceId;
    if (did == null) {
      await _pickQuickDevice();
      return;
    }
    if (_quickBusy) return;
    setState(() => _quickBusy = true);
    try {
      final api = ref.read(huishApiClientProvider);
      // 先查当前状态
      final statusResp = await api.getDeviceStatus(did);
      if (!statusResp.isSuccess) {
        if (mounted) showGlassSnackBar(context, '设备不可用');
        return;
      }
      final device = statusResp.dataMap?['device'] as Map<String, dynamic>?;
      final gene = device?['gene'] as Map<String, dynamic>?;
      final rawStatus = gene?['status'] as int? ?? 99;
      // 本机刚停过 → 覆盖为空闲
      final effStatus =
          (rawStatus == 1 && await DevicePrefs.wasRecentlyStopped(did))
          ? 99
          : rawStatus;
      // 授权开着 or 设备在出水 → 应关闭；否则启动
      final shouldStop = _quickOn || effStatus == 1;

      if (shouldStop) {
        final resp = await api.stopDevice(did);
        if (!mounted) return;
        if (resp.isSuccess) {
          await DevicePrefs.clearActiveSession();
          await DevicePrefs.markStoppedByMe(did);
          await DevicePrefs.setQuickOn(false);
          setState(() => _quickOn = false);
          showGlassSnackBar(context, '已关闭取水');
        } else {
          // 停止被拒：若设备已不在出水（授权可能早已超时失效）→ 视为已关闭
          final recheck = await api.getDeviceStatus(did);
          final gene2 =
              (recheck.dataMap?['device'] as Map<String, dynamic>?)?['gene']
                  as Map<String, dynamic>?;
          final still = gene2?['status'] as int? ?? 99;
          if (recheck.isSuccess && still != 1) {
            await DevicePrefs.setQuickOn(false);
            setState(() => _quickOn = false);
            showGlassSnackBar(context, '取水已结束（授权已失效）');
          } else {
            showGlassSnackBar(context, _mapQuickError(resp.code));
          }
        }
      } else if (effStatus == 99) {
        // 空闲 → 启动（远程启动 = 授权，实体键按下后才开始出水）
        final resp = await api.startDevice(did);
        if (!mounted) return;
        if (resp.isSuccess) {
          await DevicePrefs.setQuickOn(true);
          setState(() => _quickOn = true); // 立即变色反馈
          showGlassSnackBar(context, '已开启取水授权，请在设备上按出水键');
        } else {
          showGlassSnackBar(context, _mapQuickError(resp.code));
        }
      } else {
        if (mounted) showGlassSnackBar(context, '设备离线，请稍后重试');
      }
      // 刷新状态
      await _load(silent: true);
    } catch (_) {
      if (mounted) showGlassSnackBar(context, '操作失败，请检查网络');
    } finally {
      if (mounted) setState(() => _quickBusy = false);
    }
  }

  String _mapQuickError(int code) {
    switch (code) {
      case -1:
        return '服务端拒绝：请升级最新app';
      case -52:
        return '账户欠费，请充值后使用';
      case -82:
        return '需要支付，请先完成支付';
      case -88:
        return '未签约代扣协议，请先完成签约';
      case -99:
        return '设备已被占用';
      default:
        return '操作失败 (code: $code)';
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    setState(() {
      if (!silent) _loading = true;
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
      // 默认所有分组展开
      setState(() {});
      // 并发查设备状态（3 并发上限，总超时 8s）
      _fetchStatuses(_devices.map(_deviceId).toList());
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  // 并发查询设备状态（3 并发上限，总超时 8s）
  Future<void> _fetchStatuses(List<String> dids) async {
    if (dids.isEmpty) return;
    final api = ref.read(huishApiClientProvider);
    final results = <String, DeviceRuntimeStatus>{};
    // 3 并发分批次
    for (var i = 0; i < dids.length; i += 3) {
      final batch = dids.skip(i).take(3).toList();
      final futures = batch.map((did) async {
        try {
          final resp = await api
              .getDeviceStatus(did)
              .timeout(
                const Duration(seconds: 8),
                onTimeout: () => throw TimeoutException('超时'),
              );
          if (!resp.isSuccess) {
            return MapEntry(did, DeviceRuntimeStatus.offline);
          }
          final device = resp.dataMap?['device'] as Map<String, dynamic>?;
          final gene = device?['gene'] as Map<String, dynamic>?;
          final status = gene?['status'] as int?;
          var result = DeviceRuntimeStatusX.fromGeneStatus(status);
          // 本机刚停过水 → 服务端状态滞后期间覆盖为"空闲"
          if (result == DeviceRuntimeStatus.running &&
              await DevicePrefs.wasRecentlyStopped(did)) {
            result = DeviceRuntimeStatus.idle;
          }
          return MapEntry(did, result);
        } catch (_) {
          return MapEntry(did, DeviceRuntimeStatus.offline);
        }
      });
      final batchResults = await Future.wait(futures);
      results.addEntries(
        batchResults.whereType<MapEntry<String, DeviceRuntimeStatus>>(),
      );
      if (!mounted) return;
      // 服务端确认在出水 → 同步点亮授权状态（如从别处启动的）
      if (_quickDeviceId != null &&
          results[_quickDeviceId] == DeviceRuntimeStatus.running &&
          !_quickOn) {
        _quickOn = true;
        DevicePrefs.setQuickOn(true);
      }
      setState(() => _statuses = {..._statuses, ...results});
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

  Future<void> _tapDevice(dynamic d) async {
    final id = _deviceId(d);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            HuishDevicePage(deviceId: id, deviceName: _deviceName(d)),
      ),
    );
    if (!mounted) return;
    await _load(silent: true); // 返回后刷新列表与设备状态（可能刚取水/停水）
  }

  Future<void> _addDevice() async {
    final r = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const HuishAddDevicePage()),
    );
    if (r == null || !mounted) return;
    final did = r['did'] as String? ?? '';
    if (did.isEmpty) return;
    final fav = r['fav'] as bool? ?? false;
    if (fav) await _load(silent: true); // 已收藏 → 刷新设备列表
    if (!mounted) return;
    // 扫码后直接进入取水页（无论是否收藏）
    final name = (r['name'] as String?) ?? _currentDeviceName(did);
    final inList = _devices.any((d) => _deviceId(d) == did);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HuishDevicePage(
          deviceId: did,
          deviceName: name,
          alreadyFav: inList,
        ),
      ),
    );
    if (!mounted) return;
    await _load(silent: true); // 返回后刷新（可能已收藏/已取水）
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
                    // 账户胶囊（显示当前登录手机号尾号，点击弹账户卡片）
                    Builder(
                      builder: (_) {
                        final auth = ref.watch(huishAuthStateProvider);
                        final phone = _maskPhone(auth.phone);
                        return GestureDetector(
                          onTap: _showAccountSheet,
                          child: Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.65),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.person_rounded,
                                  size: 15,
                                  color: kPrimary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  phone,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: kInk,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 16,
                                  color: kTextMuted,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
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
              // ── 底部一键取水按钮 ────────────────────────────────
              if (!_loading && _error == null) _buildQuickButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickButton() {
    final hasDevice = _quickDeviceId != null;
    final status = hasDevice ? _statuses[_quickDeviceId] : null;
    // 授权开着 或 设备在出水 → 都算"已开启"（远程启动只是授权，实体键按下前服务端仍报空闲）
    final isRunning = _quickOn || status == DeviceRuntimeStatus.running;
    final isOffline = status == DeviceRuntimeStatus.offline;

    // 未绑定 → 灰底"选择设备"；空闲 → 蓝底"一键取水"；使用中 → 红底"关闭取水"；离线 → 灰底"离线"
    final bgColor = !hasDevice
        ? const Color(0xFF8E99B0) // 未绑定灰
        : isRunning
        ? const Color(0xFFE0705A) // 使用中橙红
        : isOffline
        ? const Color(0xFFB0B5C2) // 离线灰
        : kHuish; // 空闲蓝
    final label = !hasDevice
        ? '选择设备'
        : isRunning
        ? '关闭取水'
        : isOffline
        ? '设备离线'
        : '一键取水';
    final icon = !hasDevice
        ? Icons.add_circle_outline_rounded
        : isRunning
        ? Icons.stop_rounded
        : isOffline
        ? Icons.cloud_off_rounded
        : Icons.water_drop_rounded;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 30), // 底部留大间距防误触
      child: GestureDetector(
        onTap: _quickBusy ? null : _quickToggle,
        onLongPress: _pickQuickDevice,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: kSpring,
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: bgColor.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [bgColor, bgColor.withValues(alpha: 0.82)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                if (_quickBusy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                else
                  Icon(icon, color: Colors.white, size: 21),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                if (hasDevice && _quickDeviceName != null) ...[
                  const SizedBox(width: 8),
                  // 设备名同行展示，右侧状态文字占空间后会自动省略
                  Expanded(
                    child: Text(
                      '· ${_quickDeviceName!}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white, // 纯白，看清
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else if (!hasDevice)
                  const SizedBox(width: 8),
                if (!hasDevice)
                  const Text(
                    '长按选设备',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                const Spacer(),
                // 右侧状态文字
                if (hasDevice)
                  Text(
                    isRunning
                        ? '使用中'
                        : isOffline
                        ? '离线'
                        : '空闲',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
              ],
            ),
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
                            status:
                                _statuses[_deviceId(d)] ??
                                DeviceRuntimeStatus.unknown,
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

  String _maskPhone(String? p) {
    if (p == null || p.length < 11) return '未登录';
    return '${p.substring(0, 3)}****${p.substring(7)}';
  }

  Future<void> _showAccountSheet() async {
    final auth = ref.read(huishAuthStateProvider);
    if (!auth.loggedIn) return;
    final mask = _maskPhone(auth.phone);
    showDialog(
      context: context,
      barrierColor: const Color(0x402E3350),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: _sheetContainer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: kHuish.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_rounded, color: kHuish),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mask,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: kInk,
                            ),
                          ),
                          Text(
                            'UID: ${auth.uid ?? '-'}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: kTextMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _sheetAction(Icons.logout_rounded, '退出登录', () {
                  Navigator.of(ctx).pop();
                  _logout();
                }, color: const Color(0xFFB85450)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetStat(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: kTextMuted)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: kInk,
            ),
          ),
        ],
      ),
    );
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
  final DeviceRuntimeStatus status;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  const _DeviceCard({
    required this.customName,
    required this.status,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = status == DeviceRuntimeStatus.offline;
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
                color: disabled
                    ? const Color(0xFFB0B5C2).withValues(alpha: 0.14)
                    : kHuish.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                Icons.water_drop_rounded,
                size: 22,
                color: disabled ? const Color(0xFFB0B5C2) : kHuish,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    customName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: disabled ? kTextMuted : kInk,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: status.dotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        status.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: status.dotColor,
                        ),
                      ),
                    ],
                  ),
                ],
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
                color: disabled
                    ? const Color(0xFFB0B5C2)
                    : (status == DeviceRuntimeStatus.running
                          ? const Color(0xFFB85450)
                          : kHuish),
                borderRadius: BorderRadius.circular(12),
                boxShadow: disabled
                    ? null
                    : [
                        BoxShadow(
                          color:
                              (status == DeviceRuntimeStatus.running
                                      ? const Color(0xFFB85450)
                                      : kHuish)
                                  .withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: Text(
                disabled
                    ? '离线'
                    : (status == DeviceRuntimeStatus.running ? '结束' : '取水'),
                style: const TextStyle(
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
