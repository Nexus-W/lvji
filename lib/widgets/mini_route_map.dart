import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'map_point.dart' show MapPoint;

/// 精选页小地图：**自绘行程缩略图** + 一个「当前位置」标记。
///
/// 标记样式：空心圆（白描边 + 淡红填充）+ 底部小尾巴（指向行进方向），
/// 外加呼吸脉冲；点不同 chip 时标记会平滑滑到新位置。
class MiniRouteMap extends StatefulWidget {
  const MiniRouteMap({
    super.key,
    required this.points,
    this.activeLat,
    this.activeLng,
  });

  /// 按时间排序的行程点（第一个是起点）。
  final List<MapPoint> points;

  /// 当前选中 chip 对应的位置。
  final double? activeLat;
  final double? activeLng;

  @override
  State<MiniRouteMap> createState() => _MiniRouteMapState();
}

class _MiniRouteMapState extends State<MiniRouteMap>
    with TickerProviderStateMixin {
  // 呼吸脉冲（循环）
  late final AnimationController _pulse;
  // 位置平移补间
  late final AnimationController _move;

  double? _fromLat, _fromLng, _toLat, _toLng;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _move = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _toLat = widget.activeLat;
    _toLng = widget.activeLng;
  }

  @override
  void didUpdateWidget(covariant MiniRouteMap old) {
    super.didUpdateWidget(old);
    if (old.activeLat != widget.activeLat ||
        old.activeLng != widget.activeLng) {
      // 从「当前显示的插值位置」滑到新位置
      _fromLat = _toLat;
      _fromLng = _toLng;
      _toLat = widget.activeLat;
      _toLng = widget.activeLng;
      _move.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _move.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulse, _move]),
        builder: (context, _) {
          return CustomPaint(
            size: Size.infinite,
            painter: _MiniPainter(
              points: widget.points,
              pulse: _pulse.value,
              activeLat: _interpLat(),
              activeLng: _interpLng(),
            ),
          );
        },
      ),
    );
  }

  double? _interpLat() {
    if (_toLat == null) return null;
    if (_fromLat == null) return _toLat;
    final t = Curves.easeOutCubic.transform(_move.value);
    return _fromLat! + (_toLat! - _fromLat!) * t;
  }

  double? _interpLng() {
    if (_toLng == null) return null;
    if (_fromLng == null) return _toLng;
    final t = Curves.easeOutCubic.transform(_move.value);
    return _fromLng! + (_toLng! - _fromLng!) * t;
  }
}

class _MiniPainter extends CustomPainter {
  _MiniPainter({
    required this.points,
    required this.pulse,
    required this.activeLat,
    required this.activeLng,
  });

  final List<MapPoint> points;
  final double pulse;
  final double? activeLat;
  final double? activeLng;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF0A1116));
    if (points.isEmpty) return;

    // 包围盒（active 也纳入，避免箭头跑出框）+ 等比例投影
    var minLat = double.infinity, maxLat = -double.infinity;
    var minLng = double.infinity, maxLng = -double.infinity;
    for (final p in points) {
      if (p.lat.abs() < 0.01 && p.lng.abs() < 0.01) continue; // 0,0 = 坏坐标
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
    }
    if (activeLat != null && activeLng != null) {
      minLat = math.min(minLat, activeLat!);
      maxLat = math.max(maxLat, activeLat!);
      minLng = math.min(minLng, activeLng!);
      maxLng = math.max(maxLng, activeLng!);
    }
    final latSpan = math.max(maxLat - minLat, 0.01);
    final lngSpan = math.max(maxLng - minLng, 0.01);
    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;

    const pad = 16.0;
    final w = math.max(size.width - pad * 2, 1.0);
    final h = math.max(size.height - pad * 2, 1.0);
    final s = math.min(w / lngSpan, h / latSpan);

    Offset project(double lat, double lng) => Offset(
          size.width / 2 + (lng - centerLng) * s,
          size.height / 2 - (lat - centerLat) * s,
        );

    // 等高线背景（两组同心扰动椭圆，透明度极低，只做地形暗示）
    final contour = Paint()
      ..color = Colors.white.withValues(alpha: .05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    for (final c in [
      Offset(size.width * 0.26, size.height * 0.32),
      Offset(size.width * 0.78, size.height * 0.74),
    ]) {
      for (var i = 1; i <= 3; i++) {
        final rx = size.width * 0.13 * i;
        final ry = size.height * 0.11 * i;
        final path = Path();
        const seg = 44;
        for (var j = 0; j <= seg; j++) {
          final a = j / seg * math.pi * 2;
          final wob = 1 + 0.13 * math.sin(a * 3 + i * 1.7);
          final x = c.dx + math.cos(a) * rx * wob;
          final y = c.dy + math.sin(a) * ry * wob;
          if (j == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
        canvas.drawPath(path, contour);
      }
    }

    // 路线：全部实线（统一视觉，靠箭头移动体现进度）
    if (points.length >= 2) {
      final linePaint = Paint()
        ..color = const Color(0xFF3DDC97).withValues(alpha: .55)
        ..style = PaintingStyle.stroke // ← 不写这个会被填充成多边形
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final pt = project(points[i].lat, points[i].lng);
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(path, linePaint);
    }

    // 途经点（小绿点，会被当前位置标记完全盖住）
    for (final p in points) {
      final pos = project(p.lat, p.lng);
      canvas.drawCircle(
          pos, 3.2, Paint()..color = const Color(0xFF3DDC97).withValues(alpha: .22));
      canvas.drawCircle(pos, 1.8, Paint()..color = const Color(0xFF3DDC97));
    }

    // 当前位置标记（空心圆 + 小尾巴 + 呼吸脉冲）
    final aLat = activeLat;
    final aLng = activeLng;
    if (aLat == null || aLng == null) return;
    final pos = project(aLat, aLng);

    // 呼吸脉冲
    canvas.drawCircle(
      pos,
      7.0 + pulse * 7.5,
      Paint()
        ..color = const Color(0xFFFF4D4D).withValues(alpha: (1 - pulse) * .26),
    );

    // 方向：朝向下一个点
    var dir = const Offset(0, -1);
    for (final p in points) {
      final d = Offset(p.lng - aLng, p.lat - aLat);
      if (d.distance > 0.0001) {
        dir = Offset(d.dx, -d.dy);
        break;
      }
    }
    final angle = math.atan2(dir.dy, dir.dx) + math.pi / 2;



    // 当前位置：小箭头（约为原空心圆的 60%，指向行进方向）
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(angle);
    final arrow = Path()
      ..moveTo(0, -4.2)
      ..lineTo(-3.0, 2.6)
      ..lineTo(0, 1.2)
      ..lineTo(3.0, 2.6)
      ..close();
    // 白色描边打底，保证盖住下面的绿点
    canvas.drawPath(
      arrow,
      Paint()
        ..color = Colors.white.withValues(alpha: .92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(arrow, Paint()..color = const Color(0xFFFF4D4D));
    canvas.restore();
  }



  @override
  bool shouldRepaint(covariant _MiniPainter old) => true;
}
