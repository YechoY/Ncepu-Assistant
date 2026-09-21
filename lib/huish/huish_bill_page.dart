// huish/huish_bill_page.dart —— 消费记录页（玻璃 UI）。
//
// 余额卡（钱包 olCash/olGift）+ 状态筛选 + 账单列表 + 详情弹窗。
// MVP 不做充值/签约，只读展示。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme.dart';
import '../../widgets/glass_background.dart';
import '../../widgets/glass_card.dart';
import 'huish_auth_state.dart';

class HuishBillPage extends ConsumerStatefulWidget {
  const HuishBillPage({super.key});
  @override
  ConsumerState<HuishBillPage> createState() => _HuishBillPageState();
}

class _HuishBillPageState extends ConsumerState<HuishBillPage> {
  bool _loading = true;
  String? _error;
  List<dynamic> _bills = [];

  // 钱包
  bool _walletLoading = true;
  double _cash = 0;
  double _gift = 0;
  String _epName = '';

  int? _statusFilter; // null=全部 1=未付款 2=待确认 3=已付款 4=失败 9=已取消

  static const Map<int, _StatusStyle> _statusStyles = {
    1: _StatusStyle('未付款', Color(0xFFB07432)),
    2: _StatusStyle('待确认', Color(0xFF4A7FB5)),
    3: _StatusStyle('已付款', Color(0xFF5E9C80)),
    4: _StatusStyle('失败', Color(0xFFB85450)),
    9: _StatusStyle('已取消', Color(0xFF8A93A6)),
  };

  static const _filters = <int?, String>{
    null: '全部',
    1: '未付款',
    2: '待确认',
    3: '已付款',
    4: '失败',
    9: '已取消',
  };

  @override
  void initState() {
    super.initState();
    _loadBills();
    _loadWallet();
  }

