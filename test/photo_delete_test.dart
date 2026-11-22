import 'package:flutter_test/flutter_test.dart';

import 'package:luji/data/models/import_item.dart';
import 'package:luji/data/repository.dart';

import 'helpers/db_helper.dart';

void main() {
  test('T15 软删不计入张数，但记录还在', () async {
    final db = await openTestDb();
    final tripRepo = TripRepo(db);
    final photoRepo = PhotoRepo(db);
    try {
      final trip = await tripRepo.create(
          name: '测试', start: DateTime(2026, 10, 2), end: DateTime(2026, 10, 6));
      await photoRepo.importBatch(trip.id, [
        for (var i = 0; i < 5; i++)
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
      final p1 = await idOf('h0');
      final p2 = await idOf('h1');

      await photoRepo.softDelete([p1, p2]);

      expect(await photoRepo.countOf(trip.id), 3);
      final all = await db
          .query('photos', where: 'trip_id = ?', whereArgs: [trip.id]);
      expect(all.length, 5); // 记录未物理删
      final p1Row = (await db.query('photos', where: 'id = ?', whereArgs: [p1]))
          .first;
      expect(p1Row['deleted_at'], isNotNull);
    } finally {
      await db.close();
    }
  });

  test('T16 软删的照片不出现在 byDay', () async {
    final db = await openTestDb();
    final tripRepo = TripRepo(db);
    final photoRepo = PhotoRepo(db);
    try {
      final trip = await tripRepo.create(
          name: '测试', start: DateTime(2026, 10, 2), end: DateTime(2026, 10, 6));
      await photoRepo.importBatch(trip.id, [
        for (var i = 0; i < 5; i++)
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
      final p1 = await idOf('h0');
      final p2 = await idOf('h1');
      await photoRepo.softDelete([p1, p2]);

      final dayId = (await db.query('days',
              where: 'trip_id = ? AND date = ?',
              whereArgs: [trip.id, '2026-10-02']))
          .first['id'] as String;
      final photos = await photoRepo.byDay(trip.id, dayId);
      final ids = photos.map((p) => p.id).toSet();
      expect(ids.contains(p1), isFalse);
      expect(ids.contains(p2), isFalse);
      expect(photos.length, 3);
    } finally {
      await db.close();
    }
  });
}
