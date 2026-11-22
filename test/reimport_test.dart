import 'package:flutter_test/flutter_test.dart';

import 'package:luji/data/models/import_item.dart';
import 'package:luji/data/dao/photo_dao.dart';
import 'package:luji/data/models/photo.dart';
import 'package:luji/data/repository.dart';

import 'helpers/db_helper.dart';

void main() {
  test('删除单张后重导同一文件：必须重新可见', () async {
    final db = await openTestDb();
    final trips = TripRepo(db);
    final photos = PhotoRepo(db);

    final t = await trips.create(
        name: '测试', start: DateTime(2026, 10, 26), end: DateTime(2026, 10, 30));

    final item = ImportItem(
        uri: 'u0',
        hash: 'same-hash',
        takenAt: DateTime(2026, 10, 28, 14, 21, 42),
        width: 100,
        height: 100);

    await photos.importBatch(t.id, [item]);
    var visible = await photos.allPhotos(t.id);
    expect(visible.length, 1, reason: '首次导入应可见');

    // 软删这张
    final id = visible.first.id;
    await photos.softDelete([id]);
    visible = await photos.allPhotos(t.id);
    expect(visible, isEmpty, reason: '删除后应不可见');

    // 硬断言：软删记录还在时，insertIgnore 必须返回 false
    // （真机 sqflite 的 rawInsert 在 IGNORE 时返回上次 rowid，不能靠它判断）
    final conflict = await PhotoDao().insertIgnore(
      db,
      Photo(
        id: 'probe',
        tripId: t.id,
        uri: 'u0',
        hash: 'same-hash',
        width: 100,
        height: 100,
        createdAt: DateTime.now().toIso8601String(),
      ),
    );
    expect(conflict, isFalse, reason: 'INSERT OR IGNORE 被忽略时必须返回 false');

    // 重新导入同一文件（同 hash）
    await photos.importBatch(t.id, [item]);
    visible = await photos.allPhotos(t.id);
    expect(visible.length, 1, reason: '重导后必须重新可见');
    expect(visible.first.hash, 'same-hash');
    // 时间不能被清空
    expect(visible.first.takenAt, isNotNull, reason: '重导后拍摄时间应保留');

    // 关键回归：回收站里的照片 uri 必须仍被 allUris 返回，
    // 否则「清理缓存」会把导入副本物理删掉，恢复出来是空白图。
    await photos.softDelete([visible.first.id]);
    final uris = await photos.allUris();
    expect(uris, contains('u0'), reason: '回收站文件的 uri 不能被当成无引用');

    await db.close();
  });

  test('照片在 A 行程回收站，在 B 行程导入同一张：B 必须能看到', () async {
    final db = await openTestDb();
    final trips = TripRepo(db);
    final photos = PhotoRepo(db);

    final a = await trips.create(
        name: 'A', start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 3));
    final b = await trips.create(
        name: 'B', start: DateTime(2026, 10, 26), end: DateTime(2026, 10, 30));

    final item = ImportItem(
        uri: 'u0',
        hash: 'shared-hash',
        takenAt: DateTime(2026, 10, 28, 14, 21, 42),
        width: 100,
        height: 100);

    await photos.importBatch(a.id, [item]);
    final inA = await photos.allPhotos(a.id);
    await photos.softDelete([inA.first.id]);

    // 在 B 导入同一个文件（同 hash）
    await photos.importBatch(b.id, [item]);
    final inB = await photos.allPhotos(b.id);
    expect(inB.length, 1, reason: 'B 行程必须能看到这张照片');
    expect(inB.first.takenAt, isNotNull);

    await db.close();
  });
}
