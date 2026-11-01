// laundry/laundry_home_page.dart —— 洗衣服务首页（玻璃 UI）。
//
// 结构：余额卡 + 扫码启动按钮 + 当前订单跟踪卡。
// 流程：扫码识别设备 → 选套餐 → 创建订单 → 拉起支付宝（H5/SDK 串）→
//       轮询订单状态（预约/运行中每 5s 刷新）→ 启动/停止/取消。
// 最近订单 orderId 持久化（secure storage）：App 重启后自动恢复跟踪。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:glass_ui/theme.dart';
import 'package:glass_ui/widgets/glass_background.dart';
import 'package:glass_ui/widgets/glass_card.dart';
import 'package:glass_ui/widgets/glass_dialog.dart';
import 'package:glass_ui/widgets/glass_snackbar.dart';
import 'alipay_pay.dart';
import 'laundry_api_client.dart';
import 'laundry_auth_state.dart';
import 'laundry_device_prefs.dart';
import 'laundry_history_page.dart';
import 'laundry_login_page.dart';
import 'laundry_order_page.dart';

class LaundryHomePage extends ConsumerStatefulWidget {
  const LaundryHomePage({super.key});
  @override
  ConsumerState<LaundryHomePage> createState() => _LaundryHomePageState();
}

class _LaundryHomePageState extends ConsumerState<LaundryHomePage> {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kLastOrder = 'laundry_last_order';

  WasherOrder? _order; // 当前跟踪的订单
  bool _orderBusy = false; // 订单操作进行中
  Timer? _pollTimer;
  Timer? _remainTickTimer; // 本地每秒倒计时（运行中让剩余时间平滑走动）

  List<FavWasher> _favs = []; // 常用洗衣机（本地收藏）
  Map<String, List<String>> _deviceOrder = {}; // 分组内拖拽顺序
  bool _refreshingAll = false; // 下拉/按钮全量刷新中

