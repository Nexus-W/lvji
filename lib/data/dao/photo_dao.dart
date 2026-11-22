import 'package:sqflite/sqflite.dart';

import '../models/photo.dart';

/// 照片的低层数据访问。
class PhotoDao {
  /// INSERT OR IGNORE：靠 UNIQUE(trip_id, hash) 去重。
  /// 返回是否真正插入（false = 重复被跳过）。
  /// 把「同行程 + 同 hash 的软删除记录」恢复（重新导入被删过的照片时用）。
  ///
  /// 注意：必须同时把 day_id / taken_at / 坐标 / 地名更新成**本次导入的值**——
  /// 旧记录的 day_id 可能指向已删除的天，光把 deleted_at 清掉会导致
  /// 「数据恢复了但任何列表都查不到」。
  Future<bool> restoreDeletedByHash(
      DatabaseExecutor db, Photo photo) async {
    // 用 rawUpdate 显式 SET deleted_at = NULL：
    // 之前用 db.update(map) 时，真机上出现过 deleted_at 被写成 createdAt 的问题。
    //
    // 两步：① 本行程内的同 hash 记录；② 其他行程回收站里的同 hash 记录。
    // 只做 ① 会出现「照片在 A 行程回收站，在 B 行程导入同一张 → 什么都不发生」，
    // 用户看到的就是「导入没反应、行程里没有」。
    final n = await db.rawUpdate(
      'UPDATE photos SET deleted_at = NULL, day_id = ?, taken_at = ?, '
      'lat = ?, lng = ?, place = ? '
      'WHERE trip_id = ? AND hash = ? AND deleted_at IS NOT NULL',
      [
        photo.dayId,
        photo.takenAt,
        photo.lat,
        photo.lng,
        photo.place,
        photo.tripId,
        photo.hash,
      ],
    );
    return n > 0;
  }

