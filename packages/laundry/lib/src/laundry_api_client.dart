// U净（Ujing）洗衣平台 API 客户端。
// 协议对齐参考项目 FlandreSY（真机验证可用）：IoUjingTransport / UjingHttpAdapter。
//
// 要点：
// - BASE：https://phoenix.ujing.online/api/v1/
// - 固定伪装头：x-app-version=2.4.14 / 机型华为 / UA okhttp/4.3.1（对齐官方 App）
// - 认证：authorization: Bearer <token>（login 返回），辅助：服务端 Set-Cookie 记入内存 jar
// - 响应信封：code==0 成功，data 为业务数据；401/403 → authInvalid（上层清凭证重登）
// - 业务区分：appCode 登录用 ZA，洗衣用 BA，饮水用 CA（同一账户体系共享余额）
// - 日志：构造注入（宿主把全局调试日志传进来），缺省 no-op，模块可独立复用

import 'dart:convert';

import 'package:http/http.dart' as http;

/// U净业务异常。[authInvalid] 为 true 时上层应清除本地凭证并要求重新登录。
class LaundryException implements Exception {
  final String message;
  final String? code;
  final bool authInvalid;
  const LaundryException(this.message, {this.code, this.authInvalid = false});

  @override
  String toString() => message;
}

/// 已扫洗衣机 + 可选套餐（scanWasher 返回）。
class WasherProgram {
  final String deviceId;
  final String deviceNo;
  final String deviceTypeName;
  final String storeName;
  final String status;
  final String reason; // 不可下单原因（createOrderEnabled=false 时有值）
  final bool createOrderEnabled;
  final int defaultWashModelId;
  final List<WashModel> models;

  const WasherProgram({
    required this.deviceId,
    required this.deviceNo,
    required this.deviceTypeName,
    required this.storeName,
    required this.status,
    required this.reason,
    required this.createOrderEnabled,
    required this.defaultWashModelId,
    required this.models,
  });
}

/// 设备展示号：优先 deviceNo；不可下单响应缺 deviceNo 时用二维码 cd 参数兜底，
/// 再退回 deviceId（收藏去重 / 首页徽标 key 都用它，务必稳定）。
String washerDisplayNo(WasherProgram p, String qrCode) {
  if (p.deviceNo.isNotEmpty) return p.deviceNo;
  final cd = Uri.tryParse(qrCode)?.queryParameters['cd'];
  if (cd != null && cd.isNotEmpty) return cd;
  return p.deviceId;
}

/// 常用洗衣机状态（scanWasherCode 轻量查询：只看可用性，不拉套餐）。
class WasherDeviceStatus {
  final String status; // 服务端原始状态码
  final String reason; // 不可下单原因（离线/使用中/故障等，人话）
  final bool createOrderEnabled;

  const WasherDeviceStatus({
    required this.status,
    required this.reason,
    required this.createOrderEnabled,
  });

  bool get available => createOrderEnabled;

  /// 徽标文案：可用 → 空闲；不可用 → 服务端原因（超长截断）。
  String get label {
    if (createOrderEnabled) return '空闲可下单';
    final r = reason.trim();
    if (r.isEmpty) return '暂不可用';
    return r.length > 8 ? '${r.substring(0, 8)}…' : r;
  }
}

/// 洗衣套餐（标准洗/快洗/大件等）。
class WashModel {
  final int id; // workModelId
  final String name; // workModelName
  final int priceFen; // basePrice（分）
  final int timeMinutes; // time
  final List<WasherAdditionGroup> additionGroups; // 加液分组（洗衣液/除菌液）
  const WashModel({
    required this.id,
    required this.name,
    required this.priceFen,
    required this.timeMinutes,
    this.additionGroups = const [],
  });

  String get priceText => '¥${(priceFen / 100).toStringAsFixed(2)}';

  /// 取指定 key 的加液档位（wp_detergentGearId / wp_disinfectantGearId）。
  List<WasherAdditionOption> additionOptions(String key) {
    for (final g in additionGroups) {
      if (g.key == key) return g.options;
    }
    return const [];
  }
}

