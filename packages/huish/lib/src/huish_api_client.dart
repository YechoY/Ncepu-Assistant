// huish/huish_api_client.dart —— 惠生活798 API 客户端。
//
// 改自参考项目 huish-main/lib/api/api_client.dart（接口签名保持一致，
// 方便以后上游更新时 diff 对比）。改动点：
//   - Token 存储从 SharedPreferences 改为 flutter_secure_storage（项目硬约束）
//   - SSL Pinning 占位未启用（参考项目也未配置）

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class HuishApiClient {
  static const String _baseUrl = 'https://i.ilife798.com';

  // Secure Storage keys（前缀 huish_ 与教务账号隔离）
  static const _kToken = 'huish_auth_token';
  static const _kUid = 'huish_auth_uid';
  static const _kEid = 'huish_auth_eid';
  static const _kPhone = 'huish_auth_phone';

  // SHA256 fingerprints of trusted certificates (uppercase hex, colon-separated)
  // Get them: openssl s_client -connect i.ilife798.com:443 -servername i.ilife798.com </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256
  static const _pinnedCerts = <String>{
    // Replace with real fingerprint from the server
    'PLACEHOLDER',
  };

  late final http.Client _client;
  // EncryptedSharedPreferences 模式：release 包 R8 混淆下无参默认模式的
  // keystore 加密读写会失败（表现为每次启动丢 token），对齐洗衣模块修复。
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final void Function(String tag, String msg)? _logger;

  String? _token;
  String? _uid;
  String? _eid;

  // Cookie 存储：sendSms 成功后服务端下发 Set-Cookie，
  // login 必须带上才能关联 captcha → sms 会话。
  // key=cookie 名，value=cookie 值（不含属性）。
  final Map<String, String> _cookies = {};

  /// [logger] 可选注入宿主日志接收器（如 AppDebugLog.log）。
  /// 不注入则模块静默运行，零宿主依赖。
  HuishApiClient({void Function(String tag, String msg)? logger})
      : _logger = logger {
    final inner = _createPinnedClient();
    _client = _logger == null ? inner : _LoggingClient(inner, _logger);
  }

  static String _certSha256(X509Certificate cert) {
    final hash = crypto.sha256.convert(cert.der);
    return hash.toString();
  }

  http.Client _createPinnedClient() {
    final httpClient = HttpClient();
    httpClient.connectionTimeout = const Duration(seconds: 15);
    httpClient.badCertificateCallback =
        (X509Certificate cert, String host, int port) {
          if (host != 'i.ilife798.com') return false;
          if (_pinnedCerts.contains('PLACEHOLDER'))
            return true; // SSL Pinning 未启用（参考项目占位）
          return _pinnedCerts.contains(_certSha256(cert));
        };
    return IOClient(httpClient);
  }

  // 设备控制通道（ApplicationType=1,1）的 API 版本头，与服务端协议绑定，
  // 和官方包自己的 versionName（3.1.10）无关。UA 必须写成 Android_ilife798_<同一个值>。
  static const String _versionName = '3.1.9';
  static const String _versionCode = '3.1.9';

  // 登录接口验签盐值。服务端只认带 sign 的请求，缺 sign 时返回
  // "请升级最新版应用"（伪装成版本过旧，实际是缺签名）。
  static const String _signSalt = 'AbCdEfGhIjKlMnOpQrStUvWxYz12345';

  Map<String, String> get _baseHeaders => _headersFor(_versionName, _versionCode);

  static Map<String, String> _headersFor(String verName, String verCode) => {
    'ApplicationType': '1,1',
    'VersionCode': verCode,
    'user-agent': 'Android_ilife798_$verName',
    'Accept-Language': 'zh-Hans-CN;q=1',
  };

  Map<String, String> get _authHeaders {
    final h = <String, String>{..._baseHeaders};
    final t = _token;
    if (t != null) h['Authorization'] = t;
    if (_cookies.isNotEmpty) {
      h['cookie'] = _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    }
    return h;
  }

  /// 从响应头的 set-cookie 提取 cookie 名值对，存入 _cookies。
  /// 服务端可能一次下发多个 set-cookie（每个一个），也可能用逗号分隔。
  void _saveCookies(http.Response resp) {
    final raw = resp.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    // http 包会把多个 Set-Cookie 用逗号连接，但 cookie 值里也可能有逗号。
    // 这里按 "name=value; " 切分，取第一个分号前的部分。
    for (final part in raw.split(',')) {
      final seg = part.trim();
      final idx = seg.indexOf(';');
      final nv = (idx >= 0 ? seg.substring(0, idx) : seg).trim();
      final eq = nv.indexOf('=');
      if (eq > 0) {
        _cookies[nv.substring(0, eq).trim()] = nv.substring(eq + 1).trim();
      }
    }
  }

  Future<void> _persistToken([String? phone]) async {
    if (_token != null) {
      await _storage.write(key: _kToken, value: _token!);
      await _storage.write(key: _kUid, value: _uid ?? '');
      await _storage.write(key: _kEid, value: _eid ?? '');
      if (phone != null) {
        await _storage.write(key: _kPhone, value: phone);
      }
    }
  }

  Future<bool> restoreToken() async {
    final t = await _storage.read(key: _kToken);
    if (t != null && t.isNotEmpty) {
      _token = t;
      _uid = await _storage.read(key: _kUid);
      _eid = await _storage.read(key: _kEid);
      return true;
    }
    return false;
  }

  Future<String?> readSavedPhone() async {
    return await _storage.read(key: _kPhone);
  }

  Future<void> clearToken() async {
    _token = null;
    _uid = null;
    _eid = null;
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kUid);
    await _storage.delete(key: _kEid);
    await _storage.delete(key: _kPhone);
  }

  bool get isLoggedIn => _token != null;
  String? get token => _token;
  String? get uid => _uid;
  String? get eid => _eid;

  // ── 登录 ────────────────────────────────────────────────

  double _randS() {
    final rng = Random();
    return rng.nextDouble();
  }

  Future<HuishCaptchaResult> getCaptcha() async {
    final s = _randS();
    final r = DateTime.now().millisecondsSinceEpoch;
    final url = Uri.parse('$_baseUrl/api/v1/captcha/?s=$s&r=$r');
    // UA 必须和 sendSms/login 一致：服务端可能按 UA+版本 绑定会话，
    // 旧代码这里用 Dalvik UA，会和后续请求对不上。
    final resp = await _client.get(url, headers: _baseHeaders);
    // 验证码请求下发的 cookie 可能参与 captcha→sms→login 的会话关联
    _saveCookies(resp);
    return HuishCaptchaResult(
      s: s,
      r: r,
      imageBytes: resp.bodyBytes,
      contentType: resp.headers['content-type'] ?? 'image/png',
    );
  }

  Future<HuishApiResponse> sendSmsCode({
    required String phone,
    required String captchaCode,
    required double captchaS,
  }) async {
    final resp = await _post(
      '/api/v1/acc/login/code',
      data: {'authCode': captchaCode, 's': captchaS, 'un': phone},
    );
    return HuishApiResponse.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  /// 登录签名：md5("authCode=" + 短信码 + "&un=" + 手机号 + 盐)，放在 URL 查询串上。
  String _loginSign(String phone, String smsCode) {
    final raw = 'authCode=$smsCode&un=$phone$_signSalt';
    return crypto.md5.convert(utf8.encode(raw)).toString();
  }

  Future<HuishApiResponse> login({
    required String phone,
    required String smsCode,
  }) async {
    final resp = await _post(
      '/api/v1/acc/login',
      data: {'un': phone, 'authCode': smsCode},
      query: {'sign': _loginSign(phone, smsCode)},
    );
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final result = HuishApiResponse.fromJson(json);
    if (result.code == 0 && json['data'] != null) {
      final al = json['data']['al'];
      if (al != null) {
        _token = al['token'] as String?;
        _uid = al['uid'] as String?;
        _eid = al['eid'] as String?;
        await _persistToken(phone);
      }
    }
    return result;
  }

  // ── 设备 ────────────────────────────────────────────────

  Future<HuishApiResponse> getMaster() async {
    final resp = await _get('/api/v1/ui/app/master');
    return HuishApiResponse.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<HuishApiResponse> getDeviceHome(
    String deviceId, {
    int apply = 6,
  }) async {
    final resp = await _get(
      '/api/v1/ui/app/dev/home/1?did=$deviceId&apply=$apply',
    );
    return HuishApiResponse.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<HuishApiResponse> getDeviceStatus(String deviceId) async {
    final resp = await _get(
      '/api/v1/ui/app/dev/status?did=$deviceId&more=false',
    );
    return HuishApiResponse.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  /// 启动设备（出水授权）。ptype=91 对齐 NcepuJw（华电同学真机可用）。
  Future<HuishApiResponse> startDevice(
    String deviceId, {
    int ptype = 91,
  }) async {
    final resp = await _get(
      '/api/v1/dev/start?did=$deviceId&upgrade=true&ptype=$ptype&rcp=false',
    );
    return HuishApiResponse.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<HuishApiResponse> stopDevice(String deviceId) async {
    final resp = await _get('/api/v1/dev/end?did=$deviceId');
    return HuishApiResponse.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<HuishApiResponse> favoriteDevice(
    String deviceId, {
    bool remove = false,
  }) async {
    final resp = await _get(
      '/api/v1/dev/favo?did=$deviceId&remove=${remove ? 1 : 0}',
    );
    return HuishApiResponse.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  /// Get QR / device usage info（扫码绑定设备用）.
  Future<HuishApiResponse> getDeviceQr(String deviceId) async {
    final resp = await _get('/api/v1/qr/use?id=$deviceId');
    return HuishApiResponse.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  // ── 账单 / 钱包 ──────────────────────────────────────────

  Future<HuishApiResponse> getWalletOwner(String eid) async {
    final resp = await _get('/api/v1/acc/wallet/owner?eid=$eid&all=true');
    return HuishApiResponse.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<HuishApiResponse> getBillList({
    int page = 0,
    int size = 20,
    int? status,
  }) async {
    final statusStr = status != null ? '&status=$status' : '';
    final resp = await _get(
      '/api/v1/bill/lst-owner?page=$page&size=$size&hasCount=true$statusStr',
    );
    return HuishApiResponse.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  /// Get bill full detail.
  Future<HuishApiResponse> getBillDetail(String billId) async {
    final resp = await _get('/api/v1/bill/view-full?id=$billId');
    return HuishApiResponse.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  // ── 底层 HTTP ────────────────────────────────────────────
  // 构造时若注入了 logger，_client 会包装 _LoggingClient 自动记录 HTTP 层（method/url/status）。
  // 这里再解析响应体，记录业务层（code/msg），便于定位接口失败根因。

  /// 从响应体里提取 code/msg，记一条业务日志（未注入 logger 时空操作）。
  void _logBizResponse(String path, http.Response resp) {
    final logger = _logger;
    if (logger == null) return;
    try {
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final code = json['code'] ?? '?';
      final msg = json['msg'] ?? '';
      // 路径截取最后一段作为接口名，日志更紧凑
      final apiName = path.split('?').first.split('/').last;
      logger('HUISH-BIZ', '$apiName → code=$code msg="$msg"');
      // 登录/发验证码接口：额外把完整响应和关键 request headers 打出来方便排查
      if (path.contains('/acc/login') || path.contains('/login/code')) {
        logger('HUISH-DEBUG',
            '[login-debug] status=${resp.statusCode} ua=${_baseHeaders['user-agent']} vcode=${_baseHeaders['VersionCode']} set-cookie=${resp.headers['set-cookie']} body=${resp.body.substring(0, resp.body.length > 300 ? 300 : resp.body.length)}');
      }
    } catch (_) {
      logger(
        'HUISH-BIZ',
        '解析响应失败: ${resp.body.substring(0, resp.body.length > 200 ? 200 : resp.body.length)}',
      );
    }
  }

  Future<http.Response> _get(String path) async {
    final url = Uri.parse('$_baseUrl$path');
    final resp = await _client.get(url, headers: _authHeaders);
    _saveCookies(resp);
    _logBizResponse(path, resp);
    return resp;
  }

  Future<http.Response> _post(
    String path, {
    required Map<String, dynamic> data,
    Map<String, String>? query,
  }) async {
    var urlStr = '$_baseUrl$path';
    if (query != null && query.isNotEmpty) {
      final qs = query.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      urlStr = '$urlStr?$qs';
    }
    final url = Uri.parse(urlStr);
    final hdrs = {
      ..._authHeaders,
      'Content-Type': 'application/json; charset=UTF-8',
    };
    final body = jsonEncode(data);
    // login/sendSms：发出前把完整 headers + body 打出来，方便和命令行请求对比
    final logger = _logger;
    if (logger != null && (path.contains('/acc/login') || path.contains('/login/code'))) {
      logger('HUISH-OUT',
          '[out] POST $path\n  headers=$hdrs\n  body=$body');
    }
    final resp = await _client.post(url, headers: hdrs, body: body);
    _saveCookies(resp);
    _logBizResponse(path, resp);
    return resp;
  }

  void dispose() => _client.close();
}

class HuishCaptchaResult {
  final double s;
  final int r;
  final List<int> imageBytes;
  final String contentType;
  HuishCaptchaResult({
    required this.s,
    required this.r,
    required this.imageBytes,
    required this.contentType,
  });
}

class HuishApiResponse {
  final int code;
  final dynamic data;
  final int? time;
  final String msg; // 服务端返回的错误消息（如"设备未绑定"等）
  HuishApiResponse({required this.code, this.data, this.time, this.msg = ''});
  factory HuishApiResponse.fromJson(Map<String, dynamic> json) {
    return HuishApiResponse(
      code: json['code'] as int? ?? -1,
      data: json['data'],
      time: json['time'] as int?,
      msg: (json['msg'] as String?) ?? '',
    );
  }
  bool get isSuccess => code == 0;
  Map<String, dynamic>? get dataMap =>
      data is Map<String, dynamic> ? data : null;
  List<dynamic>? get dataList => data is List<dynamic> ? data : null;
}

/// 模块内 HTTP 日志装饰器：宿主通过 `HuishApiClient(logger: ...)` 注入
/// 日志接收器后自动记录每笔请求/响应（tag 固定 HUISH）。
/// 模块自身不依赖任何宿主日志实现，未注入时不包装。
class _LoggingClient extends http.BaseClient {
  _LoggingClient(this._inner, this._logger);
  final http.Client _inner;
  final void Function(String tag, String msg) _logger;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final uri = request.url;
    _logger('HUISH→', '${request.method.toUpperCase()} $uri');
    final response = await _inner.send(request);
    _logger(
      'HUISH←',
      '${response.statusCode} ${uri.path}${request.contentLength != null ? ' len=${request.contentLength}' : ''}',
    );
    return response;
  }

  @override
  void close() => _inner.close();
}
