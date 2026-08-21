import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class CacheService {
  CacheService(this._db);
  final Database _db;

  static Future<CacheService> open(String dirPath) async {
    final db = await openDatabase(
      p.join(dirPath, 'cache.db'),
      version: 1,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT, updated_at REAL)',
      ),
    );
    return CacheService(db);
  }

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

  Future<void> saveJson(String key, Object value, {int? updatedAt}) async {
    await _db.insert(
      'kv',
      {
        'key': key,
        'value': jsonEncode(value),
        'updated_at': (updatedAt ?? DateTime.now().millisecondsSinceEpoch).toDouble(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<dynamic> loadJson(String key, {int ttlDays = 0}) async {
    final rows = await _db.query('kv', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    final updated = rows.first['updated_at'] as num;
    if (ttlDays > 0) {
      final ageDays = (DateTime.now().millisecondsSinceEpoch - updated.toInt()) / 86400000;
      if (ageDays > ttlDays) {
        await _db.delete('kv', where: 'key = ?', whereArgs: [key]);
        return null;
      }
    }
    return jsonDecode(rows.first['value'] as String);
  }

  Future<int?> updatedAt(String key) async {
    final rows = await _db.query(
      'kv',
      columns: ['updated_at'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : (rows.first['updated_at'] as num).toInt();
  }

  Future<void> clearAll() => _db.delete('kv');
  Future<void> close() => _db.close();
}
