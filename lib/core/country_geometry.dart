import 'dart:convert';

import 'package:flutter/services.dart';

/// 一个国家的外形（多环多边形，坐标是 `[lng, lat]`，WGS-84）。
///
/// 全项目**唯一**的国家几何模型：足迹统计、世界地图点亮、世界地图绘制
/// 都用这一份，避免「同一份 252KB 数据解析两遍、射线法写两套」。
class CountryShape {
  CountryShape({required this.name, required this.polys}) {
    var x1 = double.infinity, y1 = double.infinity;
    var x2 = -double.infinity, y2 = -double.infinity;
    for (final poly in polys) {
      for (final p in poly) {
        if (p.dx < x1) x1 = p.dx;
        if (p.dx > x2) x2 = p.dx;
        if (p.dy < y1) y1 = p.dy;
        if (p.dy > y2) y2 = p.dy;
      }
    }
    minX = x1;
    minY = y1;
    maxX = x2;
    maxY = y2;
  }

  final String name;

  /// 每个环是 `[lng, lat]` 点列。
  final List<List<Offset>> polys;

  late final double minX, minY, maxX, maxY;

  /// 点是否在该国境内（先做 bbox 预检，再逐环射线法）。
  bool contains(double lng, double lat) {
    if (lng < minX || lng > maxX || lat < minY || lat > maxY) return false;
    for (final poly in polys) {
      if (_inPoly(lng, lat, poly)) return true;
    }
    return false;
  }

  static bool _inPoly(double x, double y, List<Offset> poly) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final xi = poly[i].dx, yi = poly[i].dy;
      final xj = poly[j].dx, yj = poly[j].dy;
      // 分母为 0 时退化处理，避免除零
      final dy = (yj - yi) == 0 ? 1e-9 : (yj - yi);
      if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / dy + xi) {
        inside = !inside;
      }
    }
    return inside;
  }
}

/// 国家几何的唯一入口：解析一次、全进程共享。
class CountryGeometry {
  CountryGeometry._();

  static const _asset = 'assets/world_countries.json';

  static List<CountryShape>? _shapes;
  static Future<void>? _loading;

  /// 已加载的形状（未加载时为空列表，调用方应先用 [ensureLoaded]）。
  static List<CountryShape> get shapes => _shapes ?? const [];

  /// 只解析一次；并发调用共享同一个 Future，不会解析两遍。
  static Future<void> ensureLoaded() {
    if (_shapes != null) return Future.value();
    // 失败后必须把 _loading 置空，否则失败会被永久缓存：
    // 后续所有调用都拿到同一个已失败的 Future，形状列表永远是空。
    return _loading ??= _load().catchError((Object e) {
      _loading = null;
      throw e;
    });
  }

  static Future<void> _load() async {
    final raw = await rootBundle.loadString(_asset);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    _shapes = [
      for (final c in data['countries'] as List)
        CountryShape(
          name: (c as Map<String, dynamic>)['n'] as String,
          polys: [
            for (final poly in c['p'] as List)
              [
                for (final pt in poly as List)
                  Offset((pt as List)[0] as double, pt[1] as double),
              ],
          ],
        ),
    ];
  }

  /// WGS-84 坐标 → 数据里的原始国家名（与 polygons 的 `name` 完全一致）。
  static String? countryAt(double lng, double lat) {
    for (final c in shapes) {
      if (c.contains(lng, lat)) return c.name;
    }
    return null;
  }
}
