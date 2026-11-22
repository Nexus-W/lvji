import 'package:sqflite/sqflite.dart';

import '../models/day.dart';

/// 「天」的低层数据访问。
class DayDao {
  Future<List<Day>> byTrip(DatabaseExecutor db, String tripId) async {
    final rows = await db
        .query('days', where: 'trip_id = ?', whereArgs: [tripId], orderBy: 'sort');
    return rows.map(Day.fromMap).toList();
  }

  Future<void> insert(DatabaseExecutor db, Day day) async {
    await db.insert('days', day.toMap());
  }

  Future<void> delete(DatabaseExecutor db, String dayId) async {
    // 依赖 ON DELETE SET NULL：删天时该天照片的 day_id 自动置 NULL，照片不丢。
    await db.delete('days', where: 'id = ?', whereArgs: [dayId]);
  }

  Future<void> updateSort(DatabaseExecutor db, String dayId, int sort) async {
    await db.update('days', {'sort': sort},
        where: 'id = ?', whereArgs: [dayId]);
  }
}
