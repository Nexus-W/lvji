import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:luji/app_state.dart';
import 'package:luji/data/models/import_item.dart';
import 'package:luji/data/repository.dart';
import 'package:luji/data/weather.dart';
import 'package:luji/features/trips/trips_page.dart';

import 'helpers/db_helper.dart';

void main() {
  testWidgets('列表页：渲染行程卡片与张数', (tester) async {
    late Database db;
    late AppState appState;
    await tester.runAsync(() async {
      db = await openTestDb();
      appState = AppState(
        tripRepo: TripRepo(db),
        photoRepo: PhotoRepo(db),
        weather: WeatherService(db),
      );
      final t = await appState.tripRepo.create(
          name: '大理', start: DateTime(2026, 10, 2), end: DateTime(2026, 10, 6));
      await appState.photoRepo.importBatch(t.id, [
        for (var i = 0; i < 3; i++)
          ImportItem(
              uri: 'content://test/$i',
              hash: 'h$i',
              takenAt: DateTime(2026, 10, 2, 12),
              width: 100,
              height: 100),
      ]);
      await appState.reload();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MaterialApp(home: TripsPage()),
      ),
    );
    await tester.pump();

    expect(find.text('大理'), findsOneWidget);
    expect(find.text('3 张'), findsOneWidget);
    expect(find.text('1 次 · 3 张'), findsOneWidget);

    await tester.runAsync(() => db.close());
  });
}
