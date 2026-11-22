import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/db_helper.dart';

void main() {
  test('T01 表与索引齐备', () async {
    final db = await openTestDb();
    try {
      final tables = await db
          .rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      final names = tables.map((r) => r['name'] as String).toSet();
      expect(names.containsAll(['trips', 'days', 'photos', 'imports']), isTrue);

      final idx = await db
          .rawQuery("SELECT name, sql FROM sqlite_master WHERE type='index'");
      final byName = {
        for (final r in idx) r['name'] as String: (r['sql'] as String?) ?? ''
      };
      expect(byName.containsKey('idx_photos_dedup'), isTrue);
      expect(byName.containsKey('idx_days_unique'), isTrue);
      expect(byName['idx_photos_dedup']!.toUpperCase().contains('UNIQUE'),
          isTrue);
      expect(byName['idx_days_unique']!.toUpperCase().contains('UNIQUE'),
          isTrue);
    } finally {
      await db.close();
    }
  });

  test('T02 外键约束已开启', () async {
    final db = await openTestDb();
    try {
      final r = await db.rawQuery('PRAGMA foreign_keys');
      expect(r.first.values.first, 1);
    } finally {
      await db.close();
    }
  });

  test('T03 插入非法外键应失败', () async {
    final db = await openTestDb();
    try {
      await expectLater(
        db.insert('photos', {
          'id': 'p1',
          'trip_id': 'not-exist',
          'uri': 'u',
          'hash': 'h',
          'width': 100,
          'height': 100,
          'created_at': '2026-10-02T00:00:00',
        }),
        throwsA(isA<DatabaseException>()),
      );
    } finally {
      await db.close();
    }
  });
}
