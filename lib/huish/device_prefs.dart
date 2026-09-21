// huish/device_prefs.dart —— 饮水设备本地偏好（自定义名 + 分组）。
//
// 存在 SharedPreferences，不影响云端数据。结构：
//   device_custom: { "<deviceId>": { "customName": "...", "groupId": "default" } }
//   groups: ["default", ...]  // "default" 系统分组，不可删不可重命名
//   group_order: [...]
//   custom_names: { "<deviceId>": "..." }  // 设备自定义名快捷查找

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class DeviceCustomInfo {
  final String customName;
  final String groupId;
  const DeviceCustomInfo({required this.customName, required this.groupId});
  DeviceCustomInfo.empty() : customName = '', groupId = 'default';
}

class DevicePrefs {
  static const _kDeviceCustom = 'huish_device_custom';
  static const _kGroups = 'huish_groups';
  static const _kDeviceOrder = 'huish_device_order';

  static Future<Map<String, DeviceCustomInfo>> loadDeviceCustoms() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kDeviceCustom);
    if (raw == null) return {};
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return json.map((k, v) {
        final m = v as Map<String, dynamic>;
        return MapEntry(
          k,
          DeviceCustomInfo(
            customName: m['customName'] as String? ?? '',
            groupId: m['groupId'] as String? ?? 'default',
          ),
        );
      });
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveDeviceCustoms(
    Map<String, DeviceCustomInfo> map,
  ) async {
    final sp = await SharedPreferences.getInstance();
    final json = map.map(
      (k, v) => MapEntry(k, {'customName': v.customName, 'groupId': v.groupId}),
    );
    await sp.setString(_kDeviceCustom, jsonEncode(json));
  }

  static Future<List<String>> loadGroups() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_kGroups);
    if (raw == null || raw.isEmpty) return ['default'];
    if (!raw.contains('default')) return ['default', ...raw];
    return raw;
  }

  static Future<void> saveGroups(List<String> groups) async {
    await SharedPreferences.getInstance().then((sp) {
      sp.setStringList(_kGroups, groups);
    });
  }

  /// 分组内设备拖拽顺序：`{ "<groupId>": ["deviceId", ...] }`
  static Future<Map<String, List<String>>> loadDeviceOrder() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kDeviceOrder);
    if (raw == null) return {};
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return json.map(
        (k, v) => MapEntry(k, (v as List).map((e) => e.toString()).toList()),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveDeviceOrder(Map<String, List<String>> order) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kDeviceOrder, jsonEncode(order));
  }

  static Future<void> updateDeviceCustom(
    String deviceId, {
    String? customName,
    String? groupId,
  }) async {
    final map = await loadDeviceCustoms();
    final existing = map[deviceId] ?? DeviceCustomInfo.empty();
    map[deviceId] = DeviceCustomInfo(
      customName: customName ?? existing.customName,
      groupId: groupId ?? existing.groupId,
    );
    await saveDeviceCustoms(map);
  }

  /// 删除设备：清掉自定义信息和排序记录。
  static Future<void> removeDevice(String deviceId) async {
    final map = await loadDeviceCustoms();
    map.remove(deviceId);
    await saveDeviceCustoms(map);
    final order = await loadDeviceOrder();
    final cleaned = order.map(
      (k, v) => MapEntry(k, v.where((id) => id != deviceId).toList()),
    );
    await saveDeviceOrder(cleaned);
  }

  /// 新建分组（default 保留字、重名/空名拒绝）。
  static Future<bool> addGroup(String name) async {
    final n = name.trim();
    if (n.isEmpty || n == 'default') return false;
    final groups = await loadGroups();
    if (groups.contains(n)) return false;
    await saveGroups([...groups, n]);
    return true;
  }

  /// 重命名分组：groups 更新 + 其下设备的 groupId 同步迁移。
  static Future<void> renameGroup(String oldName, String newName) async {
    final n = newName.trim();
    if (oldName == 'default' || n.isEmpty || n == 'default') return;
    final groups = await loadGroups();
    if (!groups.contains(oldName) || groups.contains(n)) return;
    await saveGroups(groups.map((g) => g == oldName ? n : g).toList());
    final map = await loadDeviceCustoms();
    final changed = map.map(
      (k, v) => MapEntry(
        k,
        v.groupId == oldName
            ? DeviceCustomInfo(customName: v.customName, groupId: n)
            : v,
      ),
    );
    await saveDeviceCustoms(changed);
  }

  /// 删除分组：其下设备移回 default。
  static Future<void> deleteGroup(String name) async {
    if (name == 'default') return;
    final groups = await loadGroups();
    if (!groups.contains(name)) return;
    await saveGroups(groups.where((g) => g != name).toList());
    final map = await loadDeviceCustoms();
    final changed = map.map(
      (k, v) => MapEntry(
        k,
        v.groupId == name
            ? DeviceCustomInfo(customName: v.customName, groupId: 'default')
            : v,
      ),
    );
    await saveDeviceCustoms(changed);
  }
}
