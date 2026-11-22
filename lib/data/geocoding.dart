import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../core/app_config.dart';

/// 腾讯位置服务 WebService 地理编码（纯 HTTP，不引地图 SDK）。
///
/// 配额策略（个人 Key：1000 次/天、并发 1 次/秒）：
/// 1. **本地缓存**：坐标网格化到 0.0001°（约 11m），同一格子只请求一次，永久复用；
/// 2. **每日上限**：`meta` 表记当日调用数，超过 900 次直接返回 null（降级本地表）；
/// 3. **失败静默**：无 Key / 断网 / 超配额统一返回 null，调用方回退本地地名表。
class Geocoding {
  Geocoding._();

  static const _endpoint = 'https://apis.map.qq.com/ws/geocoder/v1/';

  /// 每日最多消耗的配额（留 100 次应急）。
  static const int _dailyLimit = 900;

  static Database? _db;

  /// App 启动时注入数据库（用于缓存与配额计数）。
  static void attach(Database db) => _db = db;

  /// 地名 → 坐标。
  static Future<(double, double)?> forward(String address) async {
    if (AppConfig.tmapKey.isEmpty) return null;
    final q = Uri.encodeComponent(address.trim());
    final data = await _get('$_endpoint?address=$q&key=${AppConfig.tmapKey}');
    if (data == null || data['status'] != 0) return null;
    final loc = (data['result'] as Map?)?['location'] as Map?;
    if (loc == null) return null;
    return ((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble());
  }

  /// 坐标 → 地名（优先缓存；配额不足直接返回 null）。
  static Future<String?> reverse(double lat, double lng) async {
    if (AppConfig.tmapKey.isEmpty) return null;

    final grid = '${lat.toStringAsFixed(4)}_${lng.toStringAsFixed(4)}';
    final db = _db;

    // ① 缓存命中
    if (db != null) {
      final rows = await db.query('geocode_cache',
          columns: ['address'], where: 'grid = ?', whereArgs: [grid], limit: 1);
      if (rows.isNotEmpty) return rows.first['address'] as String?;
    }

    // ② 配额检查
    if (db != null && !await _consumeQuota(db)) return null;

    // ③ 请求
    final data = await _get(
        '$_endpoint?location=$lat,$lng&key=${AppConfig.tmapKey}&get_poi=0');
    if (data == null || data['status'] != 0) return null;
    final result = data['result'] as Map?;
    final fa = result?['formatted_addresses'] as Map?;
    final recommend = fa?['recommend'] as String?;
    final addr = (recommend != null && recommend.isNotEmpty)
        ? recommend
        : result?['address'] as String?;
    if (addr == null || addr.isEmpty) return null;

    // ④ 写缓存
    if (db != null) {
      await db.insert(
        'geocode_cache',
        {
          'grid': grid,
          'address': addr,
          'at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    return addr;
  }

  /// 消耗一次当日配额；超额返回 false。
  static Future<bool> _consumeQuota(Database db) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final rows = await db.query('meta',
        where: 'key IN (?, ?)',
        whereArgs: ['geocode_date', 'geocode_count']);
    final map = {
      for (final r in rows) r['key'] as String: r['value'] as String,
    };
    var count = int.tryParse(map['geocode_count'] ?? '0') ?? 0;
    if (map['geocode_date'] != today) count = 0;
    if (count >= _dailyLimit) return false;

    count++;
    await db.insert('meta', {'key': 'geocode_date', 'value': today},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('meta', {'key': 'geocode_count', 'value': '$count'},
        conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  static Future<Map<String, dynamic>?> _get(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
