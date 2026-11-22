import 'dart:convert';

import 'package:flutter/services.dart';

import 'map_point.dart' show MapPoint;

/// 中国省份索引：判断坐标属于哪个省，并把同省的点合并成一个。
///
/// 数据来自 `assets/china_provinces.json`（DataV 省界，34 个省级单位）。
/// 用途：足迹页/小地图「一个省份最多一个点」，避免同城多点挤在一起。
class ProvinceIndex {
  ProvinceIndex._();

  static List<_Prov>? _list;

  static Future<void> ensureLoaded() async {
    if (_list != null) return;
    final raw = await rootBundle.loadString('assets/china_provinces.json');
    final data = jsonDecode(raw) as List;
    _list = [
      for (final e in data)
        _Prov(
          name: (e as Map)['n'] as String,
          polys: [
            for (final poly in e['p'] as List)
              [
                for (final pt in poly as List)
                  Offset((pt as List)[0] as double, pt[1] as double),
              ],
          ],
        ),
    ];
  }

  /// 坐标 → 省份名（匹配不到返回 null）。
  static String? provinceOf(double lat, double lng) {
    final list = _list;
    if (list == null) return null;
    for (final p in list) {
      if (p.contains(lng, lat)) return p.name;
    }
    return null;
  }

  /// 同省只保留一个点：坐标取该省所有点的平均，`count` 累加。
  /// `key` 为 null 的点（匹配不到省份）单独保留。
  static List<MapPoint> dedupe(List<MapPoint> points) {
    if (points.length <= 1) return points;
    final groups = <String, List<MapPoint>>{};
    for (final p in points) {
      final key = provinceOf(p.lat, p.lng) ?? '__${p.id}';
      groups.putIfAbsent(key, () => []).add(p);
    }
    return [
      for (final e in groups.entries)
        MapPoint(
          id: e.value.first.id,
          lat: e.value.map((p) => p.lat).reduce((a, b) => a + b) /
              e.value.length,
          lng: e.value.map((p) => p.lng).reduce((a, b) => a + b) /
              e.value.length,
          label: e.value.first.label,
          count: e.value.fold<int>(0, (s, p) => s + p.count),
        ),
    ];
  }
}

class _Prov {
  _Prov({required this.name, required this.polys});

  final String name;
  final List<List<Offset>> polys;

  late final (double, double, double, double) bbox = _calc();

  (double, double, double, double) _calc() {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final poly in polys) {
      for (final p in poly) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
    }
    return (minX, minY, maxX, maxY);
  }

  bool contains(double lng, double lat) {
    final (minX, minY, maxX, maxY) = bbox;
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
      if ((yi > y) != (yj > y) &&
          x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
        inside = !inside;
      }
    }
    return inside;
  }
}
