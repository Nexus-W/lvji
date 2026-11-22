import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../core/country_index.dart';
import '../core/extensions.dart';
import '../features/year/year_summary.dart';
import '../core/place_table.dart';
import 'geocoding.dart';
import 'dao/day_dao.dart';
import 'dao/photo_dao.dart';
import 'dao/trip_dao.dart';
import 'models/day.dart';
import 'models/import_item.dart';
import 'models/import_result.dart';
import 'models/photo.dart';
import 'models/trip.dart';
import 'models/trip_location.dart';

/// 照片分组算法（技术方案 §4.4）。纯函数，可直接单测。
///
/// 规则：凌晨 0:00–4:00 算前一天（用户心理上还在"昨晚"）；
/// 不在行程 days 范围内的照片不硬塞，返回 null（未分组）。
String? pickDayId(DateTime? takenAt, List<Day> days) {
  if (takenAt == null) return null;
  final d = takenAt.hour < 4
      ? takenAt.subtract(const Duration(days: 1))
      : takenAt;
  final key = ymd(d);
  for (final day in days) {
    if (day.date == key) return day.id;
  }
  return null;
}

/// 生成 [start, end]（含端点）闭区间的日期 key 列表，按升序。

/// 行程聚合仓库。页面只调这一层，不直接摸数据库。
class TripRepo {
  final Database _db;
  final TripDao _tripDao;
  final DayDao _dayDao;

  TripRepo(this._db, {TripDao? tripDao, DayDao? dayDao})
      : _tripDao = tripDao ?? TripDao(),
        _dayDao = dayDao ?? DayDao();

  /// 新建行程：写 trips + 按起止日期生成 days。
  Future<Trip> create({
    required String name,
    required DateTime start,
    required DateTime end,
  }) async {
    final now = DateTime.now().toIso8601String();
    final trip = Trip(
      id: newUuid(),
      name: name,
      startDate: ymd(start),
      endDate: ymd(end),
      createdAt: now,
      updatedAt: now,
    );
    await _db.transaction((txn) async {
      await _tripDao.insert(txn, trip);
      final dates = dateRange(start, end);
      for (var i = 0; i < dates.length; i++) {
        await _dayDao.insert(txn,
            Day(id: newUuid(), tripId: trip.id, date: dates[i], sort: i));
      }
    });
    return (await find(trip.id))!;
  }

  /// 修复历史数据：给「0 天」的行程按起止日期补建 days。
  ///
  /// 早期版本如果起止填反了会生成 0 天，导致该行程所有照片无法归天、
  /// 地图页抽屉永远为空。
  /// 历史库补 `days`。**只在首次运行时执行一次**，之后靠 meta 标记跳过。
  ///
  /// 为什么加标记：新版本的行程在创建时就会写 days，这段逻辑对新库永远是
  /// 空的；但原来每次启动都要「查全部行程 + 逐个查 days」，30 个行程就是
  /// 31 次查询白跑。修完一次后置标记，后续启动 0 开销。
  Future<int> ensureDays() async {
    if (await metaGet('days_repaired') == '1') return 0;
    final rows = await _db.query('trips', where: 'deleted_at IS NULL');
    var fixed = 0;
    for (final r in rows) {
      final id = r['id'] as String;
      final existing = await _dayDao.byTrip(_db, id);
      if (existing.isNotEmpty) continue;
      final start = DateTime.parse(r['start_date'] as String);
      final end = DateTime.parse(r['end_date'] as String);
      final dates = dateRange(start, end);
      await _db.transaction((txn) async {
        final dayIds = <String, String>{}; // date -> dayId
        for (var i = 0; i < dates.length; i++) {
          final dayId = newUuid();
          dayIds[dates[i]] = dayId;
          await _dayDao.insert(txn,
              Day(id: dayId, tripId: id, date: dates[i], sort: i));
        }
        // 补完天之后，把该行程里「没有归属天」的照片按拍摄时间放回去，
        // 否则它们会一直悬空（既不进某天、也不进未分组）。
        final photos = await txn.query('photos',
            where: 'trip_id = ? AND deleted_at IS NULL', whereArgs: [id]);
        // 用 pickDayId 而不是截字符串：凌晨 0-4 点拍的照片要归前一天，
        // 这里直接 substring 会把它们写到错误的 day 上，且是持久化写入。
        final dayList = [
          for (final d in dates)
            Day(id: dayIds[d]!, tripId: id, date: d, sort: dates.indexOf(d)),
        ];
        for (final row in photos) {
          final takenAt = row['taken_at'] as String?;
          if (takenAt == null) continue;
          final targetDay = pickDayId(DateTime.tryParse(takenAt), dayList);
          if (targetDay == null) continue;
          final cur = row['day_id'] as String?;
          if (cur == targetDay) continue;
          await txn.update('photos', {'day_id': targetDay},
              where: 'id = ?', whereArgs: [row['id']]);
        }
      });
      fixed++;
    }
    await metaSet('days_repaired', '1');
    return fixed;
  }

