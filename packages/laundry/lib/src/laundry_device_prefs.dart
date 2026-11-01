// laundry/laundry_device_prefs.dart —— 常用洗衣机本地偏好（收藏 + 自定义名 + 分组）。
//
// 扫码/手动输入识别成功过的洗衣机自动记住（SharedPreferences，不上云），
// 首页点击即可直接进入下单流程；支持自定义名称与分组（对齐 huish DevicePrefs 规则）。

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class FavWasher {
  final String deviceNo;
  final String qrUrl; // 二维码原文（scanWasher 入参）
  final String typeName; // 设备类型名（如 波轮洗衣机）
  final String storeName;
  final String customName; // 自定义名（空 = 显示默认「洗衣机 <deviceNo>」）
  final String groupId; // 所属分组，'default' 系统分组不可删不可重命名

  const FavWasher({
    required this.deviceNo,
    required this.qrUrl,
    this.typeName = '',
    this.storeName = '',
    this.customName = '',
    this.groupId = 'default',
  });

  /// 展示名：自定义名优先，无设备号时回退二维码原文。
  String get displayName => customName.isNotEmpty
      ? customName
      : (deviceNo.isEmpty ? qrUrl : '洗衣机 $deviceNo');

  FavWasher copyWith({String? customName, String? groupId}) => FavWasher(
        deviceNo: deviceNo,
        qrUrl: qrUrl,
        typeName: typeName,
        storeName: storeName,
        customName: customName ?? this.customName,
        groupId: groupId ?? this.groupId,
      );

  Map<String, dynamic> _json() => {
        'deviceNo': deviceNo,
        'qrUrl': qrUrl,
        'typeName': typeName,
        'storeName': storeName,
        'customName': customName,
        'groupId': groupId,
      };

  static FavWasher _from(Map<String, dynamic> m) => FavWasher(
        deviceNo: m['deviceNo'] as String? ?? '',
        qrUrl: m['qrUrl'] as String? ?? '',
        typeName: m['typeName'] as String? ?? '',
        storeName: m['storeName'] as String? ?? '',
        customName: m['customName'] as String? ?? '',
        groupId: m['groupId'] as String? ?? 'default',
      );
}

class LaundryDevicePrefs {
  static const _kFavs = 'laundry_fav_washers';
  static const _kGroups = 'laundry_groups';

  // ===== 收藏 =====

  static Future<List<FavWasher>> loadFavs() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kFavs);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => FavWasher._from(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 按设备号/二维码去重，新识别的排最前；已存在时刷新元数据但保留自定义名与分组。
  static Future<List<FavWasher>> addOrUpdate(FavWasher item) async {
    final list = await loadFavs();
    final kept = list
        .where((e) => e.deviceNo != item.deviceNo && e.qrUrl != item.qrUrl)
        .toList();
    final old = list.firstWhere(
      (e) => e.deviceNo == item.deviceNo || e.qrUrl == item.qrUrl,
      orElse: () => item,
    );
    kept.insert(
      0,
      item.copyWith(
        customName: old.customName,
        groupId: old.groupId,
      ),
    );
    await _save(kept);
    return kept;
  }

  static Future<List<FavWasher>> remove(String deviceNo) async {
    final list = await loadFavs()..removeWhere((e) => e.deviceNo == deviceNo);
    await _save(list);
    return list;
  }

  /// 更新设备自定义名 / 所在分组。
  static Future<List<FavWasher>> updateDevice(
    String deviceNo, {
    String? customName,
    String? groupId,
  }) async {
    final list = await loadFavs();
    final next = [
      for (final f in list)
        f.deviceNo == deviceNo
            ? f.copyWith(customName: customName, groupId: groupId)
            : f,
    ];
    await _save(next);
    return next;
  }

  static Future<void> _save(List<FavWasher> list) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kFavs, jsonEncode(list.map((e) => e._json()).toList()));
  }

  // ===== 分组 =====

  static Future<List<String>> loadGroups() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_kGroups);
    if (raw == null || raw.isEmpty) return ['default'];
    if (!raw.contains('default')) return ['default', ...raw];
    return raw;
  }

  static Future<void> _saveGroups(List<String> groups) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_kGroups, groups);
  }

  /// 新建分组（default 保留字、重名/空名拒绝）。
  static Future<bool> addGroup(String name) async {
    final n = name.trim();
    if (n.isEmpty || n == 'default') return false;
    final groups = await loadGroups();
    if (groups.contains(n)) return false;
    await _saveGroups([...groups, n]);
    return true;
  }

  /// 重命名分组：groups 更新 + 其下设备 groupId 同步迁移。
  static Future<void> renameGroup(String oldName, String newName) async {
    final n = newName.trim();
    if (oldName == 'default' || n.isEmpty || n == 'default') return;
    final groups = await loadGroups();
    if (!groups.contains(oldName) || groups.contains(n)) return;
    await _saveGroups(groups.map((g) => g == oldName ? n : g).toList());
    final favs = await loadFavs();
    await _save([
      for (final f in favs)
        f.groupId == oldName ? f.copyWith(groupId: n) : f,
    ]);
  }

  /// 删除分组：其下设备移回 default。
  static Future<void> deleteGroup(String name) async {
    if (name == 'default') return;
    final groups = await loadGroups();
    if (!groups.contains(name)) return;
    await _saveGroups(groups.where((g) => g != name).toList());
    final favs = await loadFavs();
    await _save([
      for (final f in favs)
        f.groupId == name ? f.copyWith(groupId: 'default') : f,
    ]);
  }

  // ===== 分组内设备拖拽排序 =====

  static const _kDeviceOrder = 'laundry_device_order';

  /// 分组内设备顺序：`{ "<groupId>": [deviceNo, ...] }`（与饮水模块一致）。
  static Future<Map<String, List<String>>> loadDeviceOrder() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kDeviceOrder);
    if (raw == null) return {};
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return json.map(
        (k, v) => MapEntry(
          k,
          (v as List).map((e) => e.toString()).toList(),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveDeviceOrder(Map<String, List<String>> order) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kDeviceOrder, jsonEncode(order));
  }

  // ===== 本地洗衣记录（已完成订单，倒序）=====
  //
  // 存储格式 "orderId|完成毫秒时间戳"；旧格式纯 orderId 视为无时间。

  static const _kOrderHistory = 'laundry_order_history';

  /// 读取本地历史：`(orderId, 完成时间)`，旧记录时间为 null。
  static Future<List<(String, DateTime?)>> loadOrderHistory() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_kOrderHistory) ?? [];
    return [
      for (final s in raw)
        if (s.contains('|'))
          (
            s.split('|')[0],
            DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(s.split('|')[1]) ?? 0,
            ),
          )
        else
          (s, null),
    ];
  }

  /// 记录一笔订单到本地历史（按订单去重置顶，上限 50 条）。
  static Future<void> addOrderHistory(
    String orderId, {
    DateTime? finishedAt,
  }) async {
    if (orderId.isEmpty) return;
    final entry =
        '$orderId|${(finishedAt ?? DateTime.now()).millisecondsSinceEpoch}';
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_kOrderHistory) ?? [];
    list.removeWhere((s) => s.split('|')[0] == orderId);
    list.insert(0, entry);
    await sp.setStringList(
      _kOrderHistory,
      list.length > 50 ? list.sublist(0, 50) : list,
    );
  }
}
