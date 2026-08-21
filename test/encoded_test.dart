import 'package:flutter_test/flutter_test.dart';
import 'package:hdjw_assistant/services/api_client.dart';

void main() {
  group('encoded 算法', () {
    test('标准种子 abc#1234567890', () {
      expect(encodeLogin('2025000001', 'mypass123', 'abc#1234567890'), '2a0bc25000001%%%mypass123');
    });
    test('分隔符 ;', () {
      expect(encodeLogin('2025000001', 'mypass123', 'a;1'), '2a025000001%%%mypass123');
    });
    test('sxh 长度不足按 0 处理', () {
      expect(encodeLogin('2025000002', 'pw', 'x#123'), '2x025000002%%%pw');
    });
    test('无分隔符抛错', () {
      expect(() => encodeLogin('a', 'b', 'noseparator'), throwsArgumentError);
    });
  });
}
