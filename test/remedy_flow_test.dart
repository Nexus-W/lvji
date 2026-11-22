import 'package:flutter_test/flutter_test.dart';

import 'package:luji/data/models/import_item.dart';
import 'package:luji/data/repository.dart';

import 'helpers/db_helper.dart';

void main() {
  test('补坐标后：不再出现在缺位置队列，且仍能在时间轴里查到', () async {
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
      final photo = (await photoRepo.byDay(trip.id, day02.id)).first;

      // 补之前：在缺位置队列里
      expect((await photoRepo.photosMissingLocation(trip.id)).length, 1);

      // 模拟信息修正弹层保存：时间 + 坐标 + 地点
      await photoRepo.setTakenAt(photo.id, DateTime(2026, 10, 3, 9, 30));
      await photoRepo.setLocation(photo.id, 25.61, 100.27);
      await photoRepo.setPlace(photo.id, '大理古城');

      final updated = await photoRepo.find(photo.id);
      expect(updated!.lat, 25.61);
      expect(updated.lng, 100.27);
      expect(updated.place, '大理古城');

      // 补之后：队列里应该没有了
      expect(await photoRepo.photosMissingLocation(trip.id), isEmpty);

      // 且时间轴（按天）仍然能查到（时间改到 10-03）
      final day03 = days.firstWhere((d) => d.date == '2026-10-03');
      final inDay03 = await photoRepo.byDay(trip.id, day03.id);
      expect(inDay03.length, 1);

      // 全量照片里也在
      expect((await photoRepo.allPhotos(trip.id)).length, 1);
    } finally {
      await db.close();
    }
  });

  test('backfillLocationFromPlace：有地名没坐标的照片自动补坐标', () async {
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
      final photo = (await photoRepo.byDay(trip.id, days.first.id)).first;
      // 模拟历史数据：只有地名，没有坐标
      await db.update('photos', {'place': '杭州'},
          where: 'id = ?', whereArgs: [photo.id]);

      final fixed = await photoRepo.backfillLocationFromPlace();
      expect(fixed, 1);

      final updated = await photoRepo.find(photo.id);
      expect(updated!.lat, closeTo(30.27, 0.01));
      expect(updated.lng, closeTo(120.15, 0.01));
      // 补完后地图页能查到（photosWithLocation 只认 lat/lng）
      expect((await photoRepo.photosWithLocation(trip.id)).length, 1);
    } finally {
      await db.close();
    }
  });
}
