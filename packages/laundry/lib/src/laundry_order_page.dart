// laundry/laundry_order_page.dart —— 洗衣下单确认页（独立页面，替代原套餐弹窗）。
//
// 扫码识别成功后进入：套餐 / 水温 / 洗衣液 / 除菌液 分组选择，
// 底部实时合计（套餐 + 水温 + 加液），点「创建订单」把选择结果带回首页下单。
// 加液分组仅在该设备/套餐支持时显示；「不添加」对应 null。

import 'package:flutter/material.dart';

import 'package:glass_ui/theme.dart';
import 'package:glass_ui/widgets/glass_background.dart';
import 'package:glass_ui/widgets/glass_card.dart';

import 'laundry_api_client.dart';
import 'laundry_device_prefs.dart';

/// 下单选择结果（pop 返回给首页）。加液 null = 不添加。
class LaundryOrderSelection {
  final int modelId;
  final int temperatureId;
  final int? detergentGearId;
  final int? disinfectantGearId;
  const LaundryOrderSelection({
    required this.modelId,
    required this.temperatureId,
    this.detergentGearId,
    this.disinfectantGearId,
  });
}

class LaundryOrderPage extends StatefulWidget {
  const LaundryOrderPage({
    super.key,
    required this.program,
    required this.qrCode,
    this.initialInFavs = false,
  });

  final WasherProgram program;
  final String qrCode; // 原始二维码/设备码（收藏 qrUrl 用，下次「去洗衣」直达）
  final bool initialInFavs; // 进页时是否已在常用列表

  @override
  State<LaundryOrderPage> createState() => _LaundryOrderPageState();
}

class _LaundryOrderPageState extends State<LaundryOrderPage> {
  late int _modelId = widget.program.defaultWashModelId;
  int _temperatureId = 1; // 默认常温（官方 App 行为）
  int? _detergentId; // 洗衣液档位，null = 不添加
  int? _disinfectId; // 除菌液档位，null = 不添加
  late bool _inFavs = widget.initialInFavs; // 常用收藏（开关即时生效，与下单解耦）

  /// 设备展示号：deviceNo 缺失（不可下单响应）时用二维码 cd / deviceId 兜底。
  String get _deviceNo => washerDisplayNo(widget.program, widget.qrCode);

  /// 是否可下单：设备可用且有套餐。
  bool get _orderable =>
      widget.program.createOrderEnabled && widget.program.models.isNotEmpty;

  WashModel get _selectedModel {
    final models = widget.program.models;
    for (final m in models) {
      if (m.id == _modelId) return m;
    }
    return models.first;
  }

  List<WasherAdditionOption> get _detergentOptions =>
      _selectedModel.additionOptions('wp_detergentGearId');
  List<WasherAdditionOption> get _disinfectOptions =>
      _selectedModel.additionOptions('wp_disinfectantGearId');

  /// 实时合计：套餐 + 水温（静默固定价）+ 洗衣液 + 除菌液。
  int get _totalFen {
    final model = _selectedModel;
    var total = model.priceFen + (kWasherTemperaturePriceFen[_temperatureId] ?? 0);
    for (final o in _detergentOptions) {
      if (o.id == _detergentId) total += o.priceFen;
    }
    for (final o in _disinfectOptions) {
      if (o.id == _disinfectId) total += o.priceFen;
    }
    return total;
  }

  void _pickModel(WashModel m) {
    setState(() {
      _modelId = m.id;
      // 切套餐后加液档位随套餐变化，重置为「不添加」
      _detergentId = null;
      _disinfectId = null;
    });
  }

  void _confirm() {
    Navigator.of(context).pop(
      LaundryOrderSelection(
        modelId: _modelId,
        temperatureId: _temperatureId,
        detergentGearId: _detergentId,
        disinfectantGearId: _disinfectId,
      ),
    );
  }

  /// 「常用设备」开关：与下单完全解耦，点按立即写入/移出本地收藏。
  Future<void> _toggleFav() async {
    final v = !_inFavs;
    setState(() => _inFavs = v);
    final p = widget.program;
    try {
      if (v) {
        await LaundryDevicePrefs.addOrUpdate(
          FavWasher(
            deviceNo: _deviceNo,
            qrUrl: widget.qrCode,
            typeName: p.deviceTypeName,
            storeName: p.storeName,
          ),
        );
      } else {
        await LaundryDevicePrefs.remove(_deviceNo);
      }
    } catch (_) {
      // 存储失败静默（下次进页按实际收藏态显示）
    }
  }

