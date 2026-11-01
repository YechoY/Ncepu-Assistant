// core/logging_http_client.dart —— 带调试日志的 http.Client 装饰器。
//
// 包装任意 http.Client，在每笔请求前/后自动记录到 AppDebugLog（开关关闭时零开销）。
// 供教务侧 ApiClient 和饮水侧 HuishApiClient 共用。

import 'package:http/http.dart' as http;

import 'debug_log.dart';

/// 带调试日志的 http.Client 装饰器。
/// 用法：`final client = LoggingHttpClient(http.Client());`
class LoggingHttpClient extends http.BaseClient {
  LoggingHttpClient([http.Client? inner]) : _inner = inner ?? http.Client();
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final dbg = AppDebugLog.instance;
    if (dbg.isEnabled) {
      final uri = request.url;
      final method = request.method.toUpperCase();
      final tag = uri.host.contains('ilife798') ? 'HUISH' : 'JWXT';
      dbg.log('$tag→', '$method $uri');
    }
    final response = await _inner.send(request);
    if (dbg.isEnabled) {
      final uri = request.url;
      final tag = uri.host.contains('ilife798') ? 'HUISH' : 'JWXT';
      dbg.log(
        '$tag←',
        '${response.statusCode} ${uri.path}${request.contentLength != null ? ' len=${request.contentLength}' : ''}',
      );
    }
    return response;
  }

  @override
  void close() => _inner.close();
}
