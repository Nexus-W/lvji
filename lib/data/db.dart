import 'package:sqflite/sqflite.dart';

const int _dbVersion = 6;

/// 打开 App 数据库（生产环境用，传入绝对路径）。
Future<Database> openAppDatabase(String path) {
  return openDatabase(
    path,
    version: _dbVersion,
    onConfigure: _enableForeignKeys,
    onCreate: (db, version) => createSchema(db),
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) await createCacheSchema(db);
      if (oldVersion < 3) await createWeatherSchema(db);
      if (oldVersion < 4) {
        await db.execute(
            'ALTER TABLE photos ADD COLUMN cover_set_at TEXT');
      }
      if (oldVersion < 5) await createCoverIndex(db);
      if (oldVersion < 6) await addWeatherCoordColumns(db);
    },
  );
}

/// 外键开关：`PRAGMA foreign_keys` 是**连接级**设置，必须在这里执行。
/// 写在建表语句里没用；不开启时 `ON DELETE CASCADE` / `SET NULL` 会静默失效。
Future<void> _enableForeignKeys(Database db) async {
  await db.execute('PRAGMA foreign_keys = ON');
}

/// 天气缓存增加坐标列（按 0.1° 网格）。
///
/// 旧缓存的行 lat_key 为 NULL，读取时视为失效 → 重新拉一次；
/// 不改主键、不重建表，迁移只加两列，**不触碰任何用户数据**。
Future<void> addWeatherCoordColumns(Database db) async {
  // 幂等：v1/v2 老库升到 v3 时，`createWeatherSchema` 建的表**已经带这两列**，
  // 再无条件 ALTER 会报 duplicate column name，导致 openDatabase 失败、App 起不来。
  final cols = await db.rawQuery('PRAGMA table_info(weather_daily)');
  final names = cols.map((r) => r['name'] as String).toSet();
  if (!names.contains('lat_key')) {
    await db.execute('ALTER TABLE weather_daily ADD COLUMN lat_key REAL');
  }
  if (!names.contains('lng_key')) {
    await db.execute('ALTER TABLE weather_daily ADD COLUMN lng_key REAL');
  }
}

/// 封面查询用的部分索引：只索引「设过封面且未删除」的行。
///
/// `coverUrisByTrip` 的 SQL 没有 `trip_id` 条件（一次取所有行程的封面），
/// 所以 `idx_photos_trip(trip_id, deleted_at)` 用不上，会全表扫 + 排序。
/// 部分索引体积只跟封面数量有关（几十行），几乎不占空间。
Future<void> createCoverIndex(Database db) async {
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_photos_cover '
    'ON photos(cover_set_at DESC) '
    'WHERE cover_set_at IS NOT NULL AND deleted_at IS NULL',
  );
}

/// 建表 + 索引。表结构与索引严格对齐《技术方案-V1.md》§4.1。
/// 注意：`createWeatherSchema` 也必须在这里调用，不能只写在 onUpgrade 里——
/// 新装的库直接就是当前版本，永远不会走升级路径，否则新用户没有天气表。
/// 只在 onCreate 或测试初始化里调用一次。
Future<void> createSchema(Database db) async {
  await db.execute('''
    CREATE TABLE trips (
      id           TEXT PRIMARY KEY,
      name         TEXT NOT NULL,
      start_date   TEXT NOT NULL,
      end_date     TEXT NOT NULL,
      country      TEXT,
      province     TEXT,
      city         TEXT,
      lat          REAL,
      lng          REAL,
      note         TEXT NOT NULL DEFAULT '',
      cover_photo  TEXT,
      deleted_at   TEXT,
      created_at   TEXT NOT NULL,
      updated_at   TEXT NOT NULL
    )
  ''');
  await db.execute('CREATE INDEX idx_trips_alive ON trips(deleted_at)');

  await db.execute('''
    CREATE TABLE days (
      id       TEXT PRIMARY KEY,
      trip_id  TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
      date     TEXT NOT NULL,
      place    TEXT NOT NULL DEFAULT '',
      sort     INTEGER NOT NULL
    )
  ''');
  await db.execute('CREATE UNIQUE INDEX idx_days_unique ON days(trip_id, date)');

  await db.execute('''
    CREATE TABLE photos (
      id          TEXT PRIMARY KEY,
      trip_id     TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
      day_id      TEXT REFERENCES days(id) ON DELETE SET NULL,
      uri         TEXT NOT NULL,
      hash        TEXT NOT NULL,
      taken_at    TEXT,
      lat         REAL,
      lng         REAL,
      place       TEXT,
      width       INTEGER NOT NULL,
      height      INTEGER NOT NULL,
      is_cover    INTEGER NOT NULL DEFAULT 0,
      cover_set_at TEXT,
      is_featured INTEGER NOT NULL DEFAULT 0,
      note        TEXT NOT NULL DEFAULT '',
      deleted_at  TEXT,
      created_at  TEXT NOT NULL
    )
  ''');
  await db.execute(
      'CREATE UNIQUE INDEX idx_photos_dedup ON photos(trip_id, hash)');
  await db.execute('CREATE INDEX idx_photos_trip ON photos(trip_id, deleted_at)');
  await db.execute('CREATE INDEX idx_photos_day ON photos(day_id)');

  await db.execute('''
    CREATE TABLE imports (
      id       TEXT PRIMARY KEY,
      trip_id  TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
      count    INTEGER NOT NULL,
      at       TEXT NOT NULL
    )
  ''');

  await createCacheSchema(db);
  await createWeatherSchema(db);
  await createCoverIndex(db);
}

/// v2 新增：地理编码缓存 + 通用 key-value（配额计数）。
///
/// - `geocode_cache`：坐标网格化到 0.0001°（约 11m）→ 地址，永久复用，
///   同一景区几十张照片只消耗 1 次腾讯接口配额。
/// - `meta`：`geocode_date` / `geocode_count` 记录当日调用量。
/// 每日天气缓存（按行程 + 日期）。只存结果，失败下次再取。
Future<void> createWeatherSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS weather_daily (
      trip_id TEXT NOT NULL,
      date    TEXT NOT NULL,
      code    INTEGER,
      tmax    REAL,
      tmin    REAL,
      precip  REAL,
      lat_key REAL,
      lng_key REAL,
      at      TEXT NOT NULL,
      PRIMARY KEY (trip_id, date)
    )
  ''');
}

Future<void> createCacheSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS geocode_cache (
      grid    TEXT PRIMARY KEY,
      address TEXT NOT NULL,
      at      TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS meta (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');
}