  /// 「加入常用设备」开关行：点整行切换，即时写入/移出收藏（不依赖下单）。
  Widget _favSwitchRow() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleFav,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _inFavs ? '已加入常用设备' : '加入常用设备',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kTextMain,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '即时生效，下次免扫码一键直达',
                  style: TextStyle(
                    fontSize: 11,
                    color: kTextMuted.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 42,
            height: 24,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: _inFavs
                  ? kLaundryDeep.withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.55),
              border: Border.all(
                color: _inFavs
                    ? kLaundryDeep.withValues(alpha: 0.4)
                    : kGlassBorder,
              ),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment:
                  _inFavs ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: _topBar(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _deviceCard(),
                      const SizedBox(height: 12),
                      _sectionCard(
                        icon: Icons.turned_in_rounded,
                        title: '常用设备',
                        tail: '记录这台洗衣机',
                        child: _favSwitchRow(),
                      ),
                      const SizedBox(height: 12),
                      if (_orderable) ...[
                        _sectionCard(
                          icon: Icons.local_laundry_service_outlined,
                          title: '套餐选择',
                          tail: '请选择洗衣套餐',
                          child: _modelList(),
                        ),
                        const SizedBox(height: 12),
                        _sectionCard(
                          icon: Icons.thermostat_rounded,
                          title: '温度选择',
                          tail: '请选择洗涤水温',
                          child: _chipWrap(
                            children: [
                              for (final e in kWasherTemperatures.entries)
                                _chip(
                                  label: e.value,
                                  icon: Icons.device_thermostat_rounded,
                                  selected: _temperatureId == e.key,
                                  onTap: () => setState(() => _temperatureId = e.key),
                                ),
                            ],
                          ),
                        ),
                        if (_detergentOptions.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _sectionCard(
                            icon: Icons.soap_rounded,
                            title: '洗衣液选择',
                            tail: '请选择洗衣液用量',
                            child: _chipWrap(
                              children: [
                                _chip(
                                  label: '不添加',
                                  icon: Icons.block_rounded,
                                  selected: _detergentId == null,
                                  onTap: () => setState(() => _detergentId = null),
                                ),
                                for (final o in _detergentOptions)
                                  _chip(
                                    label: o.name,
                                    priceText: o.priceText,
                                    icon: Icons.water_drop_rounded,
                                    selected: _detergentId == o.id,
                                    onTap: () => setState(() => _detergentId = o.id),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        if (_disinfectOptions.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _sectionCard(
                            icon: Icons.sanitizer_rounded,
                            title: '除菌液选择',
                            tail: '请选择除菌液用量',
                            child: _chipWrap(
                              children: [
                                _chip(
                                  label: '不添加',
                                  icon: Icons.block_rounded,
                                  selected: _disinfectId == null,
                                  onTap: () => setState(() => _disinfectId = null),
                                ),
                                for (final o in _disinfectOptions)
                                  _chip(
                                    label: o.name,
                                    priceText: o.priceText,
                                    icon: Icons.clean_hands_rounded,
                                    selected: _disinfectId == o.id,
                                    onTap: () => setState(() => _disinfectId = o.id),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ] else ...[
                        // 不可下单（离线/使用中/故障）：占位提示，仍可收藏
                        _sectionCard(
                          icon: Icons.info_outline_rounded,
                          title: '设备暂不可用',
                          tail: '无法选择套餐',
                          child: _unavailableHint(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              _bottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  // ===== UI 组件 =====

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
            '确认洗衣订单',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: kInk,
            ),
          ),
        ),
      ],
    );
  }

  Widget _deviceCard() {
    final p = widget.program;
    return GlassCard(
      radius: 20,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      live: false,
      opacity: kFrostAlpha,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
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
              border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
            ),
            child: Icon(
              Icons.local_laundry_service_outlined,
              size: 21,
              color: kLaundryDeep.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.storeName.isEmpty ? '洗衣机' : p.storeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: kTextMain,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _deviceNo.isEmpty
                      ? p.deviceTypeName
                      : '${p.deviceTypeName.isEmpty ? '洗衣机' : p.deviceTypeName} · $_deviceNo',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: kTextMuted.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _statusChip(),
        ],
      ),
    );
  }

  /// 设备状态徽标（设备卡右侧）：绿点 = 空闲可下单；粉点 + 服务端原因 = 不可用。
  Widget _statusChip() {
    final ok = widget.program.createOrderEnabled;
    final color = ok ? const Color(0xFF3E9B6C) : kWeekend;
    final reason = widget.program.reason.trim();
    final label = ok ? '空闲可下单' : (reason.isEmpty ? '暂不可用' : reason);
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
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
      ),
    );
  }

  /// 不可下单占位文案。
  Widget _unavailableHint() {
    final reason = widget.program.reason.trim();
    return Text(
      reason.isEmpty
          ? '设备当前不可下单，可先收藏这台设备，等它空闲后再来。'
          : '服务端提示：$reason。可先收藏，设备空闲后再来洗衣。',
      style: TextStyle(
        fontSize: 12,
        height: 1.5,
        color: kTextMuted.withValues(alpha: 0.9),
      ),
    );
  }

  /// 分组卡：小标题行（图标 + 标题 + 尾注）+ 内容。
  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String tail,
    required Widget child,
  }) {
    return GlassCard(
      radius: 20,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      // 分区卡用静态磨砂（性能规则：一屏实时 blur ≤ 5，列表/分区卡禁用实时模糊）
      live: false,
      opacity: kFrostAlpha,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kLaundry.withValues(alpha: 0.35),
                ),
                child: Icon(icon, size: 15, color: kLaundryDeep),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: kInk,
                ),
              ),
              const Spacer(),
              Text(
                tail,
                style: TextStyle(
                  fontSize: 11,
                  color: kTextMuted.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  /// 套餐竖排列表（单选行）。
  Widget _modelList() {
    return Column(
      children: [
        for (var i = 0; i < widget.program.models.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _modelRow(widget.program.models[i]),
        ],
      ],
    );
  }

  Widget _modelRow(WashModel m) {
    final selected = m.id == _modelId;
    final isDefault = m.id == widget.program.defaultWashModelId;
    return GestureDetector(
      onTap: () => _pickModel(m),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected
              ? kLaundry.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.5),
          border: Border.all(
            color: selected
                ? kLaundryDeep.withValues(alpha: 0.5)
                : kGlassBorder,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          m.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: selected ? kLaundryDeep : kTextMain,
                          ),
                        ),
                      ),
                      if (isDefault) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: kLaundryDeep.withValues(alpha: 0.12),
                          ),
                          child: const Text(
                            '推荐',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: kLaundryDeep,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '约 ${m.timeMinutes} 分钟',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: kTextMuted.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              m.priceText,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: selected ? kLaundryDeep : kTextMain,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: selected ? kLaundryDeep : kTextMuted.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  /// 选项胶囊流式布局（温度/加液共用）。
  Widget _chipWrap({required List<Widget> children}) {
    return Wrap(spacing: 8, runSpacing: 8, children: children);
  }

  Widget _chip({
    required String label,
    String? priceText,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected
              ? kLaundryDeep.withValues(alpha: 0.92)
              : Colors.white.withValues(alpha: 0.55),
          border: Border.all(
            color: selected
                ? kLaundryDeep.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.7),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: kLaundryDeep.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected
                  ? Colors.white
                  : kLaundryDeep.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : kTextMain,
              ),
            ),
            if (priceText != null) ...[
              const SizedBox(width: 4),
              Text(
                priceText,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.white.withValues(alpha: 0.85)
                      : kTextMuted.withValues(alpha: 0.85),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 底部合计 + 创建订单按钮（固定底栏）。
  Widget _bottomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: GlassCard(
        radius: 22,
        padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '预计合计',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: kTextMuted.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _orderable ? '¥${(_totalFen / 100).toStringAsFixed(2)}' : '--',
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: kInk,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: _orderable ? _confirm : null,
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 26),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: _orderable
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [kLaundry, kLaundryDeep],
                        )
                      : const LinearGradient(
                          colors: [Color(0xFFB0B5C2), Color(0xFF9AA0AF)],
                        ),
                  boxShadow: _orderable
                      ? [
                          BoxShadow(
                            color: kLaundryDeep.withValues(alpha: 0.3),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  _orderable ? '创建订单' : '设备暂不可下单',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
