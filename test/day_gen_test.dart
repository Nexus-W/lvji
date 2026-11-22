import 'package:flutter_test/flutter_test.dart';

import 'package:luji/data/models/import_item.dart';
import 'package:luji/data/repository.dart';

import 'helpers/db_helper.dart';

void main() {
  test('T08 按起止日期生成正确天数', () async {
    final db = await openTestDb();
    final repo = TripRepo(db);
    try {
      final trip = await repo.create(
          name: '测试', start: DateTime(2026, 10, 2), end: DateTime(2026, 10, 6));
      final days = await db
          .query('days', where: 'trip_id = ?', whereArgs: [trip.id], orderBy: 'sort');
      expect(days.length, 5);
      expect(days.map((d) => d['date']).toList(),
          ['2026-10-02', '2026-10-03', '2026-10-04', '2026-10-05', '2026-10-06']);
      expect(days.map((d) => d['sort']).toList(), [0, 1, 2, 3, 4]);
    } finally {
      await db.close();
    }
  });

  test('T09 改日期：延长（保留原 day.id）', () async {
    final db = await openTestDb();
    final tripRepo = TripRepo(db);
    final photoRepo = PhotoRepo(db);
    try {
      final trip = await tripRepo.create(
          name: '测试', start: DateTime(2026, 10, 2), end: DateTime(2026, 10, 4));
      await photoRepo.importBatch(trip.id, [
        for (var i = 0; i < 2; i++)
          ImportItem(
              uri: 'u$i',
              hash: 'h$i',
              takenAt: DateTime(2026, 10, 3, 10 + i, 0),
              width: 100,
              height: 100),
      ]);
      final dayBefore = (await db.query('days',
          where: 'trip_id = ? AND date = ?',
          whereArgs: [trip.id, '2026-10-03'])).first;
      final dayId = dayBefore['id'];

      await tripRepo.updateDates(
          trip.id, DateTime(2026, 10, 2), DateTime(2026, 10, 6));

      final days = await db.query('days', where: 'trip_id = ?', whereArgs: [trip.id]);
      expect(days.length, 5);
      final dayAfter = (await db.query('days',
          where: 'trip_id = ? AND date = ?',
          whereArgs: [trip.id, '2026-10-03'])).first;
      expect(dayAfter['id'], dayId); // 原 day.id 不变

      final photos = await db.query('photos', where: 'trip_id = ?', whereArgs: [trip.id]);
      expect(photos.length, 2);
      for (final p in photos) {
        expect(p['day_id'], dayId);
      }
    } finally {
      await db.close();
    }
  });

  test('T10 改日期：缩短（删天不删照片，day_id 置 NULL）', () async {
    final db = await openTestDb();
    final tripRepo = TripRepo(db);
    final photoRepo = PhotoRepo(db);
    try {
      final trip = await tripRepo.create(
          name: '测试', start: DateTime(2026, 10, 2), end: DateTime(2026, 10, 6));
      await photoRepo.importBatch(trip.id, [
        ImportItem(
            uri: 'u0',
            hash: 'h0',
            takenAt: DateTime(2026, 10, 6, 10, 0),
            width: 100,
            height: 100),
      ]);

      await tripRepo.updateDates(
          trip.id, DateTime(2026, 10, 2), DateTime(2026, 10, 4));

      final days = await db.query('days', where: 'trip_id = ?', whereArgs: [trip.id]);
      expect(days.length, 3);
      expect(
          await db.query('days',
              where: 'trip_id = ? AND date = ?',
              whereArgs: [trip.id, '2026-10-06']),
          isEmpty);

      final photos = await db.query('photos', where: 'trip_id = ?', whereArgs: [trip.id]);
      expect(photos.length, 1); // 照片没被删
      expect(photos.first['day_id'], isNull); // 落回未分组
    } finally {
      await db.close();
    }
  });
}