  Future<void> _loadBills() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(huishApiClientProvider);
      final resp = await api.getBillList(status: _statusFilter, size: 50);
      if (!mounted) return;
      if (resp.isSuccess) {
        setState(() {
          _bills = resp.dataList ?? [];
          _loading = false;
        });
      } else {
        setState(() {
          _error = '加载失败 (code: ${resp.code})';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '网络异常，请检查网络后重试';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadWallet() async {
    final eid = ref.read(huishAuthStateProvider).eid;
    if (eid == null || eid.isEmpty) {
      if (mounted) setState(() => _walletLoading = false);
      return;
    }
    try {
      final api = ref.read(huishApiClientProvider);
      final resp = await api.getWalletOwner(eid);
      if (!mounted) return;
      if (resp.isSuccess) {
        final aw = resp.dataMap?['aw'] as Map<String, dynamic>?;
        setState(() {
          _cash = (aw?['olCash'] as num?)?.toDouble() ?? 0;
          _gift = (aw?['olGift'] as num?)?.toDouble() ?? 0;
          _epName = aw?['ep']?['name'] as String? ?? '';
          _walletLoading = false;
        });
      } else {
        if (mounted) setState(() => _walletLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _walletLoading = false);
    }
  }

  String _typeLabel(int type) => switch (type) {
    21 => '按量消费',
    91 => '按次消费',
    _ => '消费',
  };

  String _fmtTime(int? ctime) {
    if (ctime == null) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(ctime);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  void _showDetail(Map<String, dynamic> b) {
    final payment = (b['payment'] as num?)?.toDouble() ?? 0;
    final discount = (b['discount'] as num?)?.toDouble() ?? 0;
    final type = b['type'] as int? ?? 0;
    final status = b['status'] as int? ?? 0;
    final msg = b['msg'] as String? ?? '';
    final dev = b['dev'] as Map<String, dynamic>?;
    final devName = dev?['name'] as String? ?? '';
    final payee = b['payee'] as String? ?? '';
    final tag = b['tag'] as String? ?? '';
    final ctime = b['ctime'] as int?;

    showDialog(
      context: context,
      barrierColor: const Color(0x402E3350),
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: Colors.white.withValues(alpha: 0.92),
        title: const Text(
          '账单详情',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('金额', '¥${payment.toStringAsFixed(2)}'),
            _detailRow('类型', _typeLabel(type)),
            if (discount > 0)
              _detailRow('优惠', '-¥${discount.toStringAsFixed(2)}'),
            if (msg.isNotEmpty) _detailRow('描述', msg),
            if (devName.isNotEmpty) _detailRow('设备', devName),
            if (payee.isNotEmpty) _detailRow('收款方', payee),
            if (tag.isNotEmpty) _detailRow('交易号', tag),
            _detailRow('时间', _fmtTime(ctime)),
            _detailRow('状态', _statusStyles[status]?.label ?? '未知'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭', style: TextStyle(color: kPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(color: kTextMuted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: kTextMain),
            ),
          ),
        ],
      ),
    );
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
                        '消费记录',
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
              Expanded(
                child: RefreshIndicator(
                  color: kPrimary,
                  onRefresh: _loadBills,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    children: [
                      if (!_walletLoading && _epName.isNotEmpty) ...[
                        _balanceCard(),
                        const SizedBox(height: 16),
                      ],
                      _filterBar(),
                      const SizedBox(height: 10),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.only(top: 80),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_error != null)
                        _ErrorView(error: _error!, onRetry: _loadBills)
                      else if (_bills.isEmpty)
                        _EmptyView(filtered: _statusFilter != null)
                      else
                        ..._bills.map(
                          (b) => _BillCard(
                            bill: b as Map<String, dynamic>,
                            typeLabel: _typeLabel(b['type'] as int? ?? 0),
                            timeStr: _fmtTime(b['ctime'] as int?),
                            statusStyle:
                                _statusStyles[b['status'] as int? ?? 0],
                            onTap: () => _showDetail(b),
                          ),
                        ),
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

  Widget _balanceCard() {
    return GlassCard(
      radius: 24,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_rounded,
                size: 16,
                color: kPrimary,
              ),
              const SizedBox(width: 6),
              Text(
                _epName,
                style: const TextStyle(
                  fontSize: 12,
                  color: kTextMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '¥${(_cash + _gift).toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: kInk,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _walletChip('现金 ¥${_cash.toStringAsFixed(2)}'),
              const SizedBox(width: 8),
              _walletChip('赠送 ¥${_gift.toStringAsFixed(2)}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _walletChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          color: kTextMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _filterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: _filters.entries.map((e) {
          final selected = _statusFilter == e.key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() => _statusFilter = e.key);
                _loadBills();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: kSpring,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? kPrimary.withValues(alpha: 0.14)
                      : Colors.white.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? kPrimary.withValues(alpha: 0.55)
                        : Colors.white.withValues(alpha: 0.65),
                  ),
                ),
                child: Text(
                  e.value,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? kPrimary : kTextMuted,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StatusStyle {
  final String label;
  final Color color;
  const _StatusStyle(this.label, this.color);
}

class _BillCard extends StatelessWidget {
  final Map<String, dynamic> bill;
  final String typeLabel;
  final String timeStr;
  final _StatusStyle? statusStyle;
  final VoidCallback onTap;
  const _BillCard({
    required this.bill,
    required this.typeLabel,
    required this.timeStr,
    required this.statusStyle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final payment = (bill['payment'] as num?)?.toDouble() ?? 0;
    final msg = bill['msg'] as String? ?? '';
    final st = statusStyle ?? const _StatusStyle('未知', Color(0xFF8A93A6));

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
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: st.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.water_drop_rounded,
                  size: 20,
                  color: st.color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      typeLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: kInk,
                      ),
                    ),
                    if (msg.isNotEmpty && msg != typeLabel)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          msg,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: kTextMuted,
                          ),
                        ),
                      ),
                    if (timeStr.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          timeStr,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: kTextMuted,
                          ),
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
                    '¥${payment.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: kInk,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: st.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      st.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: st.color,
                        fontWeight: FontWeight.w600,
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

class _EmptyView extends StatelessWidget {
  final bool filtered;
  const _EmptyView({required this.filtered});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 70),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_rounded,
            size: 44,
            color: kTextMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            filtered ? '暂无该状态账单' : '暂无消费记录',
            style: TextStyle(
              fontSize: 13,
              color: kTextMuted.withValues(alpha: 0.8),
            ),
          ),
        ],
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
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(
            Icons.wifi_off_rounded,
            size: 44,
            color: kTextMuted.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          Text(
            error,
            style: TextStyle(
              fontSize: 12.5,
              color: kTextMuted.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(backgroundColor: kPrimary),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
