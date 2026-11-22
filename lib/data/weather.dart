import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../core/coord_transform.dart';
import '../core/extensions.dart';

/// 一天的天气（只保留展示需要的字段）。
class DayWeather {
  const DayWeather({
    required this.date,
    required this.code,
    required this.tmax,
    required this.tmin,
    required this.precip,
  });

  /// YYYY-MM-DD
  final String date;

  /// WMO weather code（0 晴、1-3 多云、45-48 雾、51-67 雨、71-77 雪、80-82 阵雨、95-99 雷）
  final int code;
  final double tmax;
  final double tmin;
  final double precip;

  bool get isRain => (code >= 51 && code <= 67) || (code >= 80 && code <= 82);
  bool get isSnow => code >= 71 && code <= 77;
  bool get isThunder => code >= 95;
  bool get isCloudy => code >= 1 && code <= 3;
  bool get isFog => code == 45 || code == 48;

  /// 给 UI 用的中文短描述。
  String get label {
    if (isThunder) return '雷';
    if (isSnow) return '雪';
    if (isRain) return '雨';
    if (isFog) return '雾';
    if (code == 0) return '晴';
    if (isCloudy) return '云';
    return '';
  }

  factory DayWeather.fromJson(String date, Map<String, dynamic> d) => DayWeather(
        date: date,
        code: (d['code'] as num?)?.toInt() ?? 0,
        tmax: (d['tmax'] as num?)?.toDouble() ?? 0,
        tmin: (d['tmin'] as num?)?.toDouble() ?? 0,
        precip: (d['precip'] as num?)?.toDouble() ?? 0,
      );
}

/// 历史天气（Open-Meteo Archive，免费、无需 Key、不上传用户信息）。
///
/// 设计原则：
/// - **按行程一次性拉整段日期**（一次请求覆盖 N 天，不是每天一次）
/// - 结果写 `weather_daily` 缓存，之后不再联网
/// - **失败静默**：拿不到就返回空 map，UI 退回占位图标，绝不阻塞任何操作
class WeatherService {
  WeatherService(this._db);

  final Database _db;

  /// 只用历史库：旅迹是**事后相册**，没发生的天气不该出现在卡片上。
  /// archive 的数据只到「昨天」，所以请求前把 end_date 截到昨天；
  /// 行程还没开始（start > 昨天）就直接不请求。
  static const _host = 'archive-api.open-meteo.com';
  static const _path = '/v1/archive';

  /// 坐标网格（0.1° ≈ 11km）：同城内不失效，跨城会重新取。
  static double _grid(double v) => (v * 10).round() / 10;

  /// 读缓存。坐标变了（或旧数据没有坐标列）视为未命中。
  Future<Map<String, DayWeather>> cached(String tripId,
      {double? lat, double? lng}) async {
    final rows = await _db.query('weather_daily',
        where: 'trip_id = ?', whereArgs: [tripId]);
    final latKey = lat == null ? null : _grid(lat);
    final lngKey = lng == null ? null : _grid(lng);
    final out = <String, DayWeather>{};
    for (final r in rows) {
      final code = r['code'] as int?;
      if (code == null) continue;
      // 坐标不一致（含旧数据的 null）→ 这条缓存不可用
      if (latKey != null &&
          (r['lat_key'] == null ||
              (r['lat_key'] as num).toDouble() != latKey)) {
        continue;
      }
      if (lngKey != null &&
          (r['lng_key'] == null ||
              (r['lng_key'] as num).toDouble() != lngKey)) {
        continue;
      }
      out[r['date'] as String] = DayWeather(
        date: r['date'] as String,
        code: code,
        tmax: (r['tmax'] as num?)?.toDouble() ?? 0,
        tmin: (r['tmin'] as num?)?.toDouble() ?? 0,
        precip: (r['precip'] as num?)?.toDouble() ?? 0,
      );
    }
    return out;
  }