  /// 剩余秒数通知器：倒计时每秒只重建「剩余时间」文本，不整页 setState。
  final ValueNotifier<int> _remainTickNotifier = ValueNotifier<int>(-1);
  final Map<String, WasherDeviceStatus> _favStatus = {}; // deviceNo → 在线状态
  bool _favStatusLoading = false;
  List<String> _groups = ['default']; // 收藏分组（'default' 系统分组）
  String _selectedGroup = 'default'; // 当前选中分组（default 为系统默认）

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gateLogin();
      _restoreLastOrder();
      _loadFavs();
      _loadGroups();
    });
  }

  Future<void> _loadFavs() async {
    final list = await LaundryDevicePrefs.loadFavs();
    final order = await LaundryDevicePrefs.loadDeviceOrder();
    if (mounted) {
      setState(() {
        _deviceOrder = order;
        _favs = _applyOrder(list, order);
      });
    }
    _loadFavStatus();
  }

  /// 按分组内保存的拖拽顺序排列（无记录的排后面）。
  List<FavWasher> _applyOrder(
    List<FavWasher> list,
    Map<String, List<String>> order,
  ) {
    List<FavWasher> sortGroup(List<FavWasher> items, String gid) {
      final saved = order[gid] ?? const [];
      final idx = <String, int>{
        for (var i = 0; i < saved.length; i++) saved[i]: i,
      };
      return [...items]..sort(
          (a, b) => (idx[a.deviceNo] ?? 1 << 30)
              .compareTo(idx[b.deviceNo] ?? 1 << 30),
        );
    }

    final byGroup = <String, List<FavWasher>>{};
    for (final f in list) {
      byGroup.putIfAbsent(f.groupId, () => []).add(f);
    }
    final result = <FavWasher>[];
    for (final entry in byGroup.entries) {
      result.addAll(sortGroup(entry.value, entry.key));
    }
    return result;
  }

  /// 拖拽排序：更新当前分组顺序并持久化（onReorderItem 已自动修正 newIndex）。
  Future<void> _reorderFavs(int oldIndex, int newIndex) async {
    final no = _visibleFavs;
    if (oldIndex < 0 || oldIndex >= no.length || newIndex < 0) return;
    final gid = _selectedGroup;
    final ids = [
      ...(_deviceOrder[gid] ??
          no.map((f) => f.deviceNo).where((d) => d.isNotEmpty)),
    ];
    final moved = no[oldIndex].deviceNo;
    ids.remove(moved);
    ids.insert(newIndex.clamp(0, ids.length), moved);
    setState(() {
      _deviceOrder = {..._deviceOrder, gid: ids};
      _favs = _applyOrder(_favs, _deviceOrder);
    });
    await LaundryDevicePrefs.saveDeviceOrder(_deviceOrder);
  }

  /// 全量刷新：余额 + 常用设备状态 + 当前订单。
  Future<void> _refreshAll() async {
    if (_refreshingAll) return;
    _refreshingAll = true;
    final o = _order;
    try {
      await Future.wait([
        _loadFavStatus(),
        if (o != null && !o.isFinished) _refreshOrder(),
      ]);
    } finally {
      _refreshingAll = false;
    }
  }

  /// 批量刷新常用设备状态：逐台走 scanWasherCode 轻量查询（不拉套餐）。
  /// 登录失效直接中止（交给其他流程处理），单台失败静默跳过。
  Future<void> _loadFavStatus() async {
    if (_favStatusLoading || _favs.isEmpty) return;
    if (!ref.read(laundryAuthProvider).loggedIn) return;
    _favStatusLoading = true;
    final api = ref.read(laundryApiProvider);
    final entries = <MapEntry<String, WasherDeviceStatus>>[];
    for (final f in _favs) {
      if (f.qrUrl.isEmpty) continue;
      try {
        final s = await api.fetchDeviceStatus(f.qrUrl);
        entries.add(MapEntry(f.deviceNo, s));
      } on LaundryException catch (e) {
        if (e.authInvalid) break;
      } catch (_) {
        // 单台查询失败忽略，徽标不显示
      }
    }
    _favStatusLoading = false;
    if (!mounted) return;
    setState(() {
      _favStatus
        ..clear()
        ..addEntries(entries);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _remainTickTimer?.cancel();
    super.dispose();
  }

  // ===== 登录守卫 =====

  void _gateLogin() {
    final auth = ref.read(laundryAuthProvider);
    if (auth.restored && !auth.loggedIn) _toLogin();
  }

  void _toLogin() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LaundryLoginPage()),
    );
  }

  // ===== 订单跟踪 =====

  Future<void> _restoreLastOrder() async {
    if (!ref.read(laundryAuthProvider).loggedIn) return;
    try {
      final last = await _storage.read(key: _kLastOrder);
      if (last == null || last.isEmpty) return;
      final order = await ref.read(laundryApiProvider).fetchOrder(last);
      if (!mounted) return;
      if (order.isFinished) {
        await _storage.delete(key: _kLastOrder);
        return;
      }
      setState(() => _order = order);
      _updatePolling();
    } catch (_) {
      // 恢复失败静默（订单可能已完结/被清）
    }
  }

  void _updatePolling() {
    _pollTimer?.cancel();
    _remainTickTimer?.cancel();
    final o = _order;
    if (o == null || o.isFinished) return;
    // 运行中/已预约：本地每秒递减剩余时间，让倒计时平滑走动（5s 轮询负责校准真实值）
    if (o.status == WasherOrder.statusRunning ||
        o.status == WasherOrder.statusReserved) {
      _remainTickTimer =
          Timer.periodic(const Duration(seconds: 1), (_) => _tickRemain());
    }
    // 待支付不自动轮询（用户操作驱动），预约/启动中/运行中每 5s 刷新
    if (o.canPay) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshOrder());
  }

  /// 把当前订单的剩余秒数同步给通知器（剩余时间文本只重建这一小块）。
  void _syncRemain() {
    final o = _order;
    final secs = o == null || o.isFinished || o.canPay
        ? -1
        : (o.remainTimeSeconds > 0 ? o.remainTimeSeconds : o.countDownSeconds);
    _remainTickNotifier.value = secs;
  }

  /// 本地倒计时 tick：只更新通知器（不整页 setState）；
  /// 真实订单到 0 后由轮询校准。
  void _tickRemain() {
    final o = _order;
    if (o == null) {
      _remainTickTimer?.cancel();
      return;
    }
    final v = _remainTickNotifier.value;
    if (v <= 0) {
      _remainTickTimer?.cancel();
      return;
    }
    _remainTickNotifier.value = v - 1;
  }

  Future<void> _refreshOrder() async {
    final o = _order;
    if (o == null || _orderBusy) return;
    try {
      final fresh = await ref.read(laundryApiProvider).fetchOrder(o.orderId);
      if (!mounted) return;
      setState(() => _order = fresh);
      _syncRemain();
      if (fresh.isFinished) {
        await _storage.delete(key: _kLastOrder);
        _pollTimer?.cancel();
        await LaundryDevicePrefs.addOrderHistory(fresh.orderId);
        if (mounted) {
          showGlassSnackBar(context, '洗衣已完成，可在「洗衣记录」查看');
          // 3 秒后自动收起订单卡，回到常用设备视图
          Future.delayed(const Duration(seconds: 3), () {
            if (!mounted) return;
            final o = _order;
            if (o != null &&
                o.orderId == fresh.orderId &&
                o.isFinished) {
              setState(() => _order = null);
              _syncRemain();
            }
          });
        }
      }
    } on LaundryException catch (e) {
      if (e.authInvalid && mounted) {
        await ref.read(laundryAuthProvider.notifier).clearAuth();
        _toLogin();
      }
    } catch (_) {
      // 轮询失败静默，下一轮再试
    }
  }

  Future<void> _trackOrder(String orderId) async {
    try {
      final order = await ref.read(laundryApiProvider).fetchOrder(orderId);
      if (!mounted) return;
      await _storage.write(key: _kLastOrder, value: orderId);
      setState(() => _order = order);
      _syncRemain();
      _updatePolling();
    } catch (e) {
      if (mounted) showGlassSnackBar(context, '订单查询失败: $e');
    }
  }

  // ===== 扫码 → 套餐 → 下单 =====

  Future<void> _startScan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _ScanPage()),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;
    // 手动输入的纯数字 CD 码在此归一化为完整链接
    _handleScanCode(_normalizeQr(code));
  }

  Future<void> _handleScanCode(String code) async {
    setState(() => _orderBusy = true);
    try {
      final api = ref.read(laundryApiProvider);
      final program = await api.scanWasher(code);
      if (!mounted) return;
      // 可用与否都进下单页：页内展示状态徽标，不可下单也能收藏
      final sel = await Navigator.of(context).push<LaundryOrderSelection>(
        MaterialPageRoute(
          builder: (_) => LaundryOrderPage(
            program: program,
            qrCode: code,
            initialInFavs: _favs.any(
              (f) =>
                  f.qrUrl == code || f.deviceNo == washerDisplayNo(program, code),
            ),
          ),
        ),
      );
      // 下单页收藏开关即时生效，回来刷新列表与状态徽标
      if (mounted) {
        _loadFavs();
      }
      if (sel == null || !mounted) return;
      final orderId = await api.createOrder(
        washModelId: sel.modelId,
        temperatureId: sel.temperatureId,
        detergentGearId: sel.detergentGearId,
        disinfectantGearId: sel.disinfectantGearId,
      );
      if (!mounted) return;
      showGlassSnackBar(context, '订单已创建，去支付');
      await _trackOrder(orderId);
      await _payOrder();
    } on LaundryException catch (e) {
      if (!mounted) return;
      if (e.authInvalid) {
        await ref.read(laundryAuthProvider.notifier).clearAuth();
        _toLogin();
      } else {
        showGlassSnackBar(context, e.message);
      }
    } catch (e) {
      if (mounted) showGlassSnackBar(context, '操作失败: $e');
    } finally {
      if (mounted) setState(() => _orderBusy = false);
      // 下单/支付后设备状态可能变化（空闲 → 使用中），静默刷新常用设备徽标
      _loadFavStatus();
    }
  }

  // ===== 订单操作 =====

  Future<void> _payOrder() async {
    final o = _order;
    if (o == null || !o.canPay) return;
    setState(() => _orderBusy = true);
    try {
      final args = await ref.read(laundryApiProvider).fetchPaymentArgs(o.orderId);
      if (!mounted) return;
      // 服务端下发 h5_url 时直接外跳 H5 收银；否则用 orderInfo 走原生支付宝 SDK。
      if (args.h5Url.isNotEmpty) {
        final uri = Uri.parse(args.h5Url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (!mounted) return;
          showGlassSnackBar(context, '已跳转支付宝，支付完成后回来查看状态');
          await Future.delayed(const Duration(seconds: 3));
          await _trackOrder(o.orderId);
          return;
        }
        throw const LaundryException('无法打开支付宝链接');
      }
      if (args.orderInfo.isEmpty) {
        throw const LaundryException('服务端未返回支付宝支付参数');
      }
      // 原生 PayTask 拉起收银台（对齐参考项目：channel ujing/alipay）
      final pay = await AlipayPay.payV2(args.orderInfo);
      if (!mounted) return;
      switch (pay.status) {
        case '9000':
          showGlassSnackBar(context, '支付成功');
          break;
        case '8000':
          showGlassSnackBar(context, '支付处理中，确认后自动更新状态');
          break;
        case '6001':
          showGlassSnackBar(context, '已取消支付');
          break;
        case 'NO_PLUGIN':
        case 'PAY_ERROR':
          showGlassSnackBar(context, pay.message);
          break;
        default:
          showGlassSnackBar(context, '支付未完成（${pay.status}）');
      }
      await _trackOrder(o.orderId);
    } on LaundryException catch (e) {
      if (mounted) showGlassSnackBar(context, e.message);
    } catch (e) {
      if (mounted) showGlassSnackBar(context, '支付失败: $e');
    } finally {
      if (mounted) setState(() => _orderBusy = false);
    }
  }

  Future<void> _startOrder() async {
    final o = _order;
    if (o == null || _orderBusy) return;
    setState(() => _orderBusy = true);
    try {
      final fresh = await ref.read(laundryApiProvider).startOrder(o.orderId);
      if (!mounted) return;
      setState(() => _order = fresh);
      _syncRemain();
      showGlassSnackBar(context, '已发送启动指令');
      _updatePolling();
    } on LaundryException catch (e) {
      if (mounted) showGlassSnackBar(context, e.message);
    } catch (e) {
      if (mounted) showGlassSnackBar(context, '启动失败: $e');
    } finally {
      if (mounted) setState(() => _orderBusy = false);
    }
  }

  Future<void> _stopOrder() async {
    final o = _order;
    if (o == null || _orderBusy) return;
    final ok = await GlassDialog.showConfirm(
      context,
      title: '提前停止',
      message: '确定要提前结束本次洗衣吗？剩余费用可能不予退还。',
      accentColor: kLaundryDeep,
      confirmText: '停止',
    );
    if (ok != true || !mounted) return;
    setState(() => _orderBusy = true);
    try {
      final fresh = await ref.read(laundryApiProvider).stopOrder(o.orderId);
      if (!mounted) return;
      setState(() => _order = fresh);
      _syncRemain();
      showGlassSnackBar(context, '已发送停止指令');
      _updatePolling();
    } on LaundryException catch (e) {
      if (mounted) showGlassSnackBar(context, e.message);
    } catch (e) {
      if (mounted) showGlassSnackBar(context, '停止失败: $e');
    } finally {
      if (mounted) setState(() => _orderBusy = false);
    }
  }

  Future<void> _cancelOrder() async {
    final o = _order;
    if (o == null || _orderBusy) return;
    final ok = await GlassDialog.showConfirm(
      context,
      title: '取消订单',
      message: '确定取消该洗衣订单吗？',
      accentColor: kLaundryDeep,
      confirmText: '取消订单',
    );
    if (ok != true || !mounted) return;
    setState(() => _orderBusy = true);
    try {
      await ref.read(laundryApiProvider).cancelOrder(o.orderId);
      if (!mounted) return;
      await _storage.delete(key: _kLastOrder);
      _pollTimer?.cancel();
      setState(() => _order = null);
      _syncRemain();
      await LaundryDevicePrefs.addOrderHistory(o.orderId);
      if (mounted) showGlassSnackBar(context, '订单已取消');
    } on LaundryException catch (e) {
      if (mounted) showGlassSnackBar(context, e.message);
    } catch (e) {
      if (mounted) showGlassSnackBar(context, '取消失败: $e');
    } finally {
      if (mounted) setState(() => _orderBusy = false);
    }
  }

  // ===== UI =====

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refreshAll,
            backgroundColor: Colors.white,
            color: kLaundryDeep,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _topBar(),
                  const SizedBox(height: 14),
                  _scanButton(),
                  const SizedBox(height: 14),
                  if (_order != null) _orderCard(),
                  if (_order == null) ...[
                    if (_favs.isNotEmpty) ...[
                      _groupTabs(),
                      if (_visibleFavs.isEmpty)
                        _emptyGroupHint()
                      else
                        ReorderableListView(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          buildDefaultDragHandles: true,
                          proxyDecorator: (child, index, animation) =>
                              ScaleTransition(
                            scale: Tween<double>(begin: 1, end: 1.03)
                                .animate(animation),
                            child: child,
                          ),
                          onReorderItem: _reorderFavs,
                          children: [
                            for (final f in _visibleFavs)
                              Container(
                                key: ValueKey('fav_${f.deviceNo}'),
                                child: _favCard(f),
                              ),
                          ],
                        ),
                      const SizedBox(height: 10),
                    ],
                    // 扫码引导卡只在没有常用设备时展示（有设备后卡片即入口）
                    if (_favs.isEmpty) _emptyHint(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Row(
      children: [
        // 返回按钮（全局玻璃小卡样式）
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: kLaundryDeep,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kLaundry,
            boxShadow: [
              BoxShadow(
                color: kLaundryDeep.withValues(alpha: 0.22),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.local_laundry_service_rounded,
            size: 22,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            '洗衣服务',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: kInk,
            ),
          ),
        ),
        _smallPill(
          icon: Icons.receipt_long_rounded,
          label: '洗衣记录',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LaundryHistoryPage()),
          ),
        ),
        const SizedBox(width: 6),
        _smallPill(icon: Icons.logout_rounded, label: '退出', onTap: _logout),
      ],
    );
  }

  Future<void> _logout() async {
    final ok = await GlassDialog.showConfirm(
      context,
      title: '退出登录',
      message: '退出后将清除本机洗衣登录凭证，下次需要重新登录。',
      accentColor: kLaundryDeep,
      confirmText: '退出',
    );
    if (ok != true || !mounted) return;
    _pollTimer?.cancel();
    await ref.read(laundryAuthProvider.notifier).logout();
    if (mounted) {
      setState(() => _order = null);
    }
  }

  Widget _smallPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withValues(alpha: 0.5),
          border: Border.all(color: kGlassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: kTextMuted),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: kTextMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scanButton() {
    // 对齐饮水模块「扫码取水」大卡：图标容器 + 主副标题 + 尾部箭头
    return GestureDetector(
      onTap: _orderBusy ? null : _startScan,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: kLaundryDeep.withValues(alpha: 0.3),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kLaundry, kLaundryDeep],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
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
                      '扫码洗衣',
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
    );
  }

  /// 二维码内容归一化：完整链接原样；纯数字 CD 码自动拼接 U净链接。
  String _normalizeQr(String input) {
    final s = input.trim();
    if (s.startsWith('http') || s.contains('ujing')) return s;
    if (RegExp(r'^\d{8,}$').hasMatch(s)) {
      return 'https://q.ujing.com.cn/ucqrc/index.html?cd=$s';
    }
    return s;
  }

  // ===== 收藏分组 + 设备管理（对齐饮水模块能力） =====

  Future<void> _loadGroups() async {
    final groups = await LaundryDevicePrefs.loadGroups();
    if (mounted) setState(() => _groups = groups);
  }

  List<FavWasher> get _visibleFavs =>
      _favs.where((f) => f.groupId == _selectedGroup).toList();

  /// 分组显示名：default → 默认分组。
  String _groupName(String g) => g == 'default' ? '默认分组' : g;

  /// 分组 tab 行：各分组 + 分组管理入口。
  Widget _groupTabs() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final g in _groups) _groupTab(g),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '长按拖动排序',
            style: TextStyle(fontSize: 11, color: kTextMuted),
          ),
          const SizedBox(width: 8),
          _smallPill(
            icon: Icons.tune_rounded,
            label: '分组',
            onTap: _manageGroups,
          ),
        ],
      ),
    );
  }

  Widget _groupTab(String g) {
    final selected = _selectedGroup == g;
    final count = _favs.where((f) => f.groupId == g).length;
    return GestureDetector(
      onTap: () => setState(() => _selectedGroup = g),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected
              ? kLaundryDeep.withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: 0.5),
          border: Border.all(
            color: selected
                ? kLaundryDeep.withValues(alpha: 0.4)
                : kGlassBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _groupName(g),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : kTextMain,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: selected
                    ? Colors.white.withValues(alpha: 0.8)
                    : kTextMuted.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyGroupHint() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        radius: 18,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
        child: Text(
          '该分组暂无常用洗衣机，长按设备卡可移动分组',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            color: kTextMuted.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }

  /// 分组管理：新建 / 重命名 / 删除（删除时设备移回默认分组）。
  Future<void> _manageGroups() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        List<String> sheetGroups = List.from(_groups);
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> refresh() async {
              sheetGroups = await LaundryDevicePrefs.loadGroups();
              setSheetState(() {});
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              child: GlassCard(
                radius: 20,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: kInk,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              size: 17,
                              color: kTextMuted.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _sheetAction(
                      Icons.create_new_folder_rounded,
                      '新建分组',
                      onTap: () async {
                        final name = await _textInputDialog('新建分组', '');
                        if (name == null || name.isEmpty) return;
                        final ok = await LaundryDevicePrefs.addGroup(name);
                        if (!ok) {
                          if (mounted) showGlassSnackBar(context, '分组名重复或无效');
                          return;
                        }
                        await refresh();
                      },
                    ),
                    for (final g in sheetGroups) _groupManageRow(g, refresh),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (!mounted) return;
    final gs = await LaundryDevicePrefs.loadGroups();
    final fs = await LaundryDevicePrefs.loadFavs();
    if (!mounted) return;
    setState(() {
      _groups = gs;
      _favs = fs;
      // 当前选中的分组被删/改名后回落到系统默认分组
      if (!gs.contains(_selectedGroup)) {
        _selectedGroup = 'default';
      }
    });
  }

  Widget _groupManageRow(String g, Future<void> Function() refresh) {
    final count = _favs.where((f) => f.groupId == g).length;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.5),
        border: Border.all(color: kGlassBorder),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_rounded,
            size: 16,
            color: kLaundryDeep.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _groupName(g),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: kTextMain,
              ),
            ),
          ),
          Text(
            '$count 台',
            style: TextStyle(
              fontSize: 11,
              color: kTextMuted.withValues(alpha: 0.8),
            ),
          ),
          if (g != 'default') ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () async {
                final name = await _textInputDialog('重命名分组', g);
                if (name == null || name.isEmpty) return;
                await LaundryDevicePrefs.renameGroup(g, name);
                await refresh();
              },
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(
                  Icons.edit_note_rounded,
                  size: 17,
                  color: kLaundryDeep.withValues(alpha: 0.8),
                ),
              ),
            ),
            GestureDetector(
              onTap: () async {
                final ok = await GlassDialog.showConfirm(
                  context,
                  title: '删除分组',
                  message: '「$g」内的设备将移回默认分组，确定删除？',
                  confirmText: '删除',
                  destructive: true,
                );
                if (ok != true) return;
                await LaundryDevicePrefs.deleteGroup(g);
                await refresh();
              },
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 17,
                  color: kTextMuted.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 设备长按操作：重命名 / 移动到分组 / 移除。
  Future<void> _deviceActions(FavWasher f) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassCard(
          radius: 20,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                f.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: kInk,
                ),
              ),
              const SizedBox(height: 4),
              _sheetAction(
                Icons.edit_note_rounded,
                '重命名设备',
                onTap: () => Navigator.pop(ctx, 'rename'),
              ),
              _sheetAction(
                Icons.drive_file_move_rounded,
                '移动到分组',
                onTap: () => Navigator.pop(ctx, 'move'),
              ),
              _sheetAction(
                Icons.delete_outline_rounded,
                '移除常用',
                color: kWeekend,
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'rename':
        await _renameDevice(f);
        break;
      case 'move':
        await _moveDevice(f);
        break;
      case 'remove':
        await _removeFav(f);
        break;
    }
  }

  Widget _sheetAction(
    IconData icon,
    String label, {
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withValues(alpha: 0.5),
          border: Border.all(color: kGlassBorder),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 17,
              color: color ?? kLaundryDeep.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color ?? kTextMain,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameDevice(FavWasher f) async {
    final name = await _textInputDialog('重命名设备', f.customName);
    if (name == null || !mounted) return;
    final list =
        await LaundryDevicePrefs.updateDevice(f.deviceNo, customName: name);
    if (mounted) setState(() => _favs = list);
  }

  Future<void> _moveDevice(FavWasher f) async {
    final target = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassCard(
          radius: 20,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '移动「${f.displayName}」到',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: kInk,
                ),
              ),
              const SizedBox(height: 4),
              for (final g in _groups)
                _sheetAction(
                  g == f.groupId
                      ? Icons.folder_rounded
                      : Icons.folder_outlined,
                  _groupName(g),
                  onTap: () => Navigator.pop(ctx, g),
                ),
            ],
          ),
        ),
      ),
    );
    if (target == null || target == f.groupId || !mounted) return;
    final list =
        await LaundryDevicePrefs.updateDevice(f.deviceNo, groupId: target);
    if (mounted) setState(() => _favs = list);
  }

  Future<void> _removeFav(FavWasher f) async {
    final ok = await GlassDialog.showConfirm(
      context,
      title: '移除常用洗衣机',
      message: '将「${f.displayName}」从常用列表移除？',
      confirmText: '移除',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    final list = await LaundryDevicePrefs.remove(f.deviceNo);
    if (mounted) setState(() => _favs = list);
  }

  /// 通用文本输入弹窗（重命名/新建分组共用）。返回输入内容，取消返回 null。
  Future<String?> _textInputDialog(String title, String initial) {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController(text: initial);
        return GlassDialog(
          title: title,
          accentColor: kLaundryDeep,
          content: _textField('输入名称', c),
          cancelText: '取消',
          confirmText: '确定',
          onConfirm: () => Navigator.of(ctx).pop(c.text.trim()),
        );
      },
    );
  }

  Widget _textField(String hint, TextEditingController c) {
    return TextField(
      controller: c,
      autofocus: true,
      style: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: kTextMain,
      ),
      decoration: _inputDecoration(hint),
    );
  }

  /// 统一输入框样式（手动输入设备码 / 重命名等共用）。
  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontSize: 12.5,
        color: kTextMuted.withValues(alpha: 0.7),
      ),
      isDense: true,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: kLaundryDeep.withValues(alpha: 0.55),
          width: 1.4,
        ),
      ),
    );
  }

  /// 常用洗衣机卡：点「去洗衣」直接进下单流程；长按弹出重命名/移动分组/移除；行尾快捷删除。
  Widget _favCard(FavWasher f) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        // 整卡可点直达下单页（与「去洗衣」同路径）；长按留给拖拽排序
        onTap: _orderBusy
            ? null
            : () => _handleScanCode(_normalizeQr(f.qrUrl)),
        child: GlassCard(
          radius: 18,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          // 列表卡用静态磨砂（性能规则：滚动列表禁用实时模糊）
          live: false,
          opacity: kFrostAlpha,
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      kLaundry.withValues(alpha: 0.55),
                      kLaundry.withValues(alpha: 0.16),
                    ],
                  ),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.55)),
                ),
                child: Icon(
                  Icons.local_laundry_service_outlined,
                  size: 19,
                  color: kLaundryDeep.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: kTextMain,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      f.typeName.isEmpty
                          ? f.storeName
                          : '${f.typeName} · ${f.storeName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: kTextMuted.withValues(alpha: 0.8),
                      ),
                    ),
                    // 在线状态徽标（进入页面/下单后静默刷新）
                    if (_favStatus[f.deviceNo] != null) ...[
                      const SizedBox(height: 3),
                      _favStatusBadge(_favStatus[f.deviceNo]!),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _orderBusy
                    ? null
                    : () => _handleScanCode(_normalizeQr(f.qrUrl)),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: kLaundryDeep.withValues(alpha: 0.9),
                  ),
                  child: const Text(
                    '去洗衣',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // 编辑按钮（粉调，白卡上清晰可辨）
              GestureDetector(
                onTap: () => _deviceActions(f),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: kLaundry.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: kLaundryDeep.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Icon(
                    Icons.edit_note_rounded,
                    size: 18,
                    color: kLaundryDeep,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 常用设备状态小徽标：绿点 = 空闲可下单，粉红点 + 服务端原因 = 不可用（离线/使用中等）。
  Widget _favStatusBadge(WasherDeviceStatus s) {
    final ok = s.available;
    final color = ok ? const Color(0xFF3E9B6C) : kWeekend;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: ok ? 0.9 : 0.8),
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            s.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.95),
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyHint() {
    return GlassCard(
      radius: 20,
      width: double.infinity, // stretch 布局下 GlassCard 内部 shrink-wrap 会贴左，强制全宽保证内容居中
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      child: Column(
        children: [
          // 柔光渐变圆底图标（对齐全局装饰图标风格）
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  kLaundry.withValues(alpha: 0.5),
                  kLaundry.withValues(alpha: 0.12),
                ],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
            ),
            child: Icon(
              Icons.local_laundry_service_outlined,
              size: 30,
              color: kLaundryDeep.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '扫描洗衣机机身上的二维码开始洗衣',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: kTextMuted.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderCard() {
    final o = _order!;
    return GlassCard(
        radius: 20,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '洗衣机 ${o.deviceNo.isEmpty ? o.orderId : o.deviceNo}',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: kTextMain,
                    ),
                  ),
                ),
                _statusBadge(o),
              ],
            ),
            const SizedBox(height: 12),
            // 状态详情（剩余时间用通知器驱动，每秒只重建该文本）
            Row(
              children: [
                Expanded(
                  child: o.canPay || o.isFinished
                      ? _orderInfoCell(
                          o.canPay ? '应付金额' : '支付金额',
                          o.payPrice.isEmpty ? '--' : o.payPrice,
                        )
                      : ValueListenableBuilder<int>(
                          valueListenable: _remainTickNotifier,
                          builder: (context, v, _) => _orderInfoCell(
                            '剩余时间',
                            _formatRemainSecs(v),
                          ),
                        ),
                ),
                Container(
                  width: 1,
                  height: 26,
                  color: kGlassGridLine,
                ),
                Expanded(
                  child: _orderInfoCell('订单状态', o.statusText.isEmpty ? '--' : o.statusText),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 操作按钮
            _orderActions(o),
          ],
        ),
    );
  }

  String _formatRemainSecs(int secs) {
    if (secs <= 0) return '--';
    final m = secs ~/ 60;
    final s = secs % 60;
    return '$m 分 ${s.toString().padLeft(2, '0')} 秒';
  }

  Widget _orderInfoCell(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: kTextMuted.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: kTextMain,
          ),
        ),
      ],
    );
  }

  Widget _statusBadge(WasherOrder o) {
    Color bg;
    Color fg;
    String text;
    switch (o.status) {
      case WasherOrder.statusPendingPay:
        bg = Colors.orange.withValues(alpha: 0.15);
        fg = Colors.orange.shade800;
        text = '待支付';
        break;
      case WasherOrder.statusReserved:
        bg = kPrimaryContainer;
        fg = kInk;
        text = '已预约';
        break;
      case WasherOrder.statusStarting:
        bg = kPrimaryContainer;
        fg = kInk;
        text = '启动中';
        break;
      case WasherOrder.statusRunning:
        bg = Colors.green.withValues(alpha: 0.14);
        fg = Colors.green.shade800;
        text = '运行中';
        break;
      case WasherOrder.statusDone:
        bg = kTextMuted.withValues(alpha: 0.12);
        fg = kTextMuted;
        text = '已完成';
        break;
      default:
        bg = kTextMuted.withValues(alpha: 0.12);
        fg = kTextMuted;
        text = o.statusText.isEmpty ? o.status : o.statusText;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: bg,
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _orderActions(WasherOrder o) {
    final children = <Widget>[];
    if (o.canPay) {
      children
        ..add(_actionButton('去支付', kLaundryDeep, _payOrder))
        ..add(_actionButton('取消订单', null, _cancelOrder));
    } else if (o.canStart) {
      children
        ..add(_actionButton('启动洗衣机', kLaundryDeep, _startOrder))
        ..add(_actionButton('取消订单', null, _cancelOrder));
    } else if (o.canStop) {
      children.add(_actionButton('提前停止', null, _stopOrder));
    } else if (o.isFinished) {
      children.add(_actionButton('完成，扫下一单', kLaundryDeep, _startScan));
    } else {
      children.add(_actionButton('刷新状态', null, () => _trackOrder(o.orderId)));
    }
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: children[i]),
        ],
      ],
    );
  }

  Widget _actionButton(String text, Color? solid, VoidCallback onTap) {
    return GestureDetector(
      onTap: _orderBusy ? null : onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: solid ?? Colors.white.withValues(alpha: 0.6),
          border: solid == null ? Border.all(color: kGlassBorder) : null,
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: solid != null ? Colors.white : kTextMain,
          ),
        ),
      ),
    );
  }
}

