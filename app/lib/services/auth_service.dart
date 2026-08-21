import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cache_service.dart';

class AuthPrefs {
  static const kRemember = 'remember_password';
  static const kAutoLogin = 'auto_login';
}

class AuthService {
  AuthService({FlutterSecureStorage? storage, this.cache})
      : _storage = storage ?? const FlutterSecureStorage();
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

  Future<void> setAutoLogin(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(AuthPrefs.kAutoLogin, v);
  }

  Future<bool> getAutoLogin() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(AuthPrefs.kAutoLogin) ?? false;
  }

  Future<void> logoutAll() async {
    await clearAccount();
    await setRemember(false);
    await setAutoLogin(false);
    await cache?.clearAll();
  }
}
