import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import 'app_state.dart';

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(cache: ref.watch(cacheServiceProvider)),
);

class AuthState {
  final bool loggedIn;
  final String username;
  final String name;
  final String className;
  final String? error;
  const AuthState({
    this.loggedIn = false,
    this.username = '',
    this.name = '',
    this.className = '',
    this.error,
  });
}

final authStateProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  Future<bool> login(
    String username,
    String password, {
    required bool remember,
  }) async {
    final api = ref.read(apiClientProvider);
    final auth = ref.read(authServiceProvider);
    try {
      await api.login(username, password);
    } catch (e) {
      state = AuthState(error: _message(e));
      return false;
    }
    // 记住密码等本地存储可能因 secure storage 抛错，不应影响登录本身，单独容错
    try {
      await auth.setRemember(remember);
      if (remember) {
        await auth.saveAccount(username, password);
      } else {
        await auth.clearAccount();
      }
    } catch (_) {}
    String name = '';
    String className = '';
    // 用户信息是次要的，不阻塞登录；先设 loggedIn=true 让界面切到主界面，再后台拉取
    state = AuthState(loggedIn: true, username: username, name: name, className: className);
    try {
      final info = await api.fetchUserInfo();
      name = info.name;
      className = info.className;
      state = AuthState(loggedIn: true, username: username, name: name, className: className);
    } catch (_) {}
    return true;
  }

  /// 勾选了「记住账号密码」时，用本地保存的账号静默登录。
  /// 已合并原「自动登录」开关：只要记住了密码，下次启动就尝试登录。
  Future<bool> tryAutoLogin() async {
    final auth = ref.read(authServiceProvider);
    if (!await auth.getRemember()) return false;
    final acc = await auth.loadAccount();
    if (acc == null) return false;
    return login(acc.username, acc.password, remember: true);
  }

  Future<void> logout() async {
    // 同步清掉 ApiClient 里的会话 Cookie：否则旧 JSESSIONID 还在，
    // 之后再登录时即使密码错误也会被旧会话「顶替」而误判成功。
    ref.read(apiClientProvider).clearSession();
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
