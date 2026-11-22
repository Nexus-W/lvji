import 'package:flutter_test/flutter_test.dart';

import 'package:luji/data/models/import_item.dart';
import 'package:luji/data/repository.dart';

import 'helpers/db_helper.dart';

void main() {
  test('T11 首次导入', () async {
    final db = await openTestDb();
    final tripRepo = TripRepo(db);
    final photoRepo = PhotoRepo(db);
    try {
      final trip = await tripRepo.create(
          name: '测试', start: DateTime(2026, 10, 2), end: DateTime(2026, 10, 6));

      final items = <ImportItem>[
        for (var i = 0; i < 8; i++)
          ImportItem(
              uri: 'u$i',
              hash: 'h$i',
              takenAt: DateTime(2026, 10, 2, 12, 0),
              width: 100,
              height: 100),
        const ImportItem(uri: 'u8', hash: 'h8', width: 100, height: 100),
        const ImportItem(uri: 'u9', hash: 'h9', width: 100, height: 100),
      ];

      final r = await photoRepo.importBatch(trip.id, items);

      expect(r.inserted, 10);
      expect(r.skipped, 0);
      expect(await photoRepo.countOf(trip.id), 10);
      expect(r.byDay['unknown'], 2);
      final nonUnknown = r.byDay.entries
          .where((e) => e.key != 'unknown')
          .fold<int>(0, (s, e) => s + e.value);
      expect(nonUnknown, 8);
    } finally {
      await db.close();
    }
  });

  test('T12 重复导入同一批（去重，张数不翻倍）', () async {
    final db = await openTestDb();
    final tripRepo = TripRepo(db);
    final photoRepo = PhotoRepo(db);
    try {
      final trip = await tripRepo.create(
          name: '测试', start: DateTime(2026, 10, 2), end: DateTime(2026, 10, 6));

      final items = <ImportItem>[
        for (var i = 0; i < 10; i++)
          ImportItem(
              uri: 'u$i',
              hash: 'h$i',
              takenAt: DateTime(2026, 10, 2, 12, 0),
              width: 100,
              height: 100),
      ];
      await photoRepo.importBatch(trip.id, items); // 第一次

      final r2 = await photoRepo.importBatch(trip.id, items); // 完全相同再来一次

      expect(r2.inserted, 0);
      expect(r2.skipped, 10);
      expect(await photoRepo.countOf(trip.id), 10); // 关键：不翻倍

      final imports = await db
          .query('imports', where: 'trip_id = ?', whereArgs: [trip.id]);
      expect(imports.length, 2); // 新增 1 条「尝试导入」记录
    } finally {
      await db.close();
    }
  });

  test('T13 单条失败不中断整批', () async {
    final db = await openTestDb();
    final tripRepo = TripRepo(db);
    final photoRepo = PhotoRepo(db);
    try {
      final trip = await tripRepo.create(
          name: '测试', start: DateTime(2026, 10, 2), end: DateTime(2026, 10, 6));

      final items = <ImportItem>[
        for (var i = 0; i < 10; i++)
          ImportItem(
              uri: i == 4 ? null : 'u$i', // 第 5 条 uri 为 null，模拟损坏
              hash: 'h$i',
              takenAt: DateTime(2026, 10, 2, 12, 0),
              width: 100,
              height: 100),
      ];

      final r = await photoRepo.importBatch(trip.id, items);

      expect(r.failed, 1);
      expect(r.inserted, 9);
      expect(r.skipped, 0);
    } finally {
      await db.close();
    }
  });

  test('T14 封面唯一', () async {
    final db = await openTestDb();
    final tripRepo = TripRepo(db);
    final photoRepo = PhotoRepo(db);
    try {
      final trip = await tripRepo.create(
          name: '测试', start: DateTime(2026, 10, 2), end: DateTime(2026, 10, 6));
      await photoRepo.importBatch(trip.id, [
        for (var i = 0; i < 3; i++)
          ImportItem(
              uri: 'u$i',
              hash: 'h$i',
              takenAt: DateTime(2026, 10, 2, 12, 0),
              width: 100,
              height: 100),
      ]);

      Future<String> idOf(String hash) async => (await db.query('photos',
              where: 'hash = ?', whereArgs: [hash], limit: 1))
          .first['id'] as String;

      await photoRepo.setCover(await idOf('h0'));
      await photoRepo.setCover(await idOf('h1'));

      final covers = await db.query('photos',
          where: 'trip_id = ? AND is_cover = 1', whereArgs: [trip.id]);
      expect(covers.length, 1);
      expect(covers.first['id'], await idOf('h1'));
    } finally {
      await db.close();
    }
  });

  test('T15 existingHashes 返回该行程已存在的 hash（导入预览查重）', () async {
    final db = await openTestDb();
    final tripRepo = TripRepo(db);
    final photoRepo = PhotoRepo(db);
    try {
      final trip = await tripRepo.create(
          name: '测试', start: DateTime(2026, 10, 2), end: DateTime(2026, 10, 6));
      await photoRepo.importBatch(trip.id, [
        for (var i = 0; i < 3; i++)
          ImportItem(
              uri: 'u$i',
              hash: 'h$i',
              takenAt: DateTime(2026, 10, 2, 12, 0),
              width: 100,
              height: 100),
      ]);

      final existing =
          await photoRepo.existingHashes(trip.id, ['h0', 'h1', 'hX', 'hY']);
      expect(existing, {'h0', 'h1'});
    } finally {
      await db.close();
    }
  });
}
