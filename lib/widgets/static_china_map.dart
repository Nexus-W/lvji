import 'package:flutter/material.dart';

import 'map_point.dart' show MapPoint;

/// 静态中国地图：深色底 + **点亮去过的城市**（红点 + 光晕 + 城市名）。
///
/// 底图 `assets/china_map.png`，投影参数与生成时保持一致。
class StaticChinaMap extends StatelessWidget {
  const StaticChinaMap({super.key, required this.points, this.onCityTap});

  final List<MapPoint> points;
  final ValueChanged<String>? onCityTap;

  // 与 china_map.png 生成时的投影一致
  // 与 assets/china_map.png 一致（扩到含南海诸岛与九段线）
  static const double _lngL = 73.0;
  static const double _lngR = 136.0;
  static const double _latT = 54.0;
  static const double _latB = 2.5;
  static const double _ratio = 1100 / 1000;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF05080B),
      child: Center(
        child: AspectRatio(
          aspectRatio: _ratio,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              return GestureDetector(
                onTapUp: (d) => _onTap(d.localPosition, size),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset('assets/china_map.png', fit: BoxFit.fill),
                    CustomPaint(painter: _CityPainter(points)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _onTap(Offset local, Size size) {
    if (onCityTap == null) return;
    // 找点击位置附近最近的城点（16px 内）
    String? bestId;
    var bestDist = 16.0;
    for (final p in points) {
      final x = (p.lng - _lngL) / (_lngR - _lngL) * size.width;
      final y = (_latT - p.lat) / (_latT - _latB) * size.height;
      final d = (Offset(x, y) - local).distance;
      if (d < bestDist) {
        bestDist = d;
        bestId = p.id;
      }
    }
    if (bestId != null) onCityTap!(bestId);
  }
}

class _CityPainter extends CustomPainter {
  _CityPainter(this.points);

  final List<MapPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    const lngL = StaticChinaMap._lngL;
    const lngR = StaticChinaMap._lngR;
    const latT = StaticChinaMap._latT;
    const latB = StaticChinaMap._latB;

    for (final p in points) {
      final x = (p.lng - lngL) / (lngR - lngL) * size.width;
      final y = (latT - p.lat) / (latT - latB) * size.height;
      final pos = Offset(x, y);

      // 光晕
      canvas.drawCircle(
          pos, 9, Paint()..color = const Color(0xFF3DDC97).withValues(alpha: .16));
      canvas.drawCircle(
          pos, 5.5, Paint()..color = const Color(0xFF3DDC97).withValues(alpha: .28));
      // 亮点
      canvas.drawCircle(pos, 3.0, Paint()..color = const Color(0xFF3DDC97));
      canvas.drawCircle(
        pos,
        3.0,
        Paint()
          ..color = Colors.white.withValues(alpha: .9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );

    }
  }

  @override
  bool shouldRepaint(covariant _CityPainter old) => old.points != points;
}