  /// 按「每天各自的坐标」取天气（跨城行程用这个）。
  ///
  /// [dayCoords]：`{日期: (lat, lng)}`，由 `TripRepo.dayLocations` 提供。
  /// 算法：读缓存（逐天校验坐标）→ 把缺的天按坐标网格分组 → 每组一次请求。
  /// 同城多天只发一次请求，跨城才多发。
  Future<Map<String, DayWeather>> forDays({
    required String tripId,
    required Map<String, (double, double)> dayCoords,
  }) async {
    if (dayCoords.isEmpty) return const {};

    // ① 读缓存并按天校验坐标
    final rows = await _db.query('weather_daily',
        where: 'trip_id = ?', whereArgs: [tripId]);
    final cached = <String, DayWeather>{};
    for (final r in rows) {
      final date = r['date'] as String?;
      final code = r['code'] as int?;
      if (date == null || code == null) continue;
      final coord = dayCoords[date];
      if (coord == null) continue;
      // 坐标不一致 → 这条缓存不是这天的天气
      if (r['lat_key'] == null || r['lng_key'] == null) continue;
      if ((r['lat_key'] as num).toDouble() != _grid(coord.$1)) continue;
      if ((r['lng_key'] as num).toDouble() != _grid(coord.$2)) continue;
      cached[date] = DayWeather(
        date: date,
        code: code,
        tmax: (r['tmax'] as num?)?.toDouble() ?? 0,
        tmin: (r['tmin'] as num?)?.toDouble() ?? 0,
        precip: (r['precip'] as num?)?.toDouble() ?? 0,
      );
    }

    // ② 缺的天按坐标网格分组
    final missing = <String, List<String>>{}; // gridKey -> dates
    final gridOf = <String, (double, double)>{};
    for (final e in dayCoords.entries) {
      if (cached.containsKey(e.key)) continue;
      final g = '${_grid(e.value.$1)},${_grid(e.value.$2)}';
      missing.putIfAbsent(g, () => []).add(e.key);
      gridOf[g] = e.value;
    }
    // ignore: avoid_print
    print('[Weather] trip=${tripId.substring(0, 8)} '
        'cached=${cached.length} missingDays=${missing.length} '
        'groups=${missing.length}');

    if (missing.isEmpty) return cached;

    final out = <String, DayWeather>{...cached};
    for (final g in missing.keys) {
      final (la, ln) = gridOf[g]!;
      final dates = missing[g]!..sort();
      final got = await _fetchRange(
        tripId: tripId,
        lat: la,
        lng: ln,
        startDate: dates.first,
        endDate: dates.last,
      );
      // 只采纳这组真正需要的日期
      for (final d in dates) {
        final w = got[d];
        if (w != null) out[d] = w;
      }
    }
    return out;
  }

  /// 单点请求：查 [startDate, endDate] 这段历史天气并写缓存。
  /// 供 `forDays`（按天坐标）使用。
  Future<Map<String, DayWeather>> _fetchRange({
    required String tripId,
    required double lat,
    required double lng,
    required String startDate,
    required String endDate,
  }) async {
    final cachedMap = await cached(tripId, lat: lat, lng: lng);
    final out = <String, DayWeather>{};
    try {
      final (wLat, wLng) = CoordTransform.gcj02ToWgs84(lat, lng);

      // 把结束日期截到「昨天」：今天和未来没有历史天气，不编造。
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final tripEnd = DateTime.tryParse(endDate);
      final tripStart = DateTime.tryParse(startDate);
      if (tripEnd == null || tripStart == null) return out;

      final clampedEnd = tripEnd.isAfter(yesterday) ? yesterday : tripEnd;
      if (clampedEnd.isBefore(tripStart)) {
        // ignore: avoid_print
        print('[Weather] 行程尚未结束（$startDate..$endDate），暂无历史天气');
        return out;
      }
      final queryEnd = ymd(clampedEnd);
      // ignore: avoid_print
      print('[Weather] archive $startDate..$queryEnd at $wLat,$wLng');

      final uri = Uri.https(_host, _path, {
        'latitude': wLat.toStringAsFixed(4),
        'longitude': wLng.toStringAsFixed(4),
        'start_date': startDate,
        'end_date': queryEnd,
        'daily':
            'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum',
        'timezone': 'auto',
      });
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      late String body;
      try {
        final req = await client.getUrl(uri).timeout(const Duration(seconds: 10));
        final res = await req.close().timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) return out;
        body = await res
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 12));
      } finally {
        client.close(force: true);
      }

      final json = jsonDecode(body) as Map<String, dynamic>;
      final daily = json['daily'] as Map<String, dynamic>?;
      if (daily == null) return out;

      final dates = (daily['time'] as List?)?.cast<String>() ?? const [];
      final codes = (daily['weather_code'] as List?) ?? const [];
      final tmaxs = (daily['temperature_2m_max'] as List?) ?? const [];
      final tmins = (daily['temperature_2m_min'] as List?) ?? const [];
      final precips = (daily['precipitation_sum'] as List?) ?? const [];

      final batch = _db.batch();
      for (var i = 0; i < dates.length; i++) {
        final d = DayWeather(
          date: dates[i],
          code: (codes.length > i ? codes[i] as num? : null)?.toInt() ?? 0,
          tmax: (tmaxs.length > i ? tmaxs[i] as num? : null)?.toDouble() ?? 0,
          tmin: (tmins.length > i ? tmins[i] as num? : null)?.toDouble() ?? 0,
          precip:
              (precips.length > i ? precips[i] as num? : null)?.toDouble() ?? 0,
        );
        out[d.date] = d;
        batch.insert(
          'weather_daily',
          conflictAlgorithm: ConflictAlgorithm.replace,
          {
            'trip_id': tripId,
            'date': d.date,
            'code': d.code,
            'tmax': d.tmax,
            'tmin': d.tmin,
            'precip': d.precip,
            // 必须存**入参**（GCJ-02）的网格，不能存转换后的 WGS：
            // 读缓存时比对的是数据库里的 GCJ 坐标，存 WGS 会永远对不上，
            // 导致每次都重新请求、且离线时读不出已有天气。
            'lat_key': _grid(lat),
            'lng_key': _grid(lng),
            'at': DateTime.now().toIso8601String(),
          },
        );
      }
      await batch.commit(noResult: true);
    } catch (e) {
      // ignore: avoid_print
      print('[Weather] 请求失败: $e');
    }
    return {...cachedMap, ...out};
  }

}
