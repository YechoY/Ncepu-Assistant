// laundry/laundry_history_page.dart —— 洗衣记录页（本地历史）。
//
// U净 API 无订单列表接口，这里用本地记录的已完成 orderId
// （LaundryDevicePrefs.addOrderHistory，带完成时间）逐个拉详情展示。
// 顶部今日/本月消费统计（本地聚合已完成订单），点击条目查看详情。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:glass_ui/theme.dart';
import 'package:glass_ui/widgets/glass_background.dart';
import 'package:glass_ui/widgets/glass_card.dart';
import 'package:glass_ui/widgets/glass_dialog.dart';
import 'package:glass_ui/widgets/glass_info_row.dart';
import 'package:glass_ui/widgets/glass_page_header.dart';
import 'package:glass_ui/widgets/glass_stat_cards.dart';

import 'laundry_api_client.dart';
import 'laundry_auth_state.dart';
import 'laundry_device_prefs.dart';

class LaundryHistoryPage extends ConsumerStatefulWidget {
  const LaundryHistoryPage({super.key});

  @override
  ConsumerState<LaundryHistoryPage> createState() =>
      _LaundryHistoryPageState();
}

class _LaundryHistoryPageState extends ConsumerState<LaundryHistoryPage> {
  bool _loading = true;
  List<_HistoryItem> _items = [];

