import 'country_geometry.dart';
import 'coord_transform.dart';

/// 国家判定的唯一来源。
///
/// 之前足迹页用「经纬度是否落在中国矩形内」粗判国家（中国 + 境外算 2 个），
/// 导致泰国、波兰都被算成"境外"，世界地图也只点亮 1 个境外国家。
/// 这里改为读取与 `StaticWorldMap` 同一份 `world_countries.json` 做多边形判定，
/// 保证「统计数字 / 地图点亮 / 下方分组」三处口径一致。
/// 国家名中英映射（数据源是英文名，界面显示中文）。
/// 只收录常见旅行目的地，匹配不到就显示原名。
const Map<String, String> _cnNames = {
  'China': '中国',
  'Thailand': '泰国',
  'Poland': '波兰',
  'Japan': '日本',
  'South Korea': '韩国',
  'North Korea': '朝鲜',
  'Vietnam': '越南',
  'Laos': '老挝',
  'Cambodia': '柬埔寨',
  'Myanmar': '缅甸',
  'Malaysia': '马来西亚',
  'Singapore': '新加坡',
  'Indonesia': '印度尼西亚',
  'Philippines': '菲律宾',
  'Brunei': '文莱',
  'India': '印度',
  'Nepal': '尼泊尔',
  'Bhutan': '不丹',
  'Sri Lanka': '斯里兰卡',
  'Maldives': '马尔代夫',
  'Mongolia': '蒙古',
  'Russia': '俄罗斯',
  'United States of America': '美国',
  'Canada': '加拿大',
  'Mexico': '墨西哥',
  'Brazil': '巴西',
  'Argentina': '阿根廷',
  'Chile': '智利',
  'Peru': '秘鲁',
  'United Kingdom': '英国',
  'France': '法国',
  'Germany': '德国',
  'Italy': '意大利',
  'Spain': '西班牙',
  'Portugal': '葡萄牙',
  'Netherlands': '荷兰',
  'Belgium': '比利时',
  'Switzerland': '瑞士',
  'Austria': '奥地利',
  'Czechia': '捷克',
  'Hungary': '匈牙利',
  'Greece': '希腊',
  'Turkey': '土耳其',
  'Norway': '挪威',
  'Sweden': '瑞典',
  'Finland': '芬兰',
  'Denmark': '丹麦',
  'Iceland': '冰岛',
  'Australia': '澳大利亚',
  'New Zealand': '新西兰',
  'Egypt': '埃及',
  'Morocco': '摩洛哥',
  'South Africa': '南非',
  'Kenya': '肯尼亚',
  'United Arab Emirates': '阿联酋',
  'Saudi Arabia': '沙特阿拉伯',
  'Israel': '以色列',
  'Qatar': '卡塔尔',
};

class CountryIndex {
  CountryIndex._();

  static Future<void> ensureLoaded() => CountryGeometry.ensureLoaded();

  /// 坐标 → **数据里的原始国家名**（世界地图点亮用，必须与 polygons 的
  /// `name` 完全一致；数据里「中国」本身就是中文，不能映射成 China）。
  static String? countryOfRaw(double lat, double lng) {
    // 数据库存的是 GCJ-02（腾讯地图用），Natural Earth 多边形是 WGS-84。
    // 不反转换的话，中国境内的点会整体往东偏几百米。
    final (wLat, wLng) = CoordTransform.gcj02ToWgs84(lat, lng);
    return CountryGeometry.countryAt(wLng, wLat);
  }

  /// 从地名猜国家：「泰国普吉府直辖县」→ 泰国、「波兰喀尔巴阡山省Krosno」→ 波兰。
  ///
  /// 比坐标判定更可靠——小岛（普吉）和国界附近的小国（欧洲）靠多边形经常
  /// 判不出来，但地名本身往往以国名开头。
  static String? byPlace(String? place) {
    final p = (place ?? '').trim();
    if (p.length < 2) return null;

    // 中文国名优先（长名先匹配，避免「中国」抢「中国香港」这类）
    final cn = _cnNames.values.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final name in cn) {
      if (name.length >= 2 && p.startsWith(name)) return name;
    }
    // 英文国名（大小写不敏感）
    final lower = p.toLowerCase();
    final en = _cnNames.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in en) {
      if (key.length >= 3 && lower.startsWith(key.toLowerCase())) {
        return _cnNames[key];
      }
    }
    return null;
  }

  /// 地名 → **数据原始名**（世界地图点亮用）。
  static String? byPlaceRaw(String? place) {
    final cn = byPlace(place);
    if (cn == null) return null;
    for (final e in _cnNames.entries) {
      if (e.value == cn) return e.key;
    }
    return cn;
  }

  /// 坐标 → 显示用国家名（中文，匹配不到返回 null）。
  ///
  /// 数据源是 Natural Earth 的低精度轮廓，一些小岛（如普吉）不在多边形里，
  /// 所以多边形失败时再退一步：落在某个国家包围盒内且该盒只对应一个国家，
  /// 就认为是该国——避免「泰国普吉」被判成未知。
  /// 显示名（中文）→ 数据里的原名。
  ///
  /// 地图点亮、多边形匹配必须用**原名**（`CountryShape.name`），
  /// 用显示名会出现「中国亮、印尼不亮」：数据里中国是中文，印尼是 Indonesia。
  static String? rawOf(String displayName) {
    // ① 数据里本身就写成中文的（目前只有「中国」）→ 原样返回。
    //    走下面的映射会被转成 'China'，反而和 CountryShape.name 对不上。
    if (_rawChineseNames.contains(displayName)) return displayName;
    // ② 显示名 → 数据原名（印度尼西亚 → Indonesia）
    for (final e in _cnNames.entries) {
      if (e.value == displayName) return e.key;
    }
    return displayName;
  }

  /// `world_countries.json` 里**本身就是中文**的国家名。
  /// 目前只有「中国」；新增数据源时同步维护这里。
  static const Set<String> _rawChineseNames = {'中国'};

  static String? countryOf(double lat, double lng) {
    final raw = countryOfRaw(lat, lng);
    if (raw == null) return null;
    return _cnNames[raw] ?? raw;
  }
}

