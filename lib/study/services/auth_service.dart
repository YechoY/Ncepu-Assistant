import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cache_service.dart';

class AuthPrefs {
  static const kRemember = 'remember_password';
}

class AuthService {
  AuthService({FlutterSecureStorage? storage, this.cache})
      // EncryptedSharedPreferences 模式：release 包 R8 混淆下无参默认模式的
      // keystore 加密读写会失败（表现为每次启动丢登录态），对齐洗衣模块修复。
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );
  final FlutterSecureStorage _storage;
  final CacheService? cache;

  Future<void> saveAccount(String username, String password) async {
    await _storage.write(key: 'username', value: username);
    await _storage.write(key: 'password', value: password);
  }

  Future<({String username, String password})?> loadAccount() async {
    final u = await _storage.read(key: 'username');
    final p = await _storage.read(key: 'password');
    if (u == null || p == null) return null;
    return (username: u, password: p);
  }

  Future<void> clearAccount() async {
    await _storage.delete(key: 'username');
    await _storage.delete(key: 'password');
  }

  Future<void> setRemember(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(AuthPrefs.kRemember, v);
  }

  Future<bool> getRemember() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(AuthPrefs.kRemember) ?? false;
  }

  Future<void> logoutAll() async {
    await clearAccount();
    await setRemember(false);
    await cache?.clearAll();
  }
}
