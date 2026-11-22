import 'place_table.dart';

import 'dart:math';

final Random _rng = Random.secure();

/// 生成 UUID v4 字符串。
///
/// 不引入 `uuid` 包：技术方案 §2.3 未列出该依赖，为遵守「不要引入未列出的依赖」
/// 而手写实现（仅生成 id 用，无需全局唯一校验）。
String newUuid() {
  final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// DateTime → 'YYYY-MM-DD'。
///
/// 技术方案 §4.1 / 验收标准 §3：日期字段一律存该格式字符串，
/// 不要存 `toIso8601String()`，否则 `BETWEEN` 会带上时间漏掉最后一天。
String ymd(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// DateTime → 'YYYY-MM-DD HH:mm'，用于界面展示拍摄时间。
String ymdHm(DateTime d) {
  final h = d.hour.toString().padLeft(2, '0');
  final m = d.minute.toString().padLeft(2, '0');
  return '${ymd(d)} $h:$m';
}

/// 数字千分位加逗号（技术方案 附录B：2,482 张）。
String fmtNum(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// 地址「到区」：从完整地址里抽出「XX市XX区/县」。
///
/// 例：
/// - `四川省成都市锦江区东大街…` → `成都市锦江区`
/// - `锦江区成都光环购物公园…`（无市名）→ `锦江区`
/// - 境外/无法识别 → 原样返回（截断到 12 字）
String shortPlace(String? place) {
  if (place == null) return '未标注';
  final p = place.trim();
  if (p.isEmpty) return '未标注';

  // 1) 市 + 区/县/市（县级市）
  final both = RegExp(r'([\u4e00-\u9fa5]{2,8}?市)([\u4e00-\u9fa5]{2,8}?[区县])')
      .firstMatch(p);
  if (both != null) return '${both.group(1)}${both.group(2)}';

  // 2) 只有区/县（腾讯 recommend 常只给「锦江区…」）
  final dist = RegExp(r'^([\u4e00-\u9fa5]{2,8}?[区县])').firstMatch(p);
  if (dist != null) return dist.group(1)!;

  // 3) 省 + 市（直辖市/地级市）
  final city = RegExp(r'([\u4e00-\u9fa5]{2,8}?市)').firstMatch(p);
  if (city != null) return city.group(1)!;

  // 4) 兜底：截断
  return p.length <= 12 ? p : '${p.substring(0, 12)}…';
}

/// 城市级：「德阳市」（地址里没市名时用坐标反查城市表补上）。
String cityOf(String? place, {double? lat, double? lng}) {
  final p = (place ?? '').trim();

  // ① 坐标优先：城市表里命中且距离够近（<0.6°≈60km），比正则可靠。
  //    典型坑：「西湖区北山杭州市」用正则会被切成「北山杭州市」。
  if (lat != null && lng != null) {
    final (c, dist) = nearestPlaceWithDist(lat, lng);
    // 距离 < 0.36 度²（约 0.6°≈60km）才采纳，太远说明不在城市表覆盖范围
    if (dist < 0.36) {
      return c.endsWith('市') ? c : '$c市';
    }
  }

  // ② 地址里若包含已知城市名（城市表）→ 直接用它
  //    「西湖区北山杭州市」→ 命中「杭州」→「杭州市」，不会被切成「北山杭州市」
  for (final row in cityTable) {
    if (p.contains(row.$1)) {
      return row.$1.endsWith('市') ? row.$1 : '${row.$1}市';
    }
  }

  // ③ 地址里最后一个「市」往前取 2~4 字，跳过含省/区/县/镇的候选
  //    「四川省成都市…」→ 试「省成都市」(含省) → 「成都市」✅
  //    「呼和浩特市…」→ 「呼和浩特市」✅
  final idx = p.lastIndexOf('市');
  if (idx >= 2) {
    for (var len = 4; len >= 2; len--) {
      final start = idx - len + 1;
      if (start < 0) continue;
      final candidate = p.substring(start, idx + 1);
      if (RegExp(r'[省区县镇]').hasMatch(candidate)) continue;
      return candidate;
    }
  }

  // ④ 退到「市」开头的 2~8 字
  final m = RegExp(r'([^省市区县镇]{2,8}市)').firstMatch(p);
  if (m != null) return m.group(1)!;

  return p.isEmpty ? '未标注' : p;
}

/// 区县级：「德阳市旌阳区」/「德阳市旌阳镇」；没有区县时退回城市。
String districtOf(String? place, {double? lat, double? lng}) {
  final city = cityOf(place, lat: lat, lng: lng);
  final p = (place ?? '').trim();
  final m = RegExp(r'([^省市]{2,8}(?:区|县|镇))').firstMatch(p);
  if (m == null) return city;
  final d = m.group(1)!;
  // 区名里已含城市名就不重复拼接
  if (d.contains(city) || city.contains(d)) return d;
  // 区名本身带「市」的情况（如「XX市XX区」被整体匹配）
  if (d.contains('市')) return d;
  return '$city$d';
}

/// `2026-10-28` → `10月28日`。三处（地图/精选/导入）原本各写一份，逐字相同。
String dayLabel(String date) {
  if (date.length < 10) return date;
  final m = int.tryParse(date.substring(5, 7));
  final d = int.tryParse(date.substring(8, 10));
  if (m == null || d == null) return date;
  return '$m月$d日';
}

/// `[start, end]` 闭区间的日期 key 列表（升序，自动纠正起止反了）。
///
/// 用 `DateTime(y, m, d + 1)` 步进而不是 `add(Duration(days: 1))`：
/// 后者按 24 小时推进，跨夏令时会重复或跳过某一天。
List<String> dateRange(DateTime start, DateTime end) {
  var a = DateTime(start.year, start.month, start.day);
  var b = DateTime(end.year, end.month, end.day);
  if (a.isAfter(b)) {
    final t = a;
    a = b;
    b = t;
  }
  final out = <String>[];
  for (var d = a; !d.isAfter(b); d = DateTime(d.year, d.month, d.day + 1)) {
    out.add(ymd(d));
  }
  return out;
}