/// 加液分组：key 为 wp_detergentGearId（洗衣液）/ wp_disinfectantGearId（除菌液）。
class WasherAdditionGroup {
  final String key;
  final String name;
  final List<WasherAdditionOption> options;
  const WasherAdditionGroup({
    required this.key,
    required this.name,
    required this.options,
  });
}

/// 加液档位（一档 = 一种用量）。
class WasherAdditionOption {
  final int id;
  final String name;
  final int priceFen;
  const WasherAdditionOption({
    required this.id,
    required this.name,
    required this.priceFen,
  });

  String get priceText => '¥${(priceFen / 100).toStringAsFixed(2)}';
}

/// 洗衣水温档（washTemperatureId → 名称）。官方 App 固定四档。
const Map<int, String> kWasherTemperatures = <int, String>{
  1: '常温',
  2: '30°C',
  3: '40°C',
  4: '60°C',
};

/// 水温档固定价表（分）：常温 0 / 30°C=1.0 / 40°C=1.5 / 60°C=2.0（对齐参考项目拍板值）。
/// 预估总价静默纳入水温价，让 UI 预估 == 真机实收。
const Map<int, int> kWasherTemperaturePriceFen = <int, int>{
  1: 0,
  2: 100,
  3: 150,
  4: 200,
};

/// 洗衣订单。
/// status：10 待支付 / 20 已预约 / 21 启动中 / 40 运行中 / 50 完成。
class WasherOrder {
  final String orderId;
  final String deviceNo;
  final String status; // 服务端状态码（字符串）
  final String statusText; // statusRemark，人话描述
  final String payPrice; // 已格式化（¥x.xx）
  final int remainTimeSeconds; // 运行剩余秒
  final int countDownSeconds; // 启动倒计时秒

  const WasherOrder({
    required this.orderId,
    required this.deviceNo,
    required this.status,
    required this.statusText,
    required this.payPrice,
    this.remainTimeSeconds = 0,
    this.countDownSeconds = 0,
  });

  static const statusPendingPay = '10';
  static const statusReserved = '20';
  static const statusStarting = '21';
  static const statusRunning = '40';
  static const statusDone = '50';

  bool get canPay => status == statusPendingPay;
  bool get canStart => status == statusReserved;
  bool get canStop => status == statusStarting || status == statusRunning;
  bool get canCancel => status == statusPendingPay || status == statusReserved;
  bool get isFinished => status == statusDone;

  /// 调试用：本地复制并改状态/剩余时间（不写服务端），用于预览支付后各阶段 UI。
  WasherOrder copyWithStatus(
    String status,
    String statusText, {
    int? remainTimeSeconds,
  }) =>
      WasherOrder(
        orderId: orderId,
        deviceNo: deviceNo,
        status: status,
        statusText: statusText,
        payPrice: payPrice,
        remainTimeSeconds: remainTimeSeconds ?? this.remainTimeSeconds,
        countDownSeconds: countDownSeconds,
      );
}

/// 支付参数拉取结果：orderInfo 为支付宝 SDK 串（需原生 SDK），
/// h5Url 为 H5 支付链接（可 url_launcher 拉起）。二者必有其一。
class PaymentArgs {
  final String orderInfo;
  final String h5Url;
  const PaymentArgs({required this.orderInfo, required this.h5Url});
}

class LaundryApiClient {
  LaundryApiClient({void Function(String message)? logger, http.Client? client})
    : _log = logger ?? ((_) {}),
    // 建议宿主注入 LoggingHttpClient 以接入全局调试日志。
    _client = client ?? http.Client();

  static const baseUrl = 'https://phoenix.ujing.online/api/v1/';

