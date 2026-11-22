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

  test('删掉的照片重新导入能恢复', () async {
    final trip = await trips.create(name: '测试', start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 2));
    final items = [
      ImportItem(
        uri: '/tmp/a.jpg',
        hash: 'h1',
        takenAt: DateTime(2026, 10, 1, 10),
        lat: 30.57,
        lng: 104.07,
        width: 100,
        height: 100,
      ),
    ];
    await photos.importBatch(trip.id, items);
    var list = await photos.allPhotos(trip.id);
    expect(list.length, 1);

    // 删除（软删）
    await photos.softDelete([list.first.id]);
    expect((await photos.allPhotos(trip.id)).length, 0);

    // 重新导入同一张
    final again = await photos.importBatch(trip.id, items);
    final after = await photos.allPhotos(trip.id);
    // ignore: avoid_print
    print('重导 inserted=${again.inserted} skipped=${again.skipped} 可见=${after.length}');
    expect(after.length, 1);
  });
}
