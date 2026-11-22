import 'package:flutter_test/flutter_test.dart';

import 'package:luji/data/models/import_item.dart';
import 'package:luji/data/repository.dart';

import 'helpers/db_helper.dart';

void main() {
  test('featuredPhotos 只返回精选照片', () async {
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
              takenAt: DateTime(2026, 10, 2, 12),
              width: 100,
              height: 100),
      ]);
      final dayId = (await tripRepo.listDays(trip.id)).first.id;
      final photos = await photoRepo.byDay(trip.id, dayId);
      await photoRepo.setFeatured(photos[0].id, true);
      await photoRepo.setFeatured(photos[2].id, true);

      final featured = await photoRepo.featuredPhotos(trip.id);
      expect(featured.length, 2);
    } finally {
      await db.close();
    }
  });

  test('allPhotos 返回全部存活照片', () async {
    final db = await openTestDb();
    final tripRepo = TripRepo(db);
    final photoRepo = PhotoRepo(db);
    try {
      final trip = await tripRepo.create(
          name: '测试', start: DateTime(2026, 10, 2), end: DateTime(2026, 10, 6));
      await photoRepo.importBatch(trip.id, [
        for (var i = 0; i < 4; i++)
          ImportItem(
              uri: 'u$i',
              hash: 'h$i',
              takenAt: DateTime(2026, 10, 2, 12),
              width: 100,
              height: 100),
      ]);
      expect((await photoRepo.allPhotos(trip.id)).length, 4);
    } finally {
      await db.close();
    }
  });

  test('cleanupRecycle 只删 7 天前的软删记录', () async {
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
              takenAt: DateTime(2026, 10, 2, 12),
              width: 100,
              height: 100),
      ]);
      final dayId = (await tripRepo.listDays(trip.id)).first.id;
      final photos = await photoRepo.byDay(trip.id, dayId);
      await photoRepo.softDelete([photos[0].id]); // 刚软删

      // 7 天内清理 → 不删
      await photoRepo.cleanupRecycle(7);
      final all = await db.query('photos', where: 'trip_id = ?', whereArgs: [trip.id]);
      expect(all.length, 3); // 记录还在

      // 把软删时间改成 8 天前 → 清理删掉
      final old = DateTime.now().subtract(const Duration(days: 8)).toIso8601String();
      await db.update('photos', {'deleted_at': old},
          where: 'id = ?', whereArgs: [photos[0].id]);
      final removed = await photoRepo.cleanupRecycle(7);
      expect(removed, 1);
      final after = await db.query('photos', where: 'trip_id = ?', whereArgs: [trip.id]);
      expect(after.length, 2);
    } finally {
      await db.close();
    }
  });
}
