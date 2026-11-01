import 'package:flutter_test/flutter_test.dart';
import 'package:hdjw_assistant/theme.dart';

void main() {
  test('课程配色稳定', () {
    expect(courseColor('数据结构'), courseColor('数据结构'));
  });
  test('8 色调色板数量', () {
    expect(coursePalette.length, 8);
  });
}
