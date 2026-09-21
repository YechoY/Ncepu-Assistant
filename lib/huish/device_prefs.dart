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
}
