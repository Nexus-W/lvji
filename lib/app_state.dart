import 'package:flutter/foundation.dart';

import 'data/models/trip.dart';
import 'data/repository.dart';
import 'data/weather.dart';

/// 唯一的全局状态（技术方案 §6.4）。
///
/// 只持有一份行程列表与"当前打开行程"，页面内部状态一律用 setState，
/// 不为每个页面建 ViewModel。
class AppState extends ChangeNotifier {
  final TripRepo tripRepo;
  final PhotoRepo photoRepo;
  final WeatherService weather;

  List<Trip> trips = [];
  Trip? current;

  /// tripId -> 张数（列表卡片展示用）。
  Map<String, int> photoCounts = {};

  /// tripId -> 封面拼贴（最多 3 张 uri，对应原型「1 大 + 2 小」）。
  Map<String, List<String>> covers = {};

  /// 缺坐标照片总数（列表页顶部提醒条用）。
  int missingCount = 0;

  /// 数据版本号：每次 reload 自增。
  /// 地图页/精选页/足迹页不 watch 照片表，只 watch 这个数字，
  /// 变了就重新加载——补完位置后不用退出重进。
  int _rev = 0;
  int get rev => _rev;

  /// 第一个「真的有缺位置照片」的行程 id。
  /// 主页提示条点进去要落到它，而不是无脑用 trips.first（那个行程可能一张都不缺）。
  String? missingTripId;

  AppState({
    required this.tripRepo,
    required this.photoRepo,
    required this.weather,
  });

  /// 重新加载行程列表（创建/删除/改名后调用）。
  Future<void> reload() async {
    trips = await tripRepo.listAlive();
    // 两条聚合 SQL 搞定，替代原来「每个行程查 4 次」的 N+1
    final stats = await photoRepo.statsByTrip();
    final coverUris = await photoRepo.coverUrisByTrip();

    final counts = <String, int>{};
    var missing = 0;
    String? firstMissingTrip;
    for (final t in trips) {
      final stat = stats[t.id];
      counts[t.id] = stat?.$1 ?? 0;
      final m = stat?.$2 ?? 0;
      missing += m;
      if (m > 0) firstMissingTrip ??= t.id;
    }
    missingTripId = firstMissingTrip;
    photoCounts = counts;
    covers = {
      for (final t in trips) t.id: coverUris[t.id] ?? const <String>[],
    };
    missingCount = missing;
    _rev++;
    notifyListeners();
  }

  /// 关闭数据库连接（恢复备份前必须调用，否则覆盖 luji.db 会被占用）。
  Future<void> closeDb() async {
    await tripRepo.close();
  }

  /// 轻量刷新：只递增版本号并通知，不重查 trips/统计/封面。
  /// 用于「精选 / 封面 / 手记」这类只影响照片自身标记、不影响行程汇总的改动。
  void bumpPhotos() {
    _rev++;
    notifyListeners();
  }

  /// 打开某行程；找不到返回 null（§8.1 不兜底）。
  Future<Trip?> openTrip(String id) async {
    current = await tripRepo.find(id);
    if (current != null) notifyListeners();
    return current;
  }

  /// 新建行程（列表页「＋」菜单里的唯一写入口，阶段 B 为跑通只读链路而做）。
  Future<Trip> createTrip({
    required String name,
    required DateTime start,
    required DateTime end,
  }) async {
    final trip = await tripRepo.create(name: name, start: start, end: end);
    await reload();
    return trip;
  }
}
