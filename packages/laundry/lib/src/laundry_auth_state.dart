// 洗衣模块登录态（Riverpod StateNotifier）。
// 凭证持久化到 flutter_secure_storage（Android Keystore），key 前缀 laundry_
// 与其他模块完全隔离。token 重启恢复 → 免重登；401/403 时 clear 要求重登。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'laundry_api_client.dart';

class LaundryAuthState {
  const LaundryAuthState({
    this.restored = false,
    this.loggedIn = false,
    this.mobile = '',
  });

  /// 首次从安全存储恢复完成。
  final bool restored;
  final bool loggedIn;
  final String mobile;

  LaundryAuthState copyWith({bool? restored, bool? loggedIn, String? mobile}) =>
      LaundryAuthState(
        restored: restored ?? this.restored,
        loggedIn: loggedIn ?? this.loggedIn,
        mobile: mobile ?? this.mobile,
      );
}

class LaundryAuthNotifier extends StateNotifier<LaundryAuthState> {
  LaundryAuthNotifier(this._api) : super(const LaundryAuthState()) {
    _restore();
  }

  final LaundryApiClient _api;

  /// 共享的 API 客户端（登录页/首页都通过 [laundryApiProvider] 拿同一实例）。
  LaundryApiClient get api => _api;
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kToken = 'laundry_token';
  static const _kUserId = 'laundry_user_id';
  static const _kSubject = 'laundry_subject_id';
  static const _kMobile = 'laundry_mobile';

  Future<void> _restore() async {
    try {
      final token = await _storage.read(key: _kToken);
      if (token != null && token.isNotEmpty) {
        _api.token = token;
        _api.userId = await _storage.read(key: _kUserId);
        _api.serviceSubjectId = await _storage.read(key: _kSubject);
        final mobile = await _storage.read(key: _kMobile) ?? '';
        state = state.copyWith(
          restored: true,
          loggedIn: true,
          mobile: mobile,
        );
        return;
      }
    } catch (_) {
      // 存储读取失败按未登录处理
    }
    state = state.copyWith(restored: true);
  }

  /// 等待凭证恢复完成（宿主跳转前调用；恢复异步启动后立即返回会误判未登录）。
  Future<void> ensureRestored() async {
    var waited = 0;
    while (!state.restored && waited < 2000) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      waited += 30;
    }
  }

  /// 发送验证码 → 登录 → 持久化凭证。
  Future<void> login(String mobile, String captcha) async {
    await _api.login(mobile, captcha);
    await _storage.write(key: _kToken, value: _api.token ?? '');
    await _storage.write(key: _kUserId, value: _api.userId ?? '');
    await _storage.write(key: _kSubject, value: _api.serviceSubjectId ?? '');
    await _storage.write(key: _kMobile, value: mobile);
    state = state.copyWith(loggedIn: true, mobile: mobile);
  }

  /// 服务端拒绝凭证（401/403）后调用：清本地凭证，回到登录页。
  Future<void> clearAuth() async {
    _api.token = null;
    _api.userId = null;
    _api.serviceSubjectId = null;
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kUserId);
    await _storage.delete(key: _kSubject);
    state = state.copyWith(loggedIn: false, mobile: '');
  }

  Future<void> logout() => clearAuth();
}

/// 模块级 Provider（不自挂 ProviderScope，宿主已有）。
final laundryAuthProvider =
    StateNotifierProvider<LaundryAuthNotifier, LaundryAuthState>((ref) {
      return LaundryAuthNotifier(LaundryApiClient());
    });

/// 与登录态共享的 API 客户端实例（token 状态一致）。
final laundryApiProvider = Provider<LaundryApiClient>((ref) {
  return ref.watch(laundryAuthProvider.notifier).api;
});
