import 'package:sqflite/sqflite.dart';

import '../models/trip.dart';

/// 行程的低层数据访问。方法接收 [DatabaseExecutor]（Database 或 Transaction），
/// 以便上层在同一事务里编排多表操作。
class TripDao {
  Future<String> insert(DatabaseExecutor db, Trip trip) async {
    await db.insert('trips', trip.toMap());
    return trip.id;
  }

  Future<Trip?> get(DatabaseExecutor db, String id) async {
    final rows =
        await db.query('trips', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Trip.fromMap(rows.first);
  }

  Future<List<Trip>> listAlive(DatabaseExecutor db) async {
    // 排序规则：最近「新增过照片」的行程排最前；没有照片的按创建时间。
    final rows = await db.rawQuery('''
      SELECT t.* FROM trips t
      WHERE t.deleted_at IS NULL
      ORDER BY COALESCE(
        (SELECT MAX(p.created_at) FROM photos p
         WHERE p.trip_id = t.id AND p.deleted_at IS NULL),
        t.created_at
      ) DESC
    ''');
    return rows.map(Trip.fromMap).toList();
  }

  Future<void> updateName(
      DatabaseExecutor db, String id, String name, String updatedAt) async {
    await db.update('trips', {'name': name, 'updated_at': updatedAt},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateDates(DatabaseExecutor db, String id, String startDate,
      String endDate, String updatedAt) async {
    await db.update('trips',
        {'start_date': startDate, 'end_date': endDate, 'updated_at': updatedAt},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> delete(DatabaseExecutor db, String id) async {
    await db.delete('trips', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateNote(
      DatabaseExecutor db, String id, String note, String updatedAt) async {
    await db.update('trips', {'note': note, 'updated_at': updatedAt},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateLocation(DatabaseExecutor db, String id,
      {double? lat, double? lng, String? city}) async {
    final values = <String, Object?>{};
    if (lat != null) values['lat'] = lat;
    if (lng != null) values['lng'] = lng;
    if (city != null) values['city'] = city;
    if (values.isNotEmpty) {
      await db.update('trips', values, where: 'id = ?', whereArgs: [id]);
    }
  }
}
