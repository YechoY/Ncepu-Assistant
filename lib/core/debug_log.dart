// core/debug_log.dart —— 应用级调试日志器（全局单例）。
//
// 内存滚动缓冲（上限 16000 字符，超出裁头）+ SharedPreferences 持久化。
// 开关关闭时 log() 早退，不影响性能；开关打开后所有 HTTP 请求/响应自动记录。
// 供两个 API client（教务 ApiClient / 饮水 HuishApiClient）共用。

import 'package:shared_preferences/shared_preferences.dart';

class AppDebugLog {
  AppDebugLog._();
  static final AppDebugLog instance = AppDebugLog._();

  static const _kEnabled = 'app_debug_enabled';
  static const _kLog = 'app_debug_log';
  static const int maxChars = 16000;

  final StringBuffer _buffer = StringBuffer();
  bool _enabled = false;
  bool _initialized = false;

  bool get isEnabled => _enabled;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final sp = await SharedPreferences.getInstance();
    _enabled = sp.getBool(_kEnabled) ?? false;
    if (_enabled) {
      final saved = sp.getString(_kLog);
      if (saved != null && saved.isNotEmpty) _buffer.write(saved);
    }
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kEnabled, v);
    // 关闭时不清空日志缓冲——用户可能想关闭后仍查看已记录的内容
    // 日志只在显式点击"清空"时才删除
  }

  void log(String tag, String message) {
    if (!_enabled) return;
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    final line = '[$ts] [$tag] $message\n';
    var merged = _buffer.toString() + line;
    if (merged.length > maxChars) {
      merged = merged.substring(merged.length - maxChars);
    }
    _buffer
      ..clear()
      ..write(merged);
    _persist();
  }

  String read() => _buffer.toString();

  Future<void> clear() async {
    _buffer.clear();
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kLog);
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kLog, _buffer.toString());
  }
}
