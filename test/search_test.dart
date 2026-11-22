import 'package:flutter_test/flutter_test.dart';

import 'package:luji/data/models/import_item.dart';
import 'package:luji/data/repository.dart';

import 'helpers/db_helper.dart';

void main() {
  test('搜索：同一行程的多个城市都能命中', () async {
    final db = await openTestDb();
    final trips = TripRepo(db);
    final photos = PhotoRepo(db);

    final t = await trips.create(
        name: '云南环线', start: DateTime(2026, 10, 2), end: DateTime(2026, 10, 8));
    await photos.importBatch(t.id, [
      for (var i = 0; i < 4; i++)
        ImportItem(
            uri: 'content://test/$i',
            hash: 'h$i',
            takenAt: DateTime(2026, 10, 2 + i, 12),
            width: 100,
            height: 100),
    ]);

    // 三张照片分别落在三个城市（模拟逆地理编码结果）
    final rows = await db.query('photos', orderBy: 'taken_at');
    final places = [
      '四川省 · 成都市 · 锦里',
      '云南省 · 大理市 · 洱海',
      '云南省 · 丽江市 · 古城',
      // 只有区名、没有市名：搜「德阳」必须靠 cityOf 反查
      '旌阳区',
    ];
    for (var i = 0; i < rows.length && i < places.length; i++) {
      await db.update('photos', {'place': places[i]},
          where: 'id = ?', whereArgs: [rows[i]['id']]);
    }

    // 给「旌阳区」那条补坐标，让 cityOf 能反查到德阳市
    await db.update(
      'photos',
      {'lat': 31.13, 'lng': 104.40},
      where: 'place = ?', whereArgs: ['旌阳区'],
    );

    // 三个城市都要能搜到同一个行程
    for (final q in ['成都', '大理', '丽江', '德阳', '旌阳区']) {
      final hit = await trips.search(q);
      expect(hit.map((e) => e.id), contains(t.id), reason: '搜「$q」应命中');
    }

    // 手记也能搜
    await db.update('trips', {'note': '风大得能把人吹下山'},
        where: 'id = ?', whereArgs: [t.id]);
    expect((await trips.search('吹下山')).map((e) => e.id), contains(t.id));

    // 搜不到的关键字返回空
    expect(await trips.search('东京'), isEmpty);

    await db.close();
  });
}
