// cache_service.dart —— 本地缓存服务，基于 SQLite（sqflite 包）。
//
// 设计成一张极简的「键值表」kv(key, value, updated_at)：
//   - key       ：字符串主键，比如 'grades'、'timetable_2026-08-31'
//   - value     ：把任意数据 JSON 序列化后的字符串
//   - updated_at：写入时间戳（毫秒），用来做「过期(TTL)」判断
// 这种 kv 表方式简单灵活，不用为每种数据单独建表。

import 'dart:convert'; // jsonEncode / jsonDecode

import 'package:path/path.dart' as p; // 跨平台拼接文件路径（用 `as p` 起别名，调用时写 p.join）
import 'package:sqflite/sqflite.dart'; // SQLite 数据库

class CacheService {
  // 构造函数：传入一个已经打开的数据库对象。
  // `this._db` 是 Dart 简写：直接把参数赋值给字段 _db。
  CacheService(this._db);
  final Database _db; // final = 一旦赋值不可改；_db 私有

  // 工厂式静态方法：异步打开数据库文件并返回 CacheService。
  // 之所以不放构造函数里，是因为打开数据库是异步的（await），而构造函数不能 async。
  static Future<CacheService> open(String dirPath) async {
    final db = await openDatabase(
      p.join(dirPath, 'cache.db'), // 数据库文件路径：目录 + 文件名
      version: 1, // 数据库版本号，将来改表结构时靠它做升级迁移
      // onCreate：数据库文件「第一次」创建时执行，用来建表。
      onCreate: (db, _) => db.execute(
        'CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT, updated_at REAL)',
      ),
    );
    return CacheService(db);
  }

  // 内存数据库：数据只存在内存里、程序退出即消失。专门给「单元测试」用，
  // 这样测试不会污染真实文件、跑得也快。
  static Future<CacheService> inMemory() async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT, updated_at REAL)',
      ),
    );
    return CacheService(db);
  }

  // 写入：把任意对象（Map/List/数字等）序列化成 JSON 存进去。
  // Object 是 Dart 所有类型的基类，这里表示“任何可被 jsonEncode 的值”。
  Future<void> saveJson(String key, Object value, {int? updatedAt}) async {
    await _db.insert(
      'kv',
      {
        'key': key,
        'value': jsonEncode(value), // 对象 → JSON 字符串
        // ?? 是空值合并：updatedAt 为 null 就用当前时间戳。
        'updated_at': (updatedAt ?? DateTime.now().millisecondsSinceEpoch)
            .toDouble(),
      },
      // 主键冲突时用「替换」策略：同一个 key 再写就是更新，实现“覆盖式缓存”。
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // 读取：按 key 取出并反序列化。ttlDays>0 时会检查是否过期。
  // 返回 dynamic（动态类型）：因为存的内容可能是 Map、List 等，调用方自己知道该转成什么。
  Future<dynamic> loadJson(String key, {int ttlDays = 0}) async {
    final rows = await _db.query(
      'kv',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null; // 没这条记录
    final updated = rows.first['updated_at'] as num; // as num：把动态值断言为数字
    if (ttlDays > 0) {
      // 计算已经过去多少天：(现在 - 写入时间) / 一天的毫秒数(86400000)。
      final ageDays =
          (DateTime.now().millisecondsSinceEpoch - updated.toInt()) / 86400000;
      if (ageDays > ttlDays) {
        // 过期：删掉这条脏缓存并当作“没有”返回。
        await _db.delete('kv', where: 'key = ?', whereArgs: [key]);
        return null;
      }
    }
    return jsonDecode(rows.first['value'] as String); // JSON 字符串 → 对象
  }

  // 只读某个 key 的最后更新时间（毫秒时间戳），用于“今天是否已刷新”等判断。
  Future<int?> updatedAt(String key) async {
    final rows = await _db.query(
      'kv',
      columns: ['updated_at'], // 只查这一列，省资源
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : (rows.first['updated_at'] as num).toInt();
  }

  // 清空整张表（退出登录时用，把所有缓存一并删掉）。
  Future<void> clearAll() => _db.delete('kv');

  /// 删除指定 key 的缓存（用于清理过期的历史周课表等）。
  Future<void> delete(String key) =>
      _db.delete('kv', where: 'key = ?', whereArgs: [key]);

  /// 列出所有以 [prefix] 开头的键（如 'timetable_' → 各周课表缓存键）。
  Future<List<String>> keysWithPrefix(String prefix) async {
    final rows = await _db.query(
      'kv',
      columns: ['key'],
      where: 'key LIKE ?',
      // LIKE 的 % 匹配任意后缀；前缀本身不含通配符，安全。
      whereArgs: ['$prefix%'],
    );
    return rows.map((r) => r['key'] as String).toList();
  }
  // 关闭数据库连接。
  Future<void> close() => _db.close();
}
