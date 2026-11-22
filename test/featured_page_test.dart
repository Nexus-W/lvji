import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:luji/app_state.dart';
import 'package:luji/data/models/import_item.dart';
import 'package:luji/data/repository.dart';
import 'package:luji/data/weather.dart';
import 'package:luji/features/trip_detail/featured_page.dart';
import 'package:luji/widgets/photo_marks.dart';
import 'package:luji/widgets/photo_thumb.dart';

import 'helpers/db_helper.dart';

void main() {
  testWidgets('精选页：概览卡 + 日期 chip + 优质照片展板', (tester) async {
    late Database db;
    late AppState appState;
    late String tripId;
    await tester.runAsync(() async {
      db = await openTestDb();
      appState = AppState(
        tripRepo: TripRepo(db),
        photoRepo: PhotoRepo(db),
        weather: WeatherService(db),
      );
      final t = await appState.tripRepo.create(
          name: '大理', start: DateTime(2026, 10, 2), end: DateTime(2026, 10, 6));
      tripId = t.id;
      await appState.photoRepo.importBatch(t.id, [
        for (var i = 0; i < 4; i++)
          ImportItem(
              uri: 'content://test/$i',
              hash: 'h$i',
              takenAt: DateTime(2026, 10, 2, 12),
              width: 100,
              height: 100),
      ]);
      final days = await appState.tripRepo.listDays(t.id);
      final photos = await appState.photoRepo.byDay(t.id, days.first.id);
      final ids = photos.map((p) => p.id).toList();
      await db.update('photos', {'is_cover': 1},
          where: 'id = ?', whereArgs: [ids[0]]);
      await db.update('photos', {'is_featured': 1},
          where: 'id = ?', whereArgs: [ids[1]]);
      await db.update('photos', {'note': '漂亮'},
          where: 'id = ?', whereArgs: [ids[2]]);
      await appState.reload();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: MaterialApp(home: FeaturedPage(tripId: tripId)),
      ),
    );
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pump();

    expect(find.text('大理'), findsOneWidget); // 头部标题
    expect(find.text('全部 5 天'), findsOneWidget); // 日期 chip
    // 默认「全部」：4 张都显示（导入后立刻能看到，不至于以为没导入）
    expect(find.byType(PhotoThumb), findsNWidgets(4));

    // 切到「精选」：只显示有标记的 3 张（封面/精选/备注）
    await tester.tap(find.text('精选'));
    await tester.pump();
    expect(find.byType(PhotoThumb), findsNWidgets(3));
    expect(find.byType(PhotoMarks), findsNWidgets(3));

    await tester.runAsync(() => db.close());
  });
}
