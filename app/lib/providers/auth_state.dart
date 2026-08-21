import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import 'app_state.dart';

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(cache: ref.watch(cacheServiceProvider)),
);

class AuthState {
  final bool loggedIn;
  final String username;
  final String? error;
  const AuthState({this.loggedIn = false, this.username = '', this.error});
}

final authStateProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  Future<bool> login(
    String username,
    String password, {
    required bool remember,
    required bool autoLogin,
  }) async {
    final api = ref.read(apiClientProvider);
    final auth = ref.read(authServiceProvider);
    try {
      await api.login(username, password);
    } catch (e) {
      state = AuthState(error: _message(e));
      return false;
    }
    await auth.setRemember(remember);
    await auth.setAutoLogin(autoLogin && remember);
    if (remember) {
      await auth.saveAccount(username, password);
    } else {
      await auth.clearAccount();
    }
    state = AuthState(loggedIn: true, username: username);
    return true;
  }

  Future<bool> tryAutoLogin() async {
    final auth = ref.read(authServiceProvider);
    if (!await auth.getRemember() || !await auth.getAutoLogin()) return false;
    final acc = await auth.loadAccount();
    if (acc == null) return false;
    return login(acc.username, acc.password, remember: true, autoLogin: true);
  }

  Future<void> logout() async {
    await ref.read(authServiceProvider).logoutAll();
    state = const AuthState();
  }

  String _message(Object e) {
    final s = e.toString();
    if (s.contains('TimeoutException')) return '连接超时，请检查网络后重试';
    if (s.contains('账号或密码')) return '账号或密码错误';
    if (s.contains('无法连接')) return s.replaceFirst('Exception: ', '');
    return '无法连接教务系统，请确认已连接校园网';
  }
}
