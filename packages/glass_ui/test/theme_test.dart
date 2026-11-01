// glass_ui 模块测试 —— 课程配色体系（theme.dart）。

import 'package:flutter_test/flutter_test.dart';
import 'package:glass_ui/glass_ui.dart';

void main() {
  group('coursePalette', () {
    test('12 色，每色三分量齐全', () {
      expect(coursePalette.length, 12);
      for (final c in coursePalette) {
        expect(c.bg, isNotNull);
        expect(c.border, isNotNull);
        expect(c.name, isNotNull);
      }
    });

    test('颜色互不重复（border 分量唯一）', () {
      final borders = coursePalette.map((c) => c.border).toSet();
      expect(borders.length, coursePalette.length);
    });
  });

  group('courseHash / courseColor', () {
    test('同名课哈希稳定', () {
      expect(courseHash('高等数学'), courseHash('高等数学'));
    });

    test('不同课名哈希尽量分散（100 门课至少映射到 8 个槽位）', () {
      final seen = <int>{};
      for (var i = 0; i < 100; i++) {
        seen.add(courseHash('课程$i') % coursePalette.length);
      }
      expect(seen.length, greaterThanOrEqualTo(8));
    });

    test('courseColor 稳定且在调色板内', () {
      final a = courseColor('大学物理');
      final b = courseColor('大学物理');
      expect(a, b);
      expect(coursePalette.contains(a), isTrue);
    });
  });

  group('assignCourseIndices', () {
    test('同一天的不同课程必须不同色', () {
      final result = assignCourseIndices({
        '高等数学': {1, 3}, // 周一、周三
        '大学英语': {1}, // 周一
        '大学物理': {1, 5}, // 周一、周五
        '体育': {3}, // 周三
      });
      final mon = {
        result['高等数学'],
        result['大学英语'],
        result['大学物理'],
      };
      expect(mon.length, 3); // 周一三课全不同色
      final wed = {result['高等数学'], result['体育']};
      expect(wed.length, 2); // 周三两课不同色
    });

    test('同名课始终拿到同一颜色（结果稳定）', () {
      final input = {
        '高等数学': {1, 3},
        '大学英语': {2, 4},
        '数据结构': {5},
      };
      expect(assignCourseIndices(input), assignCourseIndices(input));
      expect(
        assignCourseIndices(input)['高等数学'],
        assignCourseIndices({
          '大学英语': {2, 4},
          '数据结构': {5},
          '高等数学': {1, 3}, // 插入顺序不同
        })['高等数学'],
      );
    });

    test('所有下标都在调色板范围内', () {
      final result = assignCourseIndices({
        for (var i = 0; i < 20; i++) '课程$i': {(i % 7) + 1},
      });
      for (final idx in result.values) {
        expect(idx, inInclusiveRange(0, coursePalette.length - 1));
      }
    });

    test('无冲突时不偏离哈希初始偏好', () {
      final result = assignCourseIndices({
        '甲课': {1},
        '乙课': {2},
      });
      expect(result['甲课'], courseHash('甲课') % coursePalette.length);
      expect(result['乙课'], courseHash('乙课') % coursePalette.length);
    });
  });
}
