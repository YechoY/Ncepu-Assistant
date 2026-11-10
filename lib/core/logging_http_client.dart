// core/logging_http_client.dart —— 带调试日志的 http.Client 装饰器。
//
// 包装任意 http.Client，每笔请求记录一条日志：方法 + 路径 + 状态码 + 耗时。
// 开关关闭时零开销。供教务 ApiClient、饮水 HuishApiClient、洗衣 LaundryApiClient 共用。

import 'package:http/http.dart' as http;

import 'debug_log.dart';

/// 带调试日志的 http.Client 装饰器。
/// 用法：`final client = LoggingHttpClient(http.Client());`
class LoggingHttpClient extends http.BaseClient {
  LoggingHttpClient([http.Client? inner]) : _inner = inner ?? http.Client();
  final http.Client _inner;

  /// 按目标 host 打模块标签。
  static String _tagOf(Uri uri) {
    final host = uri.host;
    if (host.contains('ilife798')) return 'HUISH';
    if (host.contains('ujing')) return 'LAUNDRY';
    return 'JWXT';
  }

  static String _fmtDuration(Duration d) {
    final ms = d.inMilliseconds;
    return ms < 1000 ? '${ms}ms' : '${(ms / 1000).toStringAsFixed(1)}s';
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final dbg = AppDebugLog.instance;
    if (!dbg.isEnabled) return _inner.send(request);

    final sw = Stopwatch()..start();
    final uri = request.url;
    final path = uri.path.isEmpty ? '/' : uri.path;
    final label =
        '${request.method.toUpperCase()} $path'
        '${uri.hasQuery ? '?${uri.query}' : ''}';
    try {
      final response = await _inner.send(request);
      dbg.log(
        _tagOf(uri),
        '$label → ${response.statusCode} · ${_fmtDuration(sw.elapsed)}',
      );
      return response;
    } catch (e) {
      dbg.log(_tagOf(uri), '$label → FAIL ${e.toString().split('\n').first}');
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}
