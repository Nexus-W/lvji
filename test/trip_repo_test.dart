import 'package:flutter_test/flutter_test.dart';

import 'package:luji/data/models/import_item.dart';
import 'package:luji/data/repository.dart';

import 'helpers/db_helper.dart';

void main() {
  test('T04 新建行程后能查到', () async {
    final db = await openTestDb();
    final repo = TripRepo(db);
    try {
      final trip = await repo.create(
          name: '测试', start: DateTime(2026, 10, 2), end: DateTime(2026, 10, 6));
      expect(trip.id, isNotEmpty);
      final found = await repo.find(trip.id);
      expect(found, isNotNull);
      expect(found!.name, '测试');
      expect((await repo.listAlive()).length, 1);
    } finally {
      await db.close();
    }
  });

  test('T05 找不到时返回 null（不许兜底）', () async {
    final db = await openTestDb();
    final repo = TripRepo(db);
    try {
      await repo.create(
          name: '测试', start: DateTime(2026, 10, 2), end: DateTime(2026, 10, 6));
      expect(await repo.find('不存在的id'), isNull);
    } finally {
      await db.close();
    }
  });

  test('T06 删除行程后，附属数据全部消失', () async {
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

      await tripRepo.delete(trip.id);

      expect(await tripRepo.find(trip.id), isNull);
      Future<int> count(String table) async {
        final r = await db.rawQuery(
            'SELECT COUNT(*) c FROM $table WHERE trip_id = ?', [trip.id]);
        return (r.first['c'] as num).toInt();
      }
      expect(await count('days'), 0);
      expect(await count('photos'), 0);
      expect(await count('imports'), 0);
    } finally {
      await db.close();
    }
  });

  test('T07 改名不影响其它字段', () async {
    final db = await openTestDb();
    final tripRepo = TripRepo(db);
    final photoRepo = PhotoRepo(db);
    try {
      final trip = await tripRepo.create(
          name: '旧名', start: DateTime(2026, 10, 2), end: DateTime(2026, 10, 6));
      await photoRepo.importBatch(trip.id, [
        for (var i = 0; i < 3; i++)
          ImportItem(
              uri: 'u$i',
              hash: 'h$i',
              takenAt: DateTime(2026, 10, 2, 12, 0),
              width: 100,
              height: 100),
      ]);
      await tripRepo.rename(trip.id, '新名字');
      expect((await tripRepo.find(trip.id))!.name, '新名字');
      expect(await photoRepo.countOf(trip.id), 3);
    } finally {
      await db.close();
    }
  });
}
