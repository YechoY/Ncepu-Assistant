// huish_auth_state.dart —— 饮水模块登录状态（独立 Riverpod，与教务 auth_state 互不污染）。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'huish_api_client.dart';

final huishApiClientProvider = Provider<HuishApiClient>((ref) {
  return HuishApiClient();
});

final huishAuthStateProvider =
    NotifierProvider<HuishAuthNotifier, HuishAuthState>(HuishAuthNotifier.new);

class HuishAuthState {
  final bool loggedIn;
  final String? phone;
  final String? uid;
  final String? eid;
  final String? token;
  final String? error;
  HuishAuthState({
    this.loggedIn = false,
    this.phone,
    this.uid,
    this.eid,
    this.token,
    this.error,
  });
  HuishAuthState copyWith({
    bool? loggedIn,
    String? phone,
    String? uid,
    String? eid,
    String? token,
    String? error,
    bool clearError = false,
  }) {
    return HuishAuthState(
      loggedIn: loggedIn ?? this.loggedIn,
      phone: phone ?? this.phone,
      uid: uid ?? this.uid,
      eid: eid ?? this.eid,
      token: token ?? this.token,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class HuishAuthNotifier extends Notifier<HuishAuthState> {
  late final HuishApiClient _api;

  @override
  HuishAuthState build() {
    _api = ref.watch(huishApiClientProvider);
    _tryRestore();
    return HuishAuthState();
  }

  Future<void> _tryRestore() async {
    final ok = await _api.restoreToken();
    if (ok && _api.token != null) {
      state = state.copyWith(
        loggedIn: true,
        uid: _api.uid,
        eid: _api.eid,
        token: _api.token,
      );
    }
  }

  Future<bool> login(String phone, String smsCode) async {
    state = state.copyWith(clearError: true);
    final resp = await _api.login(phone: phone, smsCode: smsCode);
    if (resp.isSuccess) {
      state = state.copyWith(
        loggedIn: true,
        phone: phone,
        uid: _api.uid,
        eid: _api.eid,
        token: _api.token,
      );
      return true;
    } else {
      state = state.copyWith(error: '登录失败 (code: ${resp.code})');
      return false;
    }
  }

  Future<void> logout() async {
    await _api.clearToken();
    state = HuishAuthState();
  }
}
