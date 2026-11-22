import 'package:flutter_test/flutter_test.dart';

import 'helpers/db_helper.dart';

void main() {
  test('全新建库必须包含 weather_daily 表（新用户不走升级路径）', () async {
    final db = await openTestDb();
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'");
    final names = tables.map((r) => r['name'] as String).toSet();
    for (final t in [
      'trips', 'days', 'photos', 'imports', 'geocode_cache', 'meta',
      'weather_daily',
    ]) {
      expect(names, contains(t), reason: '缺表：$t');
    }
    // 关键列也要在（cover_set_at 是 v4 加的）
    final cols = await db.rawQuery('PRAGMA table_info(photos)');
    final colNames = cols.map((r) => r['name'] as String).toSet();
    expect(colNames, contains('cover_set_at'));
    // 封面部分索引必须在（v5），否则 coverUrisByTrip 会全表扫
    final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index'");
    final idxNames = indexes.map((r) => r['name'] as String).toSet();
    expect(idxNames, contains('idx_photos_cover'),
        reason: '缺封面索引 idx_photos_cover');

    await db.close();
  });
}
