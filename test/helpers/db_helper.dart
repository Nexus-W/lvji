import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:luji/data/db.dart';

/// 打开一个独立的测试数据库（内存库，每个用例各自新建，互不污染）。
///
/// 关键：`PRAGMA foreign_keys = ON` 必须走 `onConfigure`（连接级设置），
/// 否则外键与级联删除会静默失效（验收标准 §3 坑 1/2）。
Future<Database> openTestDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    ),
  );
  await createSchema(db);
  return db;
}
