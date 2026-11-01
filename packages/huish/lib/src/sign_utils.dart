// huish/sign_utils.dart —— 积分领取签名算法（原封不动搬自参考项目）。

import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;

class HuishSignUtils {
  static const _salt = 'aslkdvcniu34h9tgufh278wv2';

  static String generateScoreSign({
    required String adId,
    required String token,
    required String uid,
    required int localTs,
    required int serverTs,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final v20 = 10 * ((serverTs - localTs + nowMs) ~/ 10000);
    final raw =
        '$adId$v20${token.substring(token.length - 8)}${uid.substring(uid.length - 8)}$_salt';
    return crypto.md5.convert(utf8.encode(raw)).toString();
  }
}