// ===== 扫码页 =====

class _ScanPage extends StatefulWidget {
  const _ScanPage();
  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage>
    with SingleTickerProviderStateMixin {
  final _controller = MobileScannerController();
  final _manualCtrl = TextEditingController();
  bool _handled = false;
  bool _torch = false;
  bool _manualMode = false; // 与饮水模块一致：扫码识别 / 手动输入切换
  // 扫描线上下往复动画
  late final AnimationController _line = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _line.dispose();
    _controller.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  Future<void> _setMode(bool manual) async {
    if (_manualMode == manual) return;
    setState(() => _manualMode = manual);
    // 相机不 stop/start（黑屏根源）：仅 Offstage 隐藏，画面由系统继续供帧
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || _manualMode) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        _handled = true;
        Navigator.pop(context, raw.trim());
        return;
      }
    }
  }

  void _submitManual() {
    final code = _manualCtrl.text.trim();
    if (code.isEmpty) return;
    Navigator.pop(context, code);
  }

  static const double _frameSize = 240;

  @override
  Widget build(BuildContext context) {
    // 对齐饮水添加设备页：浅色玻璃页 + 顶栏 + 模式切换 + 圆角相机卡/输入卡
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 17,
                          color: kLaundryDeep,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _manualMode ? '手动输入设备码' : '扫描洗衣机二维码',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: kInk,
                      ),
                    ),
                  ],
                ),
              ),
              // 模式切换（对齐饮水添加设备页）
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    _modeChip(
                      '扫码识别',
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Stack(
                    children: [
                      // Offstage 保树：相机实例常驻，切回扫码不黑屏
                      Offstage(
                        offstage: _manualMode,
                        child: _buildScanView(),
                      ),
                      if (_manualMode) _buildManualView(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 扫码视图：圆角相机卡（挖窗遮罩 + 四角括号 + 扫描线 + 手电筒）。
  Widget _buildScanView() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          ColoredBox(color: Colors.black.withValues(alpha: 0.25)),
          // 取景窗口外围暗化（框内全透明）
          Positioned.fill(
            child: CustomPaint(painter: _MaskPainter(frame: _frameSize)),
          ),
          // 取景框：四角括号 + 扫描线
          Center(
            child: SizedBox(
              width: _frameSize,
              height: _frameSize,
              child: Stack(
                children: [
                  CustomPaint(
                    size: const Size(_frameSize, _frameSize),
                    painter: _CornerPainter(),
                  ),
                  // 扫描线（粉彩渐变，上下往复）
                  AnimatedBuilder(
                    animation: _line,
                    builder: (ctx, _) => Positioned(
                      top: 14 + _line.value * (_frameSize - 28),
                      left: 18,
                      right: 18,
                      child: Container(
                        height: 2.5,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          gradient: LinearGradient(colors: [
                            kLaundry.withValues(alpha: 0),
                            kLaundry.withValues(alpha: 0.95),
                            kLaundry.withValues(alpha: 0),
                          ]),
                          boxShadow: [
                            BoxShadow(
                              color: kLaundry.withValues(alpha: 0.55),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 卡内底部：手电筒 + 提示
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    try {
                      await _controller.toggleTorch();
                      if (mounted) setState(() => _torch = !_torch);
                    } catch (_) {}
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _torch
                          ? kLaundry.withValues(alpha: 0.9)
                          : Colors.white.withValues(alpha: 0.14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Icon(
                      _torch
                          ? Icons.flashlight_on_rounded
                          : Icons.flashlight_off_rounded,
                      size: 21,
                      color: _torch ? Colors.white : Colors.white70,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '对准机身二维码即可自动识别',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 手动输入视图（对齐饮水添加设备页，浅色玻璃卡）。
  Widget _buildManualView() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.75)),
              ),
              child: TextField(
                controller: _manualCtrl,
                autofocus: true,
                keyboardType: TextInputType.url,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: kInk,
                ),
                cursorColor: kLaundryDeep,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 18),
                  hintText: '输入完整二维码链接或机身 CD 数字码',
                  hintStyle: TextStyle(
                    fontSize: 13.5,
                    color: kTextMuted,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _submitManual,
              child: Container(
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [kLaundry, kLaundryDeep],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kLaundryDeep.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Text(
                  '识别设备',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '支持粘贴 U净二维码链接；纯数字按机身 CD 码识别',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: kTextMuted),
            ),
          ],
        ),
      ),
    );
  }

  /// 模式切换 chip（对齐饮水添加设备页，浅色配色）。
  Widget _modeChip(
    String label,
    IconData icon,
    bool selected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? kLaundry.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected
                ? kLaundryDeep.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: selected ? kLaundryDeep : kTextMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? kLaundryDeep : kTextMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 取景框外围遮罩：挖出中央窗口。
class _MaskPainter extends CustomPainter {
  final double frame;
  _MaskPainter({required this.frame});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: frame,
      height: frame,
    );
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(24)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: .2));
  }

  @override
  bool shouldRepaint(covariant _MaskPainter old) => old.frame != frame;
}

/// 取景框四角括号（粉彩白）。
class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const len = 26.0, w = 4.0, r = 24.0;
    final paint = Paint()
      ..color = kLaundry
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    void draw(Path path) => canvas.drawPath(path, paint);
    // 左上
    draw(
      Path()
        ..moveTo(0, r + len)
        ..lineTo(0, r)
        ..quadraticBezierTo(0, 0, r, 0)
        ..lineTo(r + len, 0),
    );
    // 右上
    draw(
      Path()
        ..moveTo(size.width - r - len, 0)
        ..lineTo(size.width - r, 0)
        ..quadraticBezierTo(size.width, 0, size.width, r)
        ..lineTo(size.width, r + len),
    );
    // 左下
    draw(
      Path()
        ..moveTo(0, size.height - r - len)
        ..lineTo(0, size.height - r)
        ..quadraticBezierTo(0, size.height, r, size.height)
        ..lineTo(r + len, size.height),
    );
    // 右下
    draw(
      Path()
        ..moveTo(size.width - r - len, size.height)
        ..lineTo(size.width - r, size.height)
        ..quadraticBezierTo(size.width, size.height, size.width, size.height - r)
        ..lineTo(size.width, size.height - r - len),
    );
  }

  @override
  bool shouldRepaint(covariant _CornerPainter old) => false;
}