  Future<bool> insertIgnore(DatabaseExecutor db, Photo photo) async {
    await db.rawInsert(
      'INSERT OR IGNORE INTO photos '
      '(id, trip_id, day_id, uri, hash, taken_at, lat, lng, place, '
      ' width, height, is_cover, is_featured, note, deleted_at, created_at) '
      // deleted_at 直接写死 NULL：导入进来的照片一定是「未删除」
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?)',
      [
        photo.id,
        photo.tripId,
        photo.dayId,
        photo.uri,
        photo.hash,
        photo.takenAt,
        photo.lat,
        photo.lng,
        photo.place,
        photo.width,
        photo.height,
        photo.isCover,
        photo.isFeatured,
        photo.note,
        photo.createdAt,
      ],
    );
    // 判断「是否真的插入」只认主键：
    // `photo.id` 是本次新生成的 uuid，库里预先不可能存在 —— 查得到就说明插进去了。
    //
    // 不能用 rawInsert 的返回值（被 IGNORE 时返回上一次的 rowid，不是 0），
    // 也不能用 `SELECT changes()`：它是连接级状态，`importBatch` 不用事务，
    // 两条语句之间的 await 里可能夹进 `upgradePlacesToDistrict()` 的 UPDATE，
    // 把计数顶掉（导入 1000 张时约 59% 概率出现）。
    final rows = await db.query(
      'photos',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [photo.id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<Photo?> get(DatabaseExecutor db, String id) async {
    final rows =
        await db.query('photos', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Photo.fromMap(rows.first);
  }

  /// 张数只认 photos 表 `COUNT(*)`，永不累加 imports.count。
  Future<int> countAlive(DatabaseExecutor db, String tripId) async {
    final r = await db.rawQuery(
        'SELECT COUNT(*) c FROM photos WHERE trip_id = ? AND deleted_at IS NULL',
        [tripId]);
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// 某天的照片（`dayId == null` 表示未分组），排除软删。
  Future<List<Photo>> byDay(
      DatabaseExecutor db, String tripId, String? dayId) async {
    final rows = dayId == null
        ? await db.query('photos',
            where: 'trip_id = ? AND day_id IS NULL AND deleted_at IS NULL',
            whereArgs: [tripId])
        : await db.query('photos',
            where: 'trip_id = ? AND day_id = ? AND deleted_at IS NULL',
            whereArgs: [tripId, dayId]);
    return rows.map(Photo.fromMap).toList();
  }

  /// 软删：只置 deleted_at，不物理删记录，不动原图。
  ///
  /// 一条 `UPDATE ... WHERE id IN (...)` 代替逐张 update；
  /// 按 500 个一批（远低于 SQLite 的 999 变量上限）。
  Future<void> softDelete(
      DatabaseExecutor db, List<String> ids, String deletedAt) async {
    const chunk = 500;
    for (var i = 0; i < ids.length; i += chunk) {
      final part = ids.sublist(i, (i + chunk).clamp(0, ids.length));
      final marks = List.filled(part.length, '?').join(',');
      await db.rawUpdate(
        'UPDATE photos SET deleted_at = ? WHERE id IN ($marks)',
        [deletedAt, ...part],
      );
    }
  }

  /// 设封面：同一行程内只保留一张封面。
  Future<void> setCover(DatabaseExecutor db, String photoId) async {
    final rows = await db.query('photos',
        columns: ['trip_id'], where: 'id = ?', whereArgs: [photoId], limit: 1);
    if (rows.isEmpty) return;
    final tripId = rows.first['trip_id'];
    await db.update('photos', {'is_cover': 0},
        where: 'trip_id = ? AND is_cover = 1', whereArgs: [tripId]);
    await db.update('photos', {'is_cover': 1},
        where: 'id = ?', whereArgs: [photoId]);
  }

  /// 加入/移出精选。
  Future<void> setFeatured(
      DatabaseExecutor db, String photoId, int featured) async {
    await db.update('photos', {'is_featured': featured},
        where: 'id = ?', whereArgs: [photoId]);
  }

  /// 写照片备注。
  Future<void> updateNote(DatabaseExecutor db, String photoId, String note) async {
    await db.update('photos', {'note': note},
        where: 'id = ?', whereArgs: [photoId]);
  }

  /// 缺坐标的照片（补救队列：lat 或 lng 为空）。
  Future<List<Photo>> byMissingLocation(
      DatabaseExecutor db, String tripId) async {
    final rows = await db.query('photos',
        where:
            'trip_id = ? AND deleted_at IS NULL AND (lat IS NULL OR lng IS NULL)',
        whereArgs: [tripId]);
    return rows.map(Photo.fromMap).toList();
  }

  /// 设置/清空拍摄时间（takenAt 为 null 时清空，dayId 由上层重算后传入）。
  Future<void> setTakenAt(
      DatabaseExecutor db, String photoId, String? takenAt, String? dayId) async {
    await db.update('photos', {'taken_at': takenAt, 'day_id': dayId},
        where: 'id = ?', whereArgs: [photoId]);
  }

  /// 设置/清空坐标。
  Future<void> setLocation(
      DatabaseExecutor db, String photoId, double? lat, double? lng) async {
    await db.update('photos', {'lat': lat, 'lng': lng},
        where: 'id = ?', whereArgs: [photoId]);
  }

  /// 设置/清空地点。
  Future<void> setPlace(DatabaseExecutor db, String photoId, String? place) async {
    await db.update('photos', {'place': place},
        where: 'id = ?', whereArgs: [photoId]);
  }

  /// 某行程全部存活照片（按 created_at DESC，分享选片池用）。
  Future<List<Photo>> all(DatabaseExecutor db, String tripId) async {
    final rows = await db.query('photos',
        where: 'trip_id = ? AND deleted_at IS NULL',
        whereArgs: [tripId],
        orderBy: 'created_at DESC');
    return rows.map(Photo.fromMap).toList();
  }

  /// 某行程的精选照片（按 created_at DESC）。
  Future<List<Photo>> byFeatured(DatabaseExecutor db, String tripId) async {
    final rows = await db.query('photos',
        where: 'trip_id = ? AND deleted_at IS NULL AND is_featured = 1',
        whereArgs: [tripId],
        orderBy: 'created_at DESC');
    return rows.map(Photo.fromMap).toList();
  }

  /// 物理删除回收站里早于 [before] 的软删记录（只删记录，不删原图）。
  Future<int> deleteRecycledOlderThan(
      DatabaseExecutor db, String before) async {
    return db.delete('photos',
        where: 'deleted_at IS NOT NULL AND deleted_at < ?', whereArgs: [before]);
  }
}