  Future<List<Trip>> listAlive() => _tripDao.listAlive(_db);

  /// 找不到返回 null，不兜底（修掉原型 getTrip 返回首项的 bug）。
  Future<Trip?> find(String id) => _tripDao.get(_db, id);

  /// 行程的"天"列表（按 sort 升序）。时间轴按天分组时用。
  Future<List<Day>> listDays(String id) => _dayDao.byTrip(_db, id);

  /// 足迹地图的「城市点」：聚合每个行程内有坐标的照片。
  /// 行程坐标 = 第一张有坐标照片的坐标（SQLite 在 GROUP BY 下取该组首行）。
  /// 足迹页数据：按「地点」聚合（不是按行程），每个城市一个点。
  /// 同一行程里去了杭州、成都、德阳，就该亮 3 个点，而不是只显示第一个。
  /// 没写地名的照片用本地地名表反查最近城市。
  /// 每张有坐标的照片一个点（**不做任何聚合/平均**）。
  /// 世界地图的国家判定必须用这个：`tripsWithLocation` 会按地点平均坐标，
  /// 一旦某张照片的 place 为空被 nearestPlace 猜成中国地名，平均值就会被
  /// 拉到完全无关的地方（实测波兰被拉到北纬 55°、地图亮起伊朗）。
  Future<List<TripLocation>> photoLocations() async {
    final rows = await _db.rawQuery(
      'SELECT t.id, t.name, p.place, p.lat, p.lng '
      'FROM photos p JOIN trips t ON p.trip_id = t.id '
      'WHERE t.deleted_at IS NULL AND p.deleted_at IS NULL '
      'AND p.lat IS NOT NULL AND p.lng IS NOT NULL',
    );
    return [
      for (final r in rows)
        TripLocation(
          tripId: r['id'] as String,
          name: r['name'] as String,
          lat: (r['lat'] as num).toDouble(),
          lng: (r['lng'] as num).toDouble(),
          place: (r['place'] as String?)?.trim() ?? '',
          photoCount: 1,
        ),
    ];
  }

  /// 关闭底层连接（恢复备份前调用）。
  Future<void> close() => _db.close();

