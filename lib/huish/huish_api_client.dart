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

import '../core/debug_log.dart';
import '../core/logging_http_client.dart';

class HuishApiClient {
  static const String _baseUrl = 'https://i.ilife798.com';

  // Secure Storage keys（前缀 huish_ 与教务账号隔离）
  static const _kToken = 'huish_auth_token';
  static const _kUid = 'huish_auth_uid';
  static const _kEid = 'huish_auth_eid';

  // SHA256 fingerprints of trusted certificates (uppercase hex, colon-separated)
  // Get them: openssl s_client -connect i.ilife798.com:443 -servername i.ilife798.com </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256
  static const _pinnedCerts = <String>{
    // Replace with real fingerprint from the server
    'PLACEHOLDER',
  };

  late final http.Client _client;
  final _storage = const FlutterSecureStorage();

  String? _token;
  String? _uid;
  String? _eid;

  HuishApiClient() {
    _client = LoggingHttpClient(_createPinnedClient());
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

  // 协议对齐 NcepuJw 项目（华电同学做的、当前真机可用）：
  // 服务端 dev/start 最低版本校验 >3.1.4，NcepuJw 用 8.2.9 能过。
  // UA + VersionCode 必须配套：Android_ilife798_<版本>。
  // Accept-Language 是 NcepuJw 发的，不影响 dev/start，但对齐更保险。
  Map<String, String> get _baseHeaders => {
    'ApplicationType': '1,1',
    'VersionCode': '8.2.9',
    'user-agent': 'Android_ilife798_8.2.9',
    'Accept-Language': 'zh-Hans-CN;q=1',
  };

  Map<String, String> get _authHeaders {
    final h = <String, String>{..._baseHeaders};
    final t = _token;
    if (t != null) h['Authorization'] = t;
    return h;
  }

  Future<void> _persistToken() async {
    if (_token != null) {
      await _storage.write(key: _kToken, value: _token!);
      await _storage.write(key: _kUid, value: _uid ?? '');
      await _storage.write(key: _kEid, value: _eid ?? '');
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

  Future<void> clearToken() async {
    _token = null;
    _uid = null;
    _eid = null;
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kUid);
    await _storage.delete(key: _kEid);
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
    final resp = await _client.get(
      url,
      headers: {
        'User-Agent':
            'Dalvik/2.1.0 (Linux; U; Android 16; PHP110 Build/BP2A.250605.015)',
      },
    );
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

  Future<HuishApiResponse> login({
    required String phone,
    required String smsCode,
  }) async {
    final resp = await _post(
      '/api/v1/acc/login',
      data: {'openCode': '', 'un': phone, 'authCode': smsCode, 'cid': ''},
    );
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final result = HuishApiResponse.fromJson(json);
    if (result.code == 0 && json['data'] != null) {
      final al = json['data']['al'];
      if (al != null) {
        _token = al['token'] as String?;
        _uid = al['uid'] as String?;
        _eid = al['eid'] as String?;
        await _persistToken();
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
  // LoggingHttpClient 已在构造时包装 _client，自动记录 HTTP 层（method/url/status）。
  // 这里再解析响应体，记录业务层（code/msg），便于定位接口失败根因。

  /// 从响应体里提取 code/msg，记一条业务日志（开关关闭时零开销）。
  void _logBizResponse(String path, http.Response resp) {
    final dbg = AppDebugLog.instance;
    if (!dbg.isEnabled) return;
    try {
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final code = json['code'] ?? '?';
      final msg = json['msg'] ?? '';
      // 路径截取最后一段作为接口名，日志更紧凑
      final apiName = path.split('?').first.split('/').last;
      dbg.log('HUISH-BIZ', '$apiName → code=$code msg="$msg"');
    } catch (_) {
      dbg.log(
        'HUISH-BIZ',
        '解析响应失败: ${resp.body.substring(0, resp.body.length > 200 ? 200 : resp.body.length)}',
      );
    }
  }

  Future<http.Response> _get(String path) async {
    final url = Uri.parse('$_baseUrl$path');
    final resp = await _client.get(url, headers: _authHeaders);
    _logBizResponse(path, resp);
    return resp;
  }

  Future<http.Response> _post(
    String path, {
    required Map<String, dynamic> data,
  }) async {
    final url = Uri.parse('$_baseUrl$path');
    final resp = await _client.post(
      url,
      headers: {
        ..._authHeaders,
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(data),
    );
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
