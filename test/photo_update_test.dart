import 'package:flutter_test/flutter_test.dart';

import 'package:luji/data/models/import_item.dart';
import 'package:luji/data/repository.dart';

import 'helpers/db_helper.dart';

void main() {
  test('setFeatured 加入/移出精选', () async {
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
            takenAt: DateTime(2026, 10, 2, 12),
            width: 100,
            height: 100),
      ]);
      final id = (await photoRepo.byDay(trip.id, null)).isEmpty
          ? (await photoRepo.byDay(trip.id, (await tripRepo.listDays(trip.id)).first.id))
              .first
              .id
          : (await photoRepo.byDay(trip.id, null)).first.id;

      await photoRepo.setFeatured(id, true);
      expect((await photoRepo.find(id))!.isFeatured, 1);
      await photoRepo.setFeatured(id, false);
      expect((await photoRepo.find(id))!.isFeatured, 0);
    } finally {
      await db.close();
    }
  });

  test('updateNote 写备注', () async {
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
            takenAt: DateTime(2026, 10, 2, 12),
            width: 100,
            height: 100),
      ]);
      final dayId = (await tripRepo.listDays(trip.id)).first.id;
      final id = (await photoRepo.byDay(trip.id, dayId)).first.id;

      await photoRepo.updateNote(id, '漂亮');
      expect((await photoRepo.find(id))!.note, '漂亮');
    } finally {
      await db.close();
    }
  });

  test('setTakenAt 改时间重算 day_id，清空置 NULL', () async {
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
            takenAt: DateTime(2026, 10, 2, 12),
            width: 100,
            height: 100),
      ]);
      final days = await tripRepo.listDays(trip.id);
      final day02 = days.firstWhere((d) => d.date == '2026-10-02');
      final day03 = days.firstWhere((d) => d.date == '2026-10-03');
      final id = (await photoRepo.byDay(trip.id, day02.id)).first.id;

      await photoRepo.setTakenAt(id, DateTime(2026, 10, 3, 10, 0));
      expect((await photoRepo.find(id))!.dayId, day03.id);

      await photoRepo.setTakenAt(id, null);
      final p = await photoRepo.find(id);
      expect(p!.takenAt, isNull);
      expect(p.dayId, isNull);
    } finally {
      await db.close();
    }
  });

  test('photosMissingLocation 只返回缺坐标照片', () async {
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
            takenAt: DateTime(2026, 10, 2, 12),
            lat: 25.6,
            lng: 100.2,
            width: 100,
            height: 100),
        ImportItem(
            uri: 'u1',
            hash: 'h1',
            takenAt: DateTime(2026, 10, 2, 13),
            width: 100,
            height: 100),
      ]);

      final missing = await photoRepo.photosMissingLocation(trip.id);
      expect(missing.length, 1);
      expect(missing.first.hash, 'h1');
    } finally {
      await db.close();
    }
  });

  test('tripsWithLocation 聚合有坐标行程', () async {
    final db = await openTestDb();
    final tripRepo = TripRepo(db);
    final photoRepo = PhotoRepo(db);
    try {
      final a = await tripRepo.create(
          name: '大理', start: DateTime(2026, 10, 2), end: DateTime(2026, 10, 6));
      final b = await tripRepo.create(
          name: '无坐标', start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 3));
      await photoRepo.importBatch(a.id, [
        ImportItem(
            uri: 'a0',
            hash: 'a0',
            takenAt: DateTime(2026, 10, 2, 12),
            lat: 25.61,
            lng: 100.27,
            width: 100,
            height: 100),
        ImportItem(
            uri: 'a1',
            hash: 'a1',
            takenAt: DateTime(2026, 10, 2, 13),
            lat: 25.7,
            lng: 100.3,
            width: 100,
            height: 100),
      ]);
      await photoRepo.importBatch(b.id, [
        ImportItem(
            uri: 'b0',
            hash: 'b0',
            takenAt: DateTime(2026, 9, 1, 12),
            width: 100,
            height: 100),
      ]);

      final locations = await tripRepo.tripsWithLocation();
      expect(locations.length, 1);
      expect(locations.first.name, '大理');
      expect(locations.first.photoCount, 2);
    } finally {
      await db.close();
    }
  });
}