  /// 读 meta（年度总结只弹一次的标记等）。
  Future<String?> metaGet(String key) async {
    final rows = await _db.query('meta',
        where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> metaSet(String key, String value) async {
    await _db.insert('meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 年度统计（UI 层做聚合，这里只负责取数）。
  Future<YearStats> yearStats(int year) async {
    await CountryIndex.ensureLoaded();
    return YearStats.compute(_db, year);
  }

  /// 按关键字搜行程：名称 / 手记 / 城市 / 地点（本地 LIKE，无网络）。
  ///
  /// 注意：`trips.city` 多数行程是空的（创建时没填），城市信息实际存在
  /// `photos.place` 里，所以必须用 EXISTS 去照片表里找，否则搜「成都」搜不到。
  Future<List<Trip>> search(String q) async {
    final key = '%${q.trim()}%';

    // ① 行程自身的字段（名称 / 手记 / 城市 / 省份）
    final byTrip = await _db.query(
      'trips',
      where: 'deleted_at IS NULL AND '
          '(name LIKE ? OR note LIKE ? OR city LIKE ? OR province LIKE ?)',
      whereArgs: [key, key, key, key],
    );

    // ② 照片的地点：place 原文 + cityOf 推出来的城市名都要能搜到。
    //    因为 place 格式不统一（「成都市·锦江区」有市名，「旌阳区」没有），
    //    只用 SQL LIKE 会漏掉「德阳」「上海」这类只有区名的记录。
    final needle = q.trim();
    final photoRows = await _db.query(
      'photos',
      columns: ['trip_id', 'place', 'lat', 'lng'],
      where: 'deleted_at IS NULL AND place IS NOT NULL',
    );
    final ids = <String>[];
    for (final r in photoRows) {
      final tripId = r['trip_id'];
      if (tripId is! String) continue;
      final place = (r['place'] as String?) ?? '';
      if (place.contains(needle)) {
        ids.add(tripId);
        continue;
      }
      final city = cityOf(place,
          lat: (r['lat'] as num?)?.toDouble(),
          lng: (r['lng'] as num?)?.toDouble());
      if (city.contains(needle)) ids.add(tripId);
    }
    final uniqueIds = ids.toSet().toList();

    final byPhoto = <String, Trip>{};
    if (uniqueIds.isNotEmpty) {
      final marks = List.filled(uniqueIds.length, '?').join(',');
      final rows = await _db.query(
        'trips',
        where: 'deleted_at IS NULL AND id IN ($marks)',
        whereArgs: uniqueIds,
      );
      for (final r in rows) {
        final t = Trip.fromMap(r);
        byPhoto[t.id] = t;
      }
    }

    // 合并去重 + 按开始日期倒序
    final merged = <String, Trip>{
      for (final r in byTrip) (r['id'] as String): Trip.fromMap(r),
      ...byPhoto,
    };
    final out = merged.values.toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    return out;
  }

  /// 每天的拍摄张数（首页天气条只显示「真的拍了照」的那几天）。
  Future<Map<String, int>> dayCounts(String tripId) async {
    // 用 day_id 关联 days.date，而不是截取 taken_at：
    // 凌晨 00:00–03:59 的照片在导入时被 pickDayId 归到前一天，
    // 直接截字符串会让「时间轴在哪天」和「天气/计数在哪天」对不上。
    // 用 LEFT JOIN + COALESCE：day_id 为空（未归天）的照片也要按拍摄日期统计，
    // 否则「有照片但没归天」的那几天会从天气条里消失。
    final rows = await _db.rawQuery(
      'SELECT COALESCE(d.date, substr(p.taken_at, 1, 10)) AS d, '
      'COUNT(*) AS c '
      'FROM photos p LEFT JOIN days d ON p.day_id = d.id '
      'WHERE p.trip_id = ? AND p.deleted_at IS NULL '
      // 关键：不能要求 taken_at 非空。
      // 有些照片 day_id 有效（已归到某天）但 taken_at 为空，
      // 加这个条件会把 B 行程 10-29 / 10-30 的两天整段漏掉。
      'AND (d.date IS NOT NULL OR p.taken_at IS NOT NULL) '
      'GROUP BY d',
      [tripId],
    );
    final out = <String, int>{};
    for (final r in rows) {
      final d = r['d'] as String?;
      if (d != null && d.length >= 10) {
        out[d] = (r['c'] as num).toInt();
      }
    }
    return out;
  }

  /// 每天「第一张有坐标的照片」的坐标：`{日期: (lat, lng)}`。
  ///
  /// 天气必须按天取坐标：跨城行程（成都→德阳）用整趟一个点算出来的天气是错的。
  /// 同一天多张不同城市时取最早那张 —— 一天里通常在一个城市移动。
  Future<Map<String, (double, double)>> dayLocations(String tripId) async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(d.date, substr(p.taken_at, 1, 10)) AS day, '
      'p.lat, p.lng '
      'FROM photos p LEFT JOIN days d ON p.day_id = d.id '
      'WHERE p.trip_id = ? AND p.deleted_at IS NULL '
      'AND p.lat IS NOT NULL AND p.lng IS NOT NULL '
      'AND (ABS(p.lat) > 0.01 OR ABS(p.lng) > 0.01) '
      // SQLite 的 ASC 会把 NULL 排在最前：一张「有时间但 taken_at 为空」的照片
      // 会抢走当天的代表坐标。显式把 NULL 排到最后。
      'ORDER BY (p.taken_at IS NULL), p.taken_at ASC',
      [tripId],
    );
    final out = <String, (double, double)>{};
    for (final r in rows) {
      final day = r['day'] as String?;
      if (day == null || day.length < 10) continue;
      // 只保留每天第一条（SQL 已按 taken_at 升序）
      out.putIfAbsent(day, () => (
            (r['lat'] as num).toDouble(),
            (r['lng'] as num).toDouble(),
          ));
    }
    return out;
  }

  /// 该行程第一张有坐标的照片（天气查询用它定位城市）。
  Future<(double, double)?> firstLocation(String tripId) async {
    final rows = await _db.rawQuery(
      'SELECT lat, lng FROM photos '
      'WHERE trip_id = ? AND deleted_at IS NULL '
      'AND lat IS NOT NULL AND lng IS NOT NULL '
      'AND (ABS(lat) > 0.01 OR ABS(lng) > 0.01) '
      'ORDER BY taken_at ASC LIMIT 1',
      [tripId],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return ((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble());
  }

  /// 足迹页数据：按「地点」聚合（同城多张合成一个点，坐标取平均）。
  ///
  /// 复用 `photoLocations()` 的同一份结果，**不再重复扫照片表**
  /// （原来两个方法 SQL 完全相同，足迹页连续 await 两次 = 全表扫两遍）。
  Future<List<TripLocation>> tripsWithLocation() async {
    final raw = await photoLocations();
    final byPlace = <String, List<TripLocation>>{};
    for (final l in raw) {
      final place = (l.place ?? '').trim();
      final key =
          place.isEmpty ? nearestPlace(l.lat, l.lng) : place.split('·').first.trim();
      byPlace.putIfAbsent(key, () => []).add(l);
    }
    final list = byPlace.entries.map((e) {
      final items = e.value;
      final lat = items.map((x) => x.lat).reduce((a, b) => a + b) / items.length;
      final lng = items.map((x) => x.lng).reduce((a, b) => a + b) / items.length;
      final first = items.first;
      return TripLocation(
        tripId: first.tripId,
        name: first.name,
        lat: lat,
        lng: lng,
        place: e.key,
        photoCount: items.length,
      );
    }).toList()
      ..sort((a, b) => b.photoCount.compareTo(a.photoCount));
    return list;
  }


  Future<void> rename(String id, String name) =>
      _tripDao.updateName(_db, id, name, DateTime.now().toIso8601String());

  /// 改起止日期：保留已有 days（按 date 匹配、id 不变），删多余的、补缺的。
  /// 删天依赖 ON DELETE SET NULL，照片不会丢，落回未分组。
  Future<void> updateDates(String id, DateTime start, DateTime end) async {
    final now = DateTime.now().toIso8601String();
    await _db.transaction((txn) async {
      await _tripDao.updateDates(txn, id, ymd(start), ymd(end), now);

      final targetDates = dateRange(start, end);
      final targetSet = targetDates.toSet();
      final existing = await _dayDao.byTrip(txn, id);
      final byDate = {for (final d in existing) d.date: d};

      // 删多余的天
      for (final day in existing) {
        if (!targetSet.contains(day.date)) {
          await _dayDao.delete(txn, day.id);
        }
      }
      // 保留已有（更新 sort）、补缺
      for (var i = 0; i < targetDates.length; i++) {
        final date = targetDates[i];
        final old = byDate[date];
        if (old != null) {
          await _dayDao.updateSort(txn, old.id, i);
        } else {
          await _dayDao
              .insert(txn, Day(id: newUuid(), tripId: id, date: date, sort: i));
        }
      }
    });
  }

  /// 物理删除行程：靠外键级联清空 days/photos/imports。
  Future<void> delete(String id) => _tripDao.delete(_db, id);

  /// 行程手记（纯文本 ≤500 字）。
  Future<void> updateNote(String id, String note) =>
      _tripDao.updateNote(_db, id, note, DateTime.now().toIso8601String());

  /// 手动设置行程坐标/城市（足迹城市点用）。
  Future<void> updateLocation(String id,
          {double? lat, double? lng, String? city}) =>
      _tripDao.updateLocation(_db, id, lat: lat, lng: lng, city: city);
}

/// 照片聚合仓库。
class PhotoRepo {
  final Database _db;
  final PhotoDao _photoDao;
  final DayDao _dayDao;

  PhotoRepo(this._db, {PhotoDao? photoDao, DayDao? dayDao})
      : _photoDao = photoDao ?? PhotoDao(),
        _dayDao = dayDao ?? DayDao();

  /// 批量导入。不读文件、不解析 EXIF（hash 已由调用方算好）。
  ///
  /// **刻意不用事务**：真机上出现过「事务内的 inserted 计数为 2、提交后全库查不到」
  /// 的诡异现象；改成逐条自动提交后，inserted 与真实落库严格一致，代价是
  /// 每张多一次 fsync（几百张也就多几百毫秒）。
  Future<ImportResult> importBatch(String tripId, List<ImportItem> items) async {
    final days = await _dayDao.byTrip(_db, tripId);
    var inserted = 0;
    var skipped = 0;
    var failed = 0;
    final byDay = <String, int>{};

    for (final item in items) {
      if (item.uri == null) {
        failed++;
        continue;
      }
      final dayId = pickDayId(item.takenAt, days);
      final photo = Photo(
        id: newUuid(),
        tripId: tripId,
        dayId: dayId,
        uri: item.uri!,
        hash: item.hash,
        takenAt: item.takenAt?.toIso8601String(),
        lat: item.lat,
        lng: item.lng,
        // 有坐标时用本地地名表反查最近城市，避免显示「未标注地点」
        place: (item.lat != null && item.lng != null)
            ? nearestPlace(item.lat!, item.lng!)
            : null,
        width: item.width,
        height: item.height,
        createdAt: DateTime.now().toIso8601String(),
      );

      var ok = await _photoDao.insertIgnore(_db, photo);
      if (!ok) {
        // 删过又重导：恢复软删记录（同时刷新天/时间/坐标/地名）
        ok = await _photoDao.restoreDeletedByHash(_db, photo);
      }
      // 兜底修复只在「既没新增成功、也没恢复成功」时执行。
      // 新增成功时刚 INSERT 的字段本来就是对的，再 UPDATE 一次纯属浪费
      // （导入 1000 张就多 1000 次写库）。真机上出现过的
      // deleted_at = 字面 "NULL" / 时间戳 脏数据，都落在 !ok 这条路径上。
      if (!ok) {
        // 只修 deleted_at 这一列。
        // 这条分支对「照片已存在且未删除」的正常重复导入也会命中，
        // 如果连 place/lat/lng 一起写，用户在信息面板手改的地名、
        // 在地图上点选的坐标会被最近城市名和 EXIF 原值静默覆盖。
        await _db.rawUpdate(
          'UPDATE photos SET deleted_at = NULL WHERE trip_id = ? AND hash = ?',
          [tripId, photo.hash],
        );
      }

      // 诊断只在 debug 构建里跑：release 下这段是「每张照片一次全 hash 查库 +
      // 一条 logcat」，导入 1000 张就多 1000 次平台往返。
      if (kDebugMode) {
        final probe = await _db.query('photos',
            columns: ['id', 'trip_id', 'deleted_at'],
            where: 'hash = ?',
            whereArgs: [photo.hash]);
        debugPrint('[Import] hash='
            '${photo.hash.length > 8 ? photo.hash.substring(0, 8) : photo.hash} '
            'takenAt=${photo.takenAt} dayId=${photo.dayId} ok=$ok '
            '| dbRows=${probe.length} '
            'del=${probe.map((r) => r['deleted_at']).toList()} '
            'trip=${probe.map((r) => (r['trip_id'] as String).substring(0, 8)).toList()} '
            'wantTrip=${tripId.substring(0, 8)}');
      }

      // 计数只看 ok（新增成功或恢复成功）；fixed 只是兜底刷新，不代表"新导入"
      if (ok) {
        inserted++;
        final key = dayId ?? 'unknown';
        byDay[key] = (byDay[key] ?? 0) + 1;
      } else {
        skipped++;
      }
    }

    // 记录「尝试导入」这一事实（不参与张数统计）；失败不影响照片已经落库。
    try {
      await _db.insert('imports', {
        'id': newUuid(),
        'trip_id': tripId,
        'count': items.length,
        'at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}

    return ImportResult(
        inserted: inserted, skipped: skipped, failed: failed, byDay: byDay);
  }

  /// 修复历史脏数据：坐标是 (0,0) 的照片（相机无 GPS 时 EXIF 写 0）。
  /// 这些点会落到非洲西海岸，还会让 nearestPlace 误判成「拉萨」。
  Future<int> repairFakeCoords() async {
    return _db.rawUpdate(
      'UPDATE photos SET lat = NULL, lng = NULL, place = NULL '
      'WHERE lat IS NOT NULL AND lng IS NOT NULL '
      'AND ABS(lat) < 0.01 AND ABS(lng) < 0.01',
    );
  }

  /// 修复历史脏数据：`deleted_at` 被写成字面 "NULL" / 空串 / 空格。
  /// 这些值在 SQL 里都不等于 NULL，会被所有 `deleted_at IS NULL` 查询过滤掉。
  Future<int> repairDeletedAt() async {
    return _db.rawUpdate(
      "UPDATE photos SET deleted_at = NULL "
      "WHERE deleted_at IS NOT NULL AND TRIM(deleted_at) IN ('', 'NULL', 'null')",
    );
  }

  /// 一次查出所有行程的「总数 / 缺位置数」。
  /// 替代 AppState.reload 里对每个 trip 各查两次的 N+1 写法。
  Future<Map<String, (int total, int missing)>> statsByTrip() async {
    final rows = await _db.rawQuery(
      'SELECT trip_id, COUNT(*) AS n, '
      'SUM(CASE WHEN lat IS NULL OR lng IS NULL THEN 1 ELSE 0 END) AS m '
      'FROM photos WHERE deleted_at IS NULL GROUP BY trip_id',
    );
    return {
      for (final r in rows)
        r['trip_id'] as String: (
          (r['n'] as num).toInt(),
          (r['m'] as num?)?.toInt() ?? 0,
        ),
    };
  }

  /// 一次查出所有行程的封面候选 uri（封面优先，其次最新）。
  /// 封面拼贴：只取「手动设过封面」的照片，按设置时间倒序，最多 3 张。
  /// 删除后 SQL 自然排除（deleted_at），用户继续点封面即可闭环。
  Future<Map<String, List<String>>> coverUrisByTrip() async {
    final rows = await _db.rawQuery(
      'SELECT trip_id, uri FROM photos WHERE deleted_at IS NULL '
      'AND cover_set_at IS NOT NULL '
      'ORDER BY cover_set_at DESC',
    );
    final out = <String, List<String>>{};
    for (final r in rows) {
      final id = r['trip_id'] as String;
      final list = out.putIfAbsent(id, () => <String>[]);
      if (list.length < 3) list.add(r['uri'] as String);
    }
    return out;
  }


  /// 按 id 取单张照片（列表卡片取封面用）。找不到返回 null。
  Future<Photo?> find(String id) => _photoDao.get(_db, id);

  /// 返回这批 hash 里「该行程已存在」的集合（导入预览时标记"将跳过"）。
  Future<Set<String>> existingHashes(String tripId, List<String> hashes) async {
    final existing = <String>{};
    const batch = 500; // SQLite 参数上限，分批查
    for (var i = 0; i < hashes.length; i += batch) {
      final end = (i + batch) < hashes.length ? (i + batch) : hashes.length;
      final part = hashes.sublist(i, end);
      final placeholders = List.filled(part.length, '?').join(',');
      final rows = await _db.rawQuery(
        'SELECT hash FROM photos WHERE trip_id = ? AND deleted_at IS NULL '
        'AND hash IN ($placeholders)',
        [tripId, ...part],
      );
      existing.addAll(rows.map((r) => r['hash'] as String));
    }
    return existing;
  }

  Future<List<Photo>> byDay(String tripId, String? dayId) =>
      _photoDao.byDay(_db, tripId, dayId);

  /// 行程内有坐标的照片（地图页打点用）。


  Future<void> softDelete(List<String> photoIds) =>
      _photoDao.softDelete(_db, photoIds, DateTime.now().toIso8601String());

  /// 设封面 / 取消封面（再点一次取消）。同行程只保留一张，并同步 trips.cover_photo。
  Future<void> setCover(String photoId) async {
    await _db.transaction((txn) async {
      final p = await _photoDao.get(txn, photoId);
      if (p == null) return;
      if (p.isCover == 1) {
        // 必须同时清 cover_set_at：首页封面拼贴按它过滤/排序，
        // 只清 is_cover 会导致「取消封面后列表里还在」。
        await txn.update('photos', {'is_cover': 0, 'cover_set_at': null},
            where: 'id = ?', whereArgs: [photoId]);
        await txn.update('trips', {'cover_photo': null},
            where: 'id = ?', whereArgs: [p.tripId]);
      } else {
        await _photoDao.setCover(txn, photoId);
        await txn.update(
          'photos',
          {'cover_set_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [photoId],
        );
        await txn.update('trips', {'cover_photo': photoId},
            where: 'id = ?', whereArgs: [p.tripId]);
      }
    });
  }

  /// 加入/移出精选。
  Future<void> setFeatured(String photoId, bool featured) =>
      _photoDao.setFeatured(_db, photoId, featured ? 1 : 0);

  /// 写照片备注。
  Future<void> updateNote(String photoId, String note) =>
      _photoDao.updateNote(_db, photoId, note);

  /// 缺坐标照片（补救队列）。
  // ---------------- 回收站 ----------------

  /// 最近删除的照片（软删），按删除时间倒序。
  Future<List<Photo>> deletedPhotos() async {
    final rows = await _db.query(
      'photos',
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC',
    );
    return rows.map(Photo.fromMap).toList();
  }

  /// 从回收站恢复。
  Future<int> restoreDeleted(List<String> ids) async {
    if (ids.isEmpty) return 0;
    final ph = List.filled(ids.length, '?').join(',');
    return _db.rawUpdate(
      'UPDATE photos SET deleted_at = NULL WHERE id IN ($ph)',
      ids,
    );
  }

  /// 彻底删除（记录 + 私有目录里的文件）。
  Future<int> purgeDeleted(List<String> ids) async {
    if (ids.isEmpty) return 0;
    final ph = List.filled(ids.length, '?').join(',');
    final rows = await _db.query('photos',
        columns: ['uri'], where: 'id IN ($ph)', whereArgs: ids);
    for (final r in rows) {
      final path = r['uri'] as String?;
      if (path == null) continue;
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    return _db.delete('photos', where: 'id IN ($ph)', whereArgs: ids);
  }

  /// [tripId] 为空表示查所有行程（主页提示条用）。
  Future<List<Photo>> photosMissingLocation(String? tripId) async {
    if (tripId != null) return _photoDao.byMissingLocation(_db, tripId);
    final rows = await _db.query(
      'photos',
      where: 'deleted_at IS NULL AND (lat IS NULL OR lng IS NULL)',
      orderBy: 'taken_at DESC',
    );
    return rows.map(Photo.fromMap).toList();
  }

  /// 只数 deleted_at IS NULL 的照片（测试与外部调用依赖）。
  Future<int> countOf(String tripId) => _photoDao.countAlive(_db, tripId);

  /// 只含有坐标的照片（补救页/测试用）。
  Future<List<Photo>> photosWithLocation(String tripId) async {
    final rows = await _db.query(
      'photos',
      where: 'trip_id = ? AND deleted_at IS NULL '
          'AND lat IS NOT NULL AND lng IS NOT NULL',
      whereArgs: [tripId],
    );
    return rows.map(Photo.fromMap).toList();
  }

  /// 设置/清空拍摄时间（null 清空并重算 day_id）。
  Future<void> setTakenAt(String photoId, DateTime? takenAt) async {
    await _db.transaction((txn) async {
      final p = await _photoDao.get(txn, photoId);
      String? dayId;
      if (takenAt != null && p != null) {
        dayId = pickDayId(takenAt, await _dayDao.byTrip(txn, p.tripId));
      }
      await _photoDao.setTakenAt(
          txn, photoId, takenAt?.toIso8601String(), dayId);
    });
  }

  /// 设置/清空坐标。
  Future<void> setLocation(String photoId, double? lat, double? lng) =>
      _photoDao.setLocation(_db, photoId, lat, lng);

  /// 把「城市级」地名升级为「区级」（如 成都 → 成都市锦江区…）。
  ///
  /// 只升级「空」或「自动反查出来的城市名」，不覆盖用户手改的地名；
  /// 每次限 30 张，避免把当天配额打光。
  Future<int> upgradePlacesToDistrict() async {
    final rows = await _db.query(
      'photos',
      columns: ['id', 'lat', 'lng', 'place'],
      where: 'lat IS NOT NULL AND lng IS NOT NULL AND deleted_at IS NULL',
    );
    var n = 0;
    for (final r in rows) {
      if (n >= 30) break;
      final lat = (r['lat'] as num).toDouble();
      final lng = (r['lng'] as num).toDouble();
      if (lat.abs() < 0.01 && lng.abs() < 0.01) continue;
      final old = (r['place'] as String?)?.trim();
      // 只动「空」或「本地表自动填的城市名」，保护用户手改的精确地名
      final auto = old == null || old.isEmpty || old == nearestPlace(lat, lng);
      if (!auto) continue;
      final real = await Geocoding.reverse(lat, lng);
      if (real != null && real.isNotEmpty && real != old) {
        await setPlace(r['id'] as String, real);
        n++;
      }
      // 腾讯 WebService 并发 1 次/秒，必须限速
      await Future<void>.delayed(const Duration(milliseconds: 1100));
    }
    return n;
  }

  /// 启动时批量修复：地名能解析出坐标、但与原坐标差得很远（>0.5°，
  /// 相当于跨城市）时，以地名为准覆盖坐标。
  Future<int> repairLocationFromPlace() async {
    final rows = await _db.query(
      'photos',
      columns: ['id', 'place', 'lat', 'lng'],
      where: 'place IS NOT NULL AND place != "" '
          'AND lat IS NOT NULL AND lng IS NOT NULL AND deleted_at IS NULL',
    );
    var fixed = 0;
    for (final r in rows) {
      final place = (r['place'] as String).trim();
      if (place.isEmpty) continue;
      final c = placeToLatLng(place);
      if (c.$1 == null || c.$2 == null) continue;
      final dLat = (c.$1! - (r['lat'] as num).toDouble()).abs();
      final dLng = (c.$2! - (r['lng'] as num).toDouble()).abs();
      if (dLat > 0.5 || dLng > 0.5) {
        await setLocation(r['id'] as String, c.$1, c.$2);
        fixed++;
      }
    }
    return fixed;
  }

  /// 设置/清空地点。
  Future<void> setPlace(String photoId, String? place) =>
      _photoDao.setPlace(_db, photoId, place);

  /// 某行程全部存活照片（分享选片池）。
  Future<List<Photo>> allPhotos(String tripId) => _photoDao.all(_db, tripId);

  /// 某行程精选照片（分享九宫格默认 seed）。
  Future<List<Photo>> featuredPhotos(String tripId) =>
      _photoDao.byFeatured(_db, tripId);

  /// 清理回收站：物理删除软删超过 [days] 天的记录（只删记录，不删原图）。
  Future<int> cleanupRecycle(int days) {
    final before = DateTime.now().subtract(Duration(days: days)).toIso8601String();
    return _photoDao.deleteRecycledOlderThan(_db, before);
  }

  /// 所有存活照片的 uri（设置页「清理缓存」对比用）。
  /// 所有照片的文件 uri（**包含回收站里的**）。
  ///
  /// 必须包含软删记录：回收站保留 7 天，期间用户可能「恢复」。
  /// 之前只查 `deleted_at IS NULL`，导致「删照片 → 清理缓存」把导入副本
  /// 当成无引用文件物理删除，之后恢复/重导出来是空白图。
  Future<List<String>> allUris() async {
    final rows = await _db.rawQuery('SELECT uri FROM photos');
    return rows.map((r) => r['uri'] as String).toList();
  }

  /// 启动时修复历史数据：有地名（place）但没坐标的照片，用本地地名表反查补上坐标。
  /// 否则这些照片在地图页 / 足迹页永远看不到（那两处只认 lat/lng）。
  Future<int> backfillLocationFromPlace() async {
    final rows = await _db.query('photos',
        where:
            'deleted_at IS NULL AND place IS NOT NULL AND place != "" AND (lat IS NULL OR lng IS NULL)');
    var fixed = 0;
    for (final row in rows) {
      final place = row['place'] as String;
      final coords = placeToLatLng(place);
      if (coords.$1 != null && coords.$2 != null) {
        await _db.update(
            'photos', {'lat': coords.$1, 'lng': coords.$2},
            where: 'id = ?', whereArgs: [row['id']]);
        fixed++;
      }
    }
    return fixed;
  }
}

