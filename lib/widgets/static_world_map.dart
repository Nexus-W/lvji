import 'package:flutter/material.dart';

import '../core/coord_transform.dart';
import '../core/country_geometry.dart';
import 'map_point.dart' show MapPoint;

/// 静态世界地图：深色底 + **点亮去过的国家**，点击国家回调（展开城市列表）。
///
/// 底图和点亮逻辑用同一套等距圆柱投影，保证严格对齐。
class StaticWorldMap extends StatefulWidget {
  const StaticWorldMap({
    super.key,
    required this.points,
    this.lit,
    this.onCountryTap,
  });

  final List<MapPoint> points;

  /// 要点亮的国家名（与 `world_countries.json` 的 `n` 完全一致）。
  /// 由调用方给：世界地图的 `points` 故意不含中国境内的点，
  /// 只靠 points 反推会让「中国」永远点不亮。
  final Set<String>? lit;

  /// 点击某个已点亮国家（参数是国家名）。
  final ValueChanged<String>? onCountryTap;

  @override
  State<StaticWorldMap> createState() => _StaticWorldMapState();
}

class _StaticWorldMapState extends State<StaticWorldMap> {
  List<CountryShape> _countries = const [];
  Set<String> _lit = const {};
  bool _loading = true;

  // 与 world_countries.json 的投影参数一致
  static const double _latTop = 78.0;
  static const double _latBottom = -55.0;
  static const double _ratio = 2.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 由坐标点算出「去过哪些国家」。
  ///
  /// `_lit` 之前声明成 `const {}` 之后**再也没有赋值过**，
  /// 于是所有国家都是暗的（点亮功能实际失效）。
  /// 点位来自数据库（GCJ-02），国家多边形是 WGS-84，必须反转换。
  Set<String> _litFrom(List<MapPoint> points) {
    final lit = <String>{};
    for (final p in points) {
      final (wLat, wLng) = CoordTransform.gcj02ToWgs84(p.lat, p.lng);
      final name = CountryGeometry.countryAt(wLng, wLat);
      if (name != null && name.isNotEmpty) lit.add(name);
    }
    return lit;
  }

  Future<void> _load() async {
    // 与足迹统计共用同一份解析结果，不再自己读一遍 252KB JSON
    try {
      await CountryGeometry.ensureLoaded();
      if (!mounted) return;
      setState(() {
        _countries = CountryGeometry.shapes;
        _lit = widget.lit ?? _litFrom(widget.points);
        // 必须显式关掉 loading：合并几何模块时漏了这一行，
        // _loading 永远是 true → 地图一直转圈（数据其实早就好了）。
        _loading = false;
      });
    } catch (_) {
      // 加载失败也要退出 loading，否则用户永远看到转圈，
      // 连"地图没数据"这个事实都看不出来。
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  void didUpdateWidget(covariant StaticWorldMap old) {
    super.didUpdateWidget(old);
    // 点位数量变化才重算（List 的 != 是引用比较，父组件每次重建都会是新实例，
    // 直接用 != 会导致每帧都跑一遍「所有点 × 所有国家」的多边形判定）
    if ((old.points.length != widget.points.length ||
            old.lit != widget.lit) &&
        _countries.isNotEmpty) {
      setState(() => _lit = widget.lit ?? _litFrom(widget.points));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF05080B),
      child: Center(
        child: AspectRatio(
          aspectRatio: _ratio,
          child: _loading
              ? const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF3DDC97)),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.biggest;
                    return GestureDetector(
                      onTapUp: (d) => _onTap(d.localPosition, size),
                      child: CustomPaint(
                        size: size,
                        painter: _WorldPainter(
                          countries: _countries,
                          lit: _lit,
                          points: widget.points,
                          latTop: _latTop,
                          latBottom: _latBottom,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  void _onTap(Offset local, Size size) {
    // 屏幕坐标 → 经纬度
    final lng = local.dx / size.width * 360 - 180;
    final lat = _latTop - local.dy / size.height * (_latTop - _latBottom);
    for (final c in _countries) {
      if (_lit.contains(c.name) && c.contains(lng, lat)) {
        widget.onCountryTap?.call(c.name);
        return;
      }
    }
  }
}


class _WorldPainter extends CustomPainter {
  _WorldPainter({
    required this.countries,
    required this.lit,
    required this.points,
    required this.latTop,
    required this.latBottom,
  });

  final List<CountryShape> countries;
  final Set<String> lit;
  final List<MapPoint> points;
  final double latTop;
  final double latBottom;

  @override
  void paint(Canvas canvas, Size size) {
    final land = Paint()..color = const Color(0xFF141B23);
    final litFill = Paint()..color = const Color(0xFF3DDC97).withValues(alpha: .30);
    final litBorder = Paint()
      ..color = const Color(0xFF3DDC97)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (final c in countries) {
      final on = lit.contains(c.name);
      for (final poly in c.polys) {
        final path = Path();
        double? prevX;
        for (var i = 0; i < poly.length; i++) {
          final x = (poly[i].dx + 180) / 360 * size.width;
          final y = (latTop - poly[i].dy) / (latTop - latBottom) * size.height;
          // 跨日界线（经度从 +180 跳到 -180）时 x 会横穿整幅图，
          // 必须断开，否则俄罗斯/南极会画出一条横贯全图的假线。
          if (prevX != null && (x - prevX).abs() > size.width * 0.5) {
            path.moveTo(x, y);
          } else if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
          prevX = x;
        }
        path.close();
        canvas.drawPath(path, on ? litFill : land);
        // 未点亮的国家不描边（线条太多太碍眼），只保留点亮国家的轮廓
        if (on) canvas.drawPath(path, litBorder);
      }
    }

    // 城市红点（只在已点亮国家上显示）
    for (final p in points) {
      final x = (p.lng + 180) / 360 * size.width;
      final y = (latTop - p.lat) / (latTop - latBottom) * size.height;
      canvas.drawCircle(
          Offset(x, y), 5, Paint()..color = const Color(0xFFFF4D4D).withValues(alpha: .22));
      canvas.drawCircle(Offset(x, y), 2.0, Paint()..color = const Color(0xFFFF4D4D));
    }
  }

  @override
  bool shouldRepaint(covariant _WorldPainter old) =>
      old.countries != countries || old.lit != lit || old.points != points;
}
