import 'package:flutter_test/flutter_test.dart';
import 'package:luji/data/db.dart';
import 'package:luji/data/models/import_item.dart';
import 'package:luji/data/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late TripRepo trips;
  late PhotoRepo photos;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await createSchema(db);
    trips = TripRepo(db);
    photos = PhotoRepo(db);
  });

  tearDown(() async => db.close());

  test('0 天行程：导入 → 删除 → 重导 仍然可见', () async {
    final trip = await trips.create(
        name: '333',
        start: DateTime(2026, 10, 24),
        end: DateTime(2026, 10, 30));
    // 人为制造 0 天（模拟历史坏数据）
    await db.delete('days', where: 'trip_id = ?', whereArgs: [trip.id]);
    expect((await trips.listDays(trip.id)).length, 0);

    final items = [
      ImportItem(
        uri: '/tmp/a.jpg',
        hash: 'h333',
        takenAt: DateTime(2026, 10, 24, 19, 13),
        lat: 30.6,
        lng: 104.07,
        width: 100,
        height: 100,
      ),
    ];

    await photos.importBatch(trip.id, items);
    expect((await photos.allPhotos(trip.id)).length, 1);

    final first = (await photos.allPhotos(trip.id)).first;
    await photos.softDelete([first.id]);
    expect((await photos.allPhotos(trip.id)).length, 0);

    final again = await photos.importBatch(trip.id, items);
    final after = await photos.allPhotos(trip.id);
    // ignore: avoid_print
    print('0天行程 重导 inserted=${again.inserted} skipped=${again.skipped} 可见=${after.length}');
    expect(after.length, 1);
  });
}