  // 固定伪装头（对齐参考项目 legacy UjingApi.java，真机验证通过）
  static const _appVersion = '2.4.14';
  static const _model = 'HBN-AL00';
  static const _brand = 'HUAWEI';
  static const _userAgent = 'okhttp/4.3.1';
  static const _weex = '1.1.68'; // 洗衣业务固定 weex-version

  final void Function(String message) _log;
  final http.Client _client;

  /// 登录 token（login 成功后置位；authInvalid 后清空）。
  String? token;
  String? userId;
  String? serviceSubjectId;

  /// 内存 cookie jar（服务端下发的 Set-Cookie，辅助会话）。
  final Map<String, String> _cookies = {};

  // ===== 请求底层 =====

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    String appCode = 'BA',
    String? weex,
    bool auth = false,
    Map<String, Object?>? query,
    Map<String, Object?>? body,
  }) async {
    if (auth && (token == null || token!.isEmpty)) {
      throw const LaundryException('请先登录 U净账号');
    }
    final uri = Uri.parse(baseUrl + path).replace(
      queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
    );
    final headers = <String, String>{
      'x-mobile-brand': _brand,
      'x-mobile-id': '',
      'x-app-code': appCode,
      'x-app-version': _appVersion,
      'x-mobile-model': _model,
      'user-agent': _userAgent,
      if (weex != null && weex.isNotEmpty) 'weex-version': weex,
      if (auth && token != null) 'authorization': 'Bearer $token',
      if (_cookies.isNotEmpty) 'cookie': _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
    };
    _log('洗衣 → $method ${uri.path}${query == null ? '' : ' $query'}');
    final http.Response resp;
    try {
      resp = method == 'GET'
          ? await _client.get(uri, headers: headers)
          : await _client.post(
              uri,
              headers: headers..['content-type'] = 'application/json; charset=utf-8',
              body: body == null ? null : utf8.encode(jsonEncode(body)),
            );
    } catch (e) {
      throw LaundryException('网络请求失败（${e.runtimeType}）');
    }
    _rememberCookies(resp);
    _log('洗衣 ← HTTP ${resp.statusCode}');
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw LaundryException(
        'HTTP ${resp.statusCode}，请求未完成',
        code: '${resp.statusCode}',
        authInvalid: resp.statusCode == 401 || resp.statusCode == 403,
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      throw const LaundryException('响应不是合法 JSON，结果未确认');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const LaundryException('响应格式异常（顶层非对象）');
    }
    final code = decoded['code'];
    if (code is! num) {
      throw const LaundryException('响应缺少有效成功码，结果未确认');
    }
    if (code != 0) {
      final msg = decoded['message'];
      final invalid = code == 401 || code == 403;
      throw LaundryException(
        msg is String && msg.isNotEmpty ? msg : '接口返回错误 code=$code',
        code: '$code',
        authInvalid: invalid,
      );
    }
    final data = decoded['data'];
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  void _rememberCookies(http.Response resp) {
    // http 包对多段 set-cookie 拼在一个头里（逗号分隔），粗略拆 name=value 对。
    final raw = resp.headers['set-cookie'];
    if (raw == null) return;
    for (final part in raw.split(',')) {
      final seg = part.trim().split(';').first;
      final eq = seg.indexOf('=');
      if (eq > 0) {
        _cookies[seg.substring(0, eq).trim()] = seg.substring(eq + 1).trim();
      }
    }
  }

  /// authInvalid 异常统一转出口：清凭证后原样抛出。
  Never _rethrowAuth(LaundryException e) {
    if (e.authInvalid) {
      _log('洗衣凭证已失效，需重新登录');
      token = null;
    }
    throw e;
  }

  /// 扫码/下单后统一包一层（服务端拒绝时清凭证 + 清已扫缓存）。
  Future<T> _guarded<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on LaundryException catch (e) {
      _rethrowAuth(e);
    }
  }

  // ===== 账号 =====

  /// 发送短信验证码（AFS 人机验证以固定参数绕过，对齐官方 App 行为）。
  Future<void> requestCaptcha(String mobile) => _guarded(() async {
    _log('洗衣请求验证码');
    await _send(
      'GET',
      'captcha',
      appCode: 'ZA',
      query: {
        'mobile': mobile,
        'type': 1,
        'sessionId': 'AFS_SWITCH_OFF',
        'token': 'AFS_SWITCH_OFF',
        'sig': 'AFS_SWITCH_OFF',
      },
    );
  });

  /// 短信验证码登录，返回 userId / serviceSubjectId 并持有 token。
  Future<void> login(String mobile, String captcha) => _guarded(() async {
    final data = await _send(
      'POST',
      'login',
      appCode: 'ZA',
      body: {'mobile': mobile, 'captcha': captcha},
    );
    final t = data['token'];
    if (t is! String || t.trim().isEmpty) {
      throw const LaundryException('登录响应缺少有效 token，结果未确认');
    }
    token = t;
    userId = _str(data, 'userId');
    serviceSubjectId = _str(data, 'serviceSubjectId');
    _log('洗衣登录成功');
  });

  /// 当前账户余额（分）。洗衣与饮水共用 U净账户。
  Future<int> fetchBalanceFen() => _guarded(() async {
    final data = await _send(
      'GET',
      'app/water/serviceSubject/currentInfo',
      appCode: 'CA',
      auth: true,
    );
    final bal = _num(data, 'balance');
    return bal.round();
  });

  // ===== 洗衣主流程 =====

  /// 扫码识别洗衣机并拉取套餐。不可下单时返回 createOrderEnabled=false + reason。
  Future<WasherProgram> scanWasher(String qrCode) => _guarded(() async {
    final scan = await _send(
      'POST',
      'devices/scanWasherCode',
      weex: _weex,
      auth: true,
      body: {'qrCode': qrCode.trim()},
    );
    final result = _obj(scan, 'result');
    final deviceId = _required(result, 'deviceId');
    final deviceTypeId = _int(result, 'deviceTypeId');
    final createOrderEnabled = _bool(result, 'createOrderEnabled');
    final status = _str(result, 'status');
    final reason = _str(result, 'reason');

    if (!createOrderEnabled) {
      _log('设备不可下单：$reason');
      return WasherProgram(
        deviceId: deviceId,
        deviceNo: '',
        deviceTypeName: '',
        storeName: '',
        status: status,
        reason: reason,
        createOrderEnabled: false,
        defaultWashModelId: 0,
        models: const [],
      );
    }

    final info = await _send(
      'GET',
      'app/washer/devices/program/info',
      weex: _weex,
      auth: true,
      query: {'deviceId': deviceId},
    );
    final storeId = _required(info, 'storeId');
    final models = <WashModel>[];
    final rawModels = info['deviceWashModel'];
    if (rawModels is List) {
      for (final item in rawModels) {
        if (item is! Map) continue;
        final m = item.cast<String, dynamic>();
        models.add(
          WashModel(
            id: _int(m, 'workModelId'),
            name: _str(m, 'workModelName'),
            priceFen: _int(m, 'basePrice'),
            timeMinutes: _int(m, 'time'),
            additionGroups: _parseAdditions(m),
          ),
        );
      }
    }
    // 默认套餐：优先 workModelId=1（标准洗），否则第一个。
    var defaultId = 0;
    for (final m in models) {
      if (m.id == 1) {
        defaultId = 1;
        break;
      }
    }
    if (defaultId == 0 && models.isNotEmpty) defaultId = models.first.id;
    // storeId/deviceTypeId 是下单必需字段，随扫码结果缓存到实例。
    _scanned = _Scanned(
      deviceId: deviceId,
      deviceTypeId: deviceTypeId,
      storeId: storeId,
    );
    return WasherProgram(
      deviceId: deviceId,
      deviceNo: _str(info, 'deviceNo'),
      deviceTypeName: _str(info, 'deviceTypeName'),
      storeName: _str(info, 'storeName'),
      status: status,
      reason: reason,
      createOrderEnabled: true,
      defaultWashModelId: defaultId,
      models: models,
    );
  });

  _Scanned? _scanned;

  /// 创建订单（扫码成功后调用）。返回 orderId。
  /// [detergentGearId] / [disinfectantGearId] 为可选加液档位（null = 不添加）。
  Future<String> createOrder({
    required int washModelId,
    required int temperatureId,
    int? detergentGearId,
    int? disinfectantGearId,
  }) => _guarded(() async {
    final s = _scanned;
    if (s == null || s.storeId.isEmpty) {
      throw const LaundryException('请先扫描洗衣机并获取套餐');
    }
    final body = <String, Object?>{
      'type': 1,
      'deviceTypeId': s.deviceTypeId,
      'deviceId': s.deviceId,
      'deviceWashModelId': washModelId,
      'storeId': s.storeId,
      'washTemperatureId': temperatureId,
      if (detergentGearId != null) 'wp_detergentGearId': detergentGearId,
      if (disinfectantGearId != null) 'wp_disinfectantGearId': disinfectantGearId,
    };
    final created = await _send(
      'POST',
      'orders/create',
      weex: _weex,
      auth: true,
      body: body,
    );
    final orderId = _required(created, 'orderId');
    if (orderId == '0') {
      throw const LaundryException('创建订单结果未确认，缺少有效 orderId');
    }
    _log('订单已创建 orderId=$orderId');
    return orderId;
  });

  /// 查询订单详情。
  Future<WasherOrder> fetchOrder(String orderId) => _guarded(() async {
    final detail = await _send(
      'GET',
      'orders/$orderId/detail',
      weex: _weex,
      auth: true,
    );
    return WasherOrder(
      orderId: orderId,
      deviceNo: _str(detail, 'deviceNo'),
      status: _str(detail, 'status'),
      statusText: _str(detail, 'statusRemark', fallback: _str(detail, 'status')),
      payPrice: _formatPrice(detail['payPrice']),
      remainTimeSeconds: _int(detail, 'remainTime'),
      countDownSeconds: _int(detail, 'countDown'),
    );
  });

  /// 拉起支付参数。h5Url 可用 url_launcher 打开；orderInfo 需要支付宝原生 SDK。
  Future<PaymentArgs> fetchPaymentArgs(String orderId) => _guarded(() async {
    final args = await _send(
      'GET',
      'payment/arguments',
      weex: _weex,
      auth: true,
      query: {
        'channel': 'alipay',
        'orderId': orderId,
        'couponId': '',
        'isUseRedPacket': false,
        'redPacketId': 0,
        'alipayF2FNoAds': false,
        'branchType': 0,
        'jumpToAliMini': false,
        'payVersion': 1,
      },
    );
    final payInfo = _obj(args, 'payInfo');
    final orderInfo = payInfo['orderInfo'];
    final h5 = _str(payInfo, 'h5_url');
    if (orderInfo is! String || orderInfo.trim().isEmpty) {
      if (payInfo.containsKey('prepayid') || payInfo.containsKey('prepayId')) {
        throw const LaundryException('服务端返回了微信支付参数，当前只支持支付宝');
      }
      if (h5.isEmpty) {
        throw const LaundryException('支付宝支付参数缺少 orderInfo');
      }
    }
    return PaymentArgs(orderInfo: orderInfo is String ? orderInfo : '', h5Url: h5);
  });

  /// 常用设备状态速查：只走 scanWasherCode 一步（不拉套餐/型号），供首页徽标轮询。
  Future<WasherDeviceStatus> fetchDeviceStatus(String qrCode) =>
      _guarded(() async {
        final scan = await _send(
          'POST',
          'devices/scanWasherCode',
          weex: _weex,
          auth: true,
          body: {'qrCode': qrCode.trim()},
        );
        final result = _obj(scan, 'result');
        return WasherDeviceStatus(
          status: _str(result, 'status'),
          reason: _str(result, 'reason'),
          createOrderEnabled: _bool(result, 'createOrderEnabled'),
        );
      });

  /// 启动洗衣机（已支付/已预约后）。
  Future<WasherOrder> startOrder(String orderId) => _guarded(() async {
    await _send('GET', 'orders/$orderId/control/start', weex: _weex, auth: true);
    _log('启动请求已确认');
    return fetchOrder(orderId);
  });

  /// 提前停止洗衣机。
  Future<WasherOrder> stopOrder(String orderId) => _guarded(() async {
    await _send('GET', 'orders/$orderId/control/stop', weex: _weex, auth: true);
    _log('停止请求已确认');
    return fetchOrder(orderId);
  });

  /// 取消订单（待支付/已预约时）。
  Future<void> cancelOrder(String orderId) => _guarded(() async {
    await _send(
      'POST',
      'orders/$orderId/cancel',
      weex: _weex,
      auth: true,
      body: {'orderId': orderId},
    );
    _log('订单已取消 orderId=$orderId');
  });

  // ===== 解析 helpers（容错 int/string/bool）=====

  /// 套餐附加项解析：additionDevices 可能是直接数组，
  /// 或嵌套 {washingPartnerFeature: [...]}（对齐参考项目 ujing_http_adapter）。
  static List<WasherAdditionGroup> _parseAdditions(Map<String, dynamic> modelJson) {
    final direct = modelJson['additionDevices'];
    List<dynamic>? additions;
    if (direct is List) {
      additions = direct;
    } else if (direct is Map) {
      final nested = direct['washingPartnerFeature'];
      if (nested is List) additions = nested;
    }
    if (additions == null) return const [];
    final groups = <WasherAdditionGroup>[];
    for (final a in additions) {
      if (a is! Map) continue;
      final map = a.cast<String, dynamic>();
      final key = _str(map, 'key');
      if (key.isEmpty) continue;
      final options = <WasherAdditionOption>[];
      final rawOptions = map['options'];
      if (rawOptions is List) {
        for (final o in rawOptions) {
          if (o is! Map) continue;
          final om = o.cast<String, dynamic>();
          options.add(
            WasherAdditionOption(
              id: _int(om, 'id'),
              name: _str(om, 'name'),
              priceFen: _int(om, 'price'),
            ),
          );
        }
      }
      if (options.isEmpty) continue;
      groups.add(
        WasherAdditionGroup(key: key, name: _str(map, 'name'), options: options),
      );
    }
    return groups;
  }

  static String _required(Map<String, dynamic> m, String key) {
    final v = m[key];
    if ((v is String && v.trim().isNotEmpty) || (v is num && v.isFinite)) {
      return '$v';
    }
    throw const LaundryException('响应缺少必要信息，结果未确认');
  }

  static String _str(Map<String, dynamic> m, String key, {String fallback = ''}) {
    final v = m[key];
    if (v == null) return fallback;
    if (v is String) return v.isEmpty ? fallback : v;
    return '$v';
  }

  static int _int(Map<String, dynamic> m, String key, {int fallback = 0}) {
    final v = m[key];
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static num _num(Map<String, dynamic> m, String key, {num fallback = 0}) {
    final v = m[key];
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? fallback;
    return fallback;
  }

  static bool _bool(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.toLowerCase() == 'true' || v == '1';
    return false;
  }

  static Map<String, dynamic> _obj(Map<String, dynamic> m, String key) {
    final v = m[key];
    return v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
  }

  static String _formatPrice(Object? v) {
    if (v == null) return '';
    if (v is num) return '¥${v.toStringAsFixed(2)}';
    final n = num.tryParse('$v');
    if (n != null) return '¥${n.toStringAsFixed(2)}';
    return '$v';
  }
}

/// 扫码后缓存的下单必需字段（套餐接口返回，创建订单用）。
class _Scanned {
  const _Scanned({
    required this.deviceId,
    required this.deviceTypeId,
    required this.storeId,
  });
  final String deviceId;
  final int deviceTypeId;
  final String storeId;
}
