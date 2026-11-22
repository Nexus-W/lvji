import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tencent_map/flutter_tencent_map.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'app_state.dart';
import 'core/app_config.dart';
import 'data/db.dart';
import 'data/weather.dart';
import 'data/geocoding.dart';
import 'data/repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  final db = await openAppDatabase(p.join(dir.path, 'luji.db'));
  // 读取本地 Key（腾讯位置服务），失败不影响启动。
  await AppConfig.load();
  // 地理编码缓存 / 配额计数需要数据库
  Geocoding.attach(db);
  // 腾讯地图 SDK 隐私合规（必须在创建地图前调用；失败不影响启动）。
  try {
    await TencentMapInitializer.setAgreePrivacy(true);
    await TencentMapInitializer.start();
  } catch (_) {
    // SDK 未配置好时静默失败，信息修正会显示兜底提示
  }
  final appState = AppState(
    tripRepo: TripRepo(db),
    photoRepo: PhotoRepo(db),
    weather: WeatherService(db),
  );

  // 先加载「界面需要的」数据（一次查询），让首帧尽快出现。
  await appState.reload();
  runApp(LujiApp(appState: appState));

  // 历史数据修复和历史清理放后台：这些以前都在 runApp 之前串行执行，
  // 是首次启动卡顿的主因（每多一个行程/照片都要多跑一轮 SQL）。
  unawaited(() async {
    try {
      await appState.photoRepo.backfillLocationFromPlace();
      await appState.photoRepo.repairLocationFromPlace();
      await appState.tripRepo.ensureDays();
      await appState.photoRepo.repairDeletedAt();
      await appState.photoRepo.repairFakeCoords();
      await appState.photoRepo.cleanupRecycle(7);
      // 修复可能改了显示相关数据，刷新一次（界面此时已经能操作了）
      await appState.reload();
    } catch (_) {
      // 修复失败不影响使用
    }
  }());
}
