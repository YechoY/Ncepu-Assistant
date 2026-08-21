import 'package:flutter_test/flutter_test.dart';
import 'package:hdjw_assistant/services/cache_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('保存并读取 JSON', () async {
    final c = await CacheService.inMemory();
    await c.saveJson('grades', ['a', 1]);
    expect(await c.loadJson('grades'), ['a', 1]);
    await c.close();
  });
  test('30 天课表缓存过期', () async {
    final c = await CacheService.inMemory();
    await c.saveJson(
      'timetable_2026-08-17',
      [1],
      updatedAt: DateTime.now().subtract(const Duration(days: 31)).millisecondsSinceEpoch,
    );
    expect(await c.loadJson('timetable_2026-08-17', ttlDays: 30), null);
    await c.close();
  });
  test('成绩不设限', () async {
    final c = await CacheService.inMemory();
    await c.saveJson(
      'grades',
      [1],
      updatedAt: DateTime.now().subtract(const Duration(days: 200)).millisecondsSinceEpoch,
    );
    expect(await c.loadJson('grades'), [1]);
    await c.close();
  });
  test('清除全部', () async {
    final c = await CacheService.inMemory();
    await c.saveJson('grades', [1]);
    await c.clearAll();
    expect(await c.loadJson('grades'), null);
    await c.close();
  });
}
