// huish 模块测试 —— 积分领取签名算法（sign_utils.dart）。

import 'package:flutter_test/flutter_test.dart';
import 'package:huish/src/sign_utils.dart';

const _token = 'aaaaaaaaaaaaaaaa12345678';
const _uid = 'zzzzzzzzzzzz87654321';

Future<String> sign({
  String adId = 'ad-0001',
  String token = _token,
  String uid = _uid,
}) => Future.value(
  HuishSignUtils.generateScoreSign(
    adId: adId,
    token: token,
    uid: uid,
    localTs: 1700000000,
    serverTs: 1700000050,
  ),
);

void main() {
  group('generateScoreSign', () {
    test('输出 32 位十六进制（MD5）', () async {
      final s = await sign();
      expect(s, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('同一 10 秒窗口内签名稳定（v20 以 10s 粒度取整）', () async {
      expect(await sign(), await sign());
    });

    test('不同 adId 产生不同签名', () async {
      expect(await sign(adId: 'ad-0001'), isNot(await sign(adId: 'ad-0002')));
    });

    test('uid 尾 8 位参与签名（换尾段签名改变）', () async {
      final altUid = '${_uid.substring(0, _uid.length - 8)}AAAAAAAA';
      expect(await sign(uid: altUid), isNot(await sign()));
    });

    test('token 尾 8 位参与签名（换尾段签名改变）', () async {
      final altToken = '${_token.substring(0, _token.length - 8)}BBBBBBBB';
      expect(await sign(token: altToken), isNot(await sign()));
    });
  });
}