  int _balanceFen = -1; // -1 = 未加载/获取失败
  bool _loadingBalance = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _loadBalance();
    });
  }

  Future<void> _loadBalance() async {
    if (ref.read(laundryAuthProvider).loggedIn == false) return;
    setState(() => _loadingBalance = true);
    try {
      final fen = await ref.read(laundryApiProvider).fetchBalanceFen();
      if (mounted) setState(() => _balanceFen = fen);
    } catch (_) {
      if (mounted) setState(() => _balanceFen = -1);
    } finally {
      if (mounted) setState(() => _loadingBalance = false);
    }
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final ids = await LaundryDevicePrefs.loadOrderHistory();
    final api = ref.read(laundryApiProvider);
    final result = await Future.wait(
      [for (final (id, at) in ids) _fetchOne(api, id, at)],
    );
    if (!mounted) return;
    setState(() {
      _items = result;
      _loading = false;
    });
  }

  Future<_HistoryItem> _fetchOne(
    LaundryApiClient api,
    String orderId,
    DateTime? finishedAt,
  ) async {
    try {
      final o = await api.fetchOrder(orderId);
      return _HistoryItem(
        orderId: orderId,
        finishedAt: finishedAt,
        order: o,
        failed: false,
      );
    } catch (_) {
      return _HistoryItem(
        orderId: orderId,
        finishedAt: finishedAt,
        order: null,
        failed: true,
      );
    }
  }

  // ── 账户余额卡（对齐饮水账单页）────────────────────────

  Widget _balanceCard() {
    final balanceText = _balanceFen < 0
        ? '--'
        : '¥${(_balanceFen / 100).toStringAsFixed(2)}';
    return GlassBalanceCard(
      label: '账户余额',
      amount: balanceText,
      icon: Icons.account_balance_wallet_rounded,
      light: kLaundry,
      deep: kLaundryDeep,
      trailing: GestureDetector(
        onTap: _loadingBalance ? null : _loadBalance,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.55),
            border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
          ),
          child: _loadingBalance
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kLaundryDeep,
                  ),
                )
              : const Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: kLaundryDeep,
                ),
        ),
      ),
    );
  }

  // ── 今日 / 本月消费统计（本地聚合已完成订单）────────────

  /// payPrice 是「¥x.xx」格式化串，这里还原成分值再求和。
  (double today, double month) _calcStats() {
    final now = DateTime.now();
    double today = 0;
    double month = 0;
    for (final it in _items) {
      final o = it.order;
      if (o == null || !o.isFinished || it.finishedAt == null) continue;
      final fen =
          double.tryParse(o.payPrice.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;
      final t = it.finishedAt!;
      if (t.year == now.year && t.month == now.month) {
        month += fen;
        if (t.day == now.day) today += fen;
      }
    }
    return (today, month);
  }

  Widget _statsCard() {
    final (today, month) = _calcStats();
    return GlassStatsCard(
      stats: [
        GlassStat(
          icon: Icons.today_rounded,
          label: '今日消费',
          value: '¥${today.toStringAsFixed(2)}',
        ),
        GlassStat(
          icon: Icons.calendar_month_rounded,
          label: '本月消费',
          value: '¥${month.toStringAsFixed(2)}',
        ),
      ],
    );
  }

  // ── 详情弹窗 ──────────────────────────────────────────

  void _showDetail(_HistoryItem item) {
    final o = item.order;
    final at = item.finishedAt;
    final atStr = at == null || at.millisecondsSinceEpoch == 0
        ? ''
        : '${at.year}-${_two(at.month)}-${_two(at.day)} '
            '${_two(at.hour)}:${_two(at.minute)}';
    showDialog<void>(
      context: context,
      barrierColor: const Color(0x402E3350),
      builder: (_) => GlassDialog(
        title: '订单详情',
        accentColor: kLaundryDeep,
        confirmText: '知道了',
        cancelText: null,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassInfoRow(
              label: '设备',
              value: o == null || o.deviceNo.isEmpty
                  ? ''
                  : '洗衣机 ${o.deviceNo}',
            ),
            GlassInfoRow(label: '订单号', value: item.orderId),
            GlassInfoRow(label: '状态', value: o == null ? '查询失败' : o.statusText),
            GlassInfoRow(
              label: '金额',
              value: o == null || o.payPrice.isEmpty ? '' : o.payPrice,
            ),
            GlassInfoRow(label: '完成时间', value: atStr),
          ],
        ),
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const GlassPageHeader(title: '洗衣记录', accentColor: kLaundryDeep),
              if (!_loading && _items.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: _balanceCard(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: _statsCard(),
                ),
              ],
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: kLaundryDeep,
                          strokeWidth: 2.2,
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        backgroundColor: Colors.white,
                        color: kLaundryDeep,
                        child: _items.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(
                                    height:
                                        MediaQuery.sizeOf(context).height * .6,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.receipt_long_rounded,
                                          size: 46,
                                          color: kTextMuted.withValues(
                                            alpha: 0.4,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          '还没有洗衣记录\n完成一次洗衣后会自动记在这里',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            height: 1.6,
                                            color: kTextMuted
                                                .withValues(alpha: 0.75),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  12,
                                  20,
                                  24,
                                ),
                                itemCount: _items.length,
                                itemBuilder: (context, i) => _historyCard(
                                  _items[i],
                                ),
                              ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _historyCard(_HistoryItem item) {
    final o = item.order;
    final at = item.finishedAt;
    final statusText =
        o == null ? '查询失败' : (o.statusText.isEmpty ? '--' : o.statusText);
    final color = o == null
        ? kTextMuted
        : o.isFinished
            ? const Color(0xFF5E9C80)
            : o.canPay
                ? const Color(0xFFB07432)
                : kLaundryDeep;
    final atStr = at == null || at.millisecondsSinceEpoch == 0
        ? '时间未知'
        : '${at.year}-${_two(at.month)}-${_two(at.day)} '
            '${_two(at.hour)}:${_two(at.minute)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _showDetail(item),
        child: GlassCard(
          radius: 20,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          // 列表卡用静态磨砂（性能规则）
          live: false,
          opacity: kFrostAlpha,
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.12),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Icon(
                  o == null
                      ? Icons.help_outline_rounded
                      : o.isFinished
                          ? Icons.check_circle_outline_rounded
                          : Icons.local_laundry_service_outlined,
                  size: 22,
                  color: color,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o == null
                          ? '订单 ${item.orderId}'
                          : '洗衣机 ${o.deviceNo.isEmpty ? item.orderId : o.deviceNo}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: kTextMain,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '完成于 $atStr',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: kTextMuted.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '订单号 ${item.orderId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: kTextMuted.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    o == null || o.payPrice.isEmpty ? '--' : o.payPrice,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: kTextMain,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryItem {
  final String orderId;
  final DateTime? finishedAt;
  final WasherOrder? order;
  final bool failed;
  const _HistoryItem({
    required this.orderId,
    required this.finishedAt,
    required this.order,
    required this.failed,
  });
}
