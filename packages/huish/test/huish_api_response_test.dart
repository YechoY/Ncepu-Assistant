// huish 模块测试 —— API 响应模型（huish_api_client.dart 的 HuishApiResponse）。

import 'package:flutter_test/flutter_test.dart';
import 'package:huish/src/huish_api_client.dart';

void main() {
  group('HuishApiResponse.fromJson', () {
    test('正常响应：code=0', () {
      final r = HuishApiResponse.fromJson({
        'code': 0,
        'msg': 'ok',
        'data': {'a': 1},
        'time': 1700000000,
      });
      expect(r.code, 0);
      expect(r.msg, 'ok');
      expect(r.time, 1700000000);
      expect(r.isSuccess, isTrue);
    });

    test('code 缺省时归为 -1（视为失败）', () {
      final r = HuishApiResponse.fromJson({'msg': 'x'});
      expect(r.code, -1);
      expect(r.isSuccess, isFalse);
    });

    test('msg 缺省归为空串，null 同理', () {
      expect(HuishApiResponse.fromJson({}).msg, '');
      expect(HuishApiResponse.fromJson({'msg': null}).msg, '');
    });

    test('dataMap：data 为对象时返回映射', () {
      final r = HuishApiResponse.fromJson({
        'code': 0,
        'data': {'gene': {'status': 1}},
      });
      expect(r.dataMap, isNotNull);
      expect(r.dataMap!['gene'], isA<Map<String, dynamic>>());
      expect(r.dataList, isNull);
    });

    test('dataList：data 为数组时返回列表', () {
      final r = HuishApiResponse.fromJson({
        'code': 0,
        'data': [1, 2, 3],
      });
      expect(r.dataList, isNotNull);
      expect(r.dataList!.length, 3);
      expect(r.dataMap, isNull);
    });

    test('data 为字符串时 dataMap/dataList 均为 null', () {
      final r = HuishApiResponse.fromJson({'code': 0, 'data': 'plain'});
      expect(r.dataMap, isNull);
      expect(r.dataList, isNull);
    });
  });
}
