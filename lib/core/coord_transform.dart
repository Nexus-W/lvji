import 'dart:math' as math;

/// 坐标系转换：WGS-84 ↔ GCJ-02。
///
/// 背景（务必理解，否则地图会偏几百米）：
/// - **WGS-84**：GPS 原始坐标（照片 EXIF、国际标准）
/// - **GCJ-02**：国测局加密坐标（腾讯/高德/百度地图都用它）
/// - 中国境内两者相差 **约 300~700 米**
///
/// 本项目约定：**数据库里统一存 GCJ-02**（因为所有地图渲染都用腾讯地图）。
/// - 导入照片：EXIF(WGS-84) → 转成 GCJ-02 再入库
/// - 点地图选点 / 地理编码：腾讯返回的本来就是 GCJ-02，直接用
class CoordTransform {
  CoordTransform._();

  static const double _a = 6378245.0; // 克拉索夫斯基椭球长半轴
  static const double _ee = 0.00669342162296594323; // 第一偏心率平方

  /// 是否在中国境外（境外不做偏移）。
  static bool outOfChina(double lat, double lng) {
    return lng < 72.004 || lng > 137.8347 || lat < 0.8293 || lat > 55.8271;
  }

  /// WGS-84 → GCJ-02。
  static (double, double) wgs84ToGcj02(double lat, double lng) {
    if (outOfChina(lat, lng)) return (lat, lng);
    var dLat = _transformLat(lng - 105.0, lat - 35.0);
    var dLng = _transformLng(lng - 105.0, lat - 35.0);
    final radLat = lat / 180.0 * math.pi;
    var magic = math.sin(radLat);
    magic = 1 - _ee * magic * magic;
    final sqrtMagic = math.sqrt(magic);
    dLat = (dLat * 180.0) /
        ((_a * (1 - _ee)) / (magic * sqrtMagic) * math.pi);
    dLng = (dLng * 180.0) / (_a / sqrtMagic * math.cos(radLat) * math.pi);
    return (lat + dLat, lng + dLng);
  }

  /// GCJ-02 → WGS-84（反解，误差 < 1 米，足够导航展示）。
  static (double, double) gcj02ToWgs84(double lat, double lng) {
    if (outOfChina(lat, lng)) return (lat, lng);
    final (gLat, gLng) = wgs84ToGcj02(lat, lng);
    return (lat * 2 - gLat, lng * 2 - gLng);
  }

  static double _transformLat(double x, double y) {
    var ret = -100.0 +
        2.0 * x +
        3.0 * y +
        0.2 * y * y +
        0.1 * x * y +
        0.2 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) +
            20.0 * math.sin(2.0 * x * math.pi)) *
        2.0 /
        3.0;
    ret += (20.0 * math.sin(y * math.pi) +
            40.0 * math.sin(y / 3.0 * math.pi)) *
        2.0 /
        3.0;
    ret += (160.0 * math.sin(y / 12.0 * math.pi) +
            320 * math.sin(y * math.pi / 30.0)) *
        2.0 /
        3.0;
    return ret;
  }

  static double _transformLng(double x, double y) {
    var ret = 300.0 +
        x +
        2.0 * y +
        0.1 * x * x +
        0.1 * x * y +
        0.1 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) +
            20.0 * math.sin(2.0 * x * math.pi)) *
        2.0 /
        3.0;
    ret += (20.0 * math.sin(x * math.pi) +
            40.0 * math.sin(x / 3.0 * math.pi)) *
        2.0 /
        3.0;
    ret += (150.0 * math.sin(x / 12.0 * math.pi) +
            300.0 * math.sin(x / 30.0 * math.pi)) *
        2.0 /
        3.0;
    return ret;
  }
}
