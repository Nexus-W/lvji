import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_tencent_map/flutter_tencent_map.dart';

import 'map_point.dart' show MapPoint;
import 'photo_thumb.dart';

/// 行程大地图：真实底图（腾讯 dark）+ **缩略图气泡**（不是水滴图钉）。
///
/// 性能要点：
/// - 气泡最多 12 个（按屏幕 55px 聚合），屏幕外的点直接丢弃
/// - 相机移动只做纯计算 + setState，不重建地图本身
/// - 气泡各自 `RepaintBoundary`，缩略图 `PhotoThumb` 自带 cacheWidth
class RealBubbleMap extends StatefulWidget {
  const RealBubbleMap({
    super.key,
    required this.points,
    this.onClusterTap,
    this.onPointTap,
  });

  final List<MapPoint> points;

  /// 多点合并的气泡：参数是地点名。
  final ValueChanged<String>? onClusterTap;

  /// 单张照片气泡：参数是照片 id。
  final ValueChanged<String>? onPointTap;

  @override
  State<RealBubbleMap> createState() => _RealBubbleMapState();
}

class _RealBubbleMapState extends State<RealBubbleMap> {
  CameraPosition? _cam;
  bool _ready = false;
  TencentMapController? _ctrl;
  // zoom 0 时的世界宽度（px）。各家地图这个基准不同（256/512），
  // 用 SDK 的 getScreenCoordinate 实测校准一次，之后任意 zoom 都准。
  double? _baseWorld;

  // ---------- Web Mercator 投影（与腾讯地图一致）----------
  static double _mercX(double lng) => (lng + 180) / 360;
  static double _mercY(double lat) {
    final s = math.sin(lat * math.pi / 180).clamp(-0.9999, 0.9999);
    return 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
  }

  Offset _toScreen(double lat, double lng, Size size, CameraPosition cam) {
    final world = (_baseWorld ?? 256.0) * math.pow(2, cam.zoom);
    final dx = (_mercX(lng) - _mercX(cam.target.longitude)) * world;
    final dy = (_mercY(lat) - _mercY(cam.target.latitude)) * world;
    return Offset(size.width / 2 + dx, size.height / 2 + dy);
  }

  /// 用 SDK 实测「1 经度 = 多少像素」，反推 zoom 0 的世界宽度。
  Future<void> _calibrate() async {
    final c = _ctrl;
    if (c == null) return;
    try {
      final center = _cam?.target ?? const LatLng(30.0, 120.0);
      final p1 = await c.getScreenCoordinate(center);
      final p2 = await c.getScreenCoordinate(
          LatLng(center.latitude, center.longitude + 0.01));
      final dx = (p2.x - p1.x).abs();
      if (dx < 0.5) return;
      final zoom = _cam?.zoom ?? 4;
      final base = dx / 0.01 * 360 / math.pow(2, zoom);
      if (mounted) setState(() => _baseWorld = base);
    } catch (_) {
      // 校准失败就退回 256 基准（大多数情况够用）
    }
  }

  /// 按屏幕距离聚合（55px → 一个气泡），最多 12 个。
  List<_Bubble> _buildBubbles(Size size, CameraPosition cam) {
    final cells = <String, List<(MapPoint, Offset)>>{};
    for (final p in widget.points) {
      final s = _toScreen(p.lat, p.lng, size, cam);
      if (s.dx < -100 ||
          s.dy < -100 ||
          s.dx > size.width + 100 ||
          s.dy > size.height + 100) {
        continue; // 屏幕外不参与
      }
      // 按「地点」聚类（不再按屏幕格子）：同一地点才合并，
      // 避免把不同地点混进一个气泡导致点击跳错相册。
      final key = (p.label == null || p.label!.trim().isEmpty)
          ? 'id:${p.id}'
          : 'p:${p.label!.trim()}';
      cells.putIfAbsent(key, () => []).add((p, s));
    }

    final bubbles = <_Bubble>[];
    for (final e in cells.values) {
      final center =
          e.map((x) => x.$2).reduce((a, b) => a + b) / e.length.toDouble();
      final first = e.first.$1;
      bubbles.add(_Bubble(
        id: first.id,
        label: first.label,
        count: e.length,
        screen: center,
        thumbs: [
          for (final x in e)
            if (x.$1.thumbnail != null) x.$1.thumbnail!,
        ],
      ));
    }
    bubbles.sort((a, b) => b.count.compareTo(a.count));
    return bubbles.take(12).toList();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final cam = _cam;
        final bubbles =
            (cam == null || !_ready) ? <_Bubble>[] : _buildBubbles(size, cam);

        return Stack(
          children: [
            Positioned.fill(
              child: TencentMap(
                mapType: MapType.dark,
                initialCameraPosition: _initialCamera(size),
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                onMapCreated: (c) => _ctrl = c,
                onMapLoaded: () async {
                  if (mounted) setState(() => _ready = true);
                  _calibrate();
                  // initialCameraPosition 在部分机型上不生效，这里强制把镜头
                  // 移到第一张照片（单点时 zoom 14，多点时按范围自适应）。
                  final pts = widget.points;
                  if (pts.isEmpty) return;
                  final first = pts.first;
                  try {
                    await _ctrl?.moveCamera(
                      CameraUpdate.newLatLngZoom(
                        LatLng(first.lat, first.lng),
                        pts.length == 1 ? 14 : 6,
                      ),
                    );
                  } catch (_) {}
                },
                onCameraMove: (c) => setState(() => _cam = c),
                onCameraMoveEnd: (c) => setState(() => _cam = c),
              ),
            ),
            // 气泡层：Stack 本身透明，空白处事件会穿透给地图。
            for (final b in bubbles)
              Positioned(
                left: b.screen.dx + 10,
                top: b.screen.dy - 19,
                child: RepaintBoundary(
                  child: _BubbleView(
                    bubble: b,
                    onTap: () {
                      if (b.count > 1) {
                        if (b.label != null) widget.onClusterTap?.call(b.label!);
                      } else {
                        widget.onPointTap?.call(b.id);
                      }
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  CameraPosition _initialCamera(Size size) {
    final pts = widget.points;
    if (pts.isEmpty) {
      return const CameraPosition(target: LatLng(30.2741, 120.1551), zoom: 4);
    }
    if (pts.length == 1) {
      return CameraPosition(
          target: LatLng(pts.first.lat, pts.first.lng), zoom: 13);
    }
    var minLat = double.infinity, maxLat = -double.infinity;
    var minLng = double.infinity, maxLng = -double.infinity;
    for (final p in pts) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }
    final lngSpan = math.max((maxLng - minLng).abs(), 0.002);
    final latSpan = math.max((maxLat - minLat).abs(), 0.002);
    final w = size.width <= 0 ? 390.0 : size.width;
    final h = size.height <= 0 ? 300.0 : size.height;
    final zx = math.log(w * 360 / (256 * lngSpan)) / math.ln2;
    final zy = math.log(h * 180 / (256 * latSpan)) / math.ln2;
    final zoom = (math.min(zx, zy) - 0.3).clamp(3.0, 14.0);
    return CameraPosition(
      target: LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2),
      zoom: zoom,
    );
  }
}

class _Bubble {
  _Bubble({
    required this.id,
    required this.label,
    required this.count,
    required this.screen,
    required this.thumbs,
  });

  final String id;
  final String? label;
  final int count;
  final Offset screen;
  final List<String> thumbs;
}

/// 缩略图气泡（原型 .cluster 的 Flutter 版）：负边距堆叠 + 地点 + 张数。
class _BubbleView extends StatelessWidget {
  const _BubbleView({required this.bubble, required this.onTap});

  final _Bubble bubble;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final thumbs = bubble.thumbs.take(3).toList();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 160),
        height: 38,
        padding: const EdgeInsets.fromLTRB(3, 3, 10, 3),
        decoration: BoxDecoration(
          color: const Color(0xFF080E12).withValues(alpha: .9),
          borderRadius: BorderRadius.circular(19),
          border: Border.all(
              color: const Color(0xFF3DDC97).withValues(alpha: .55)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x99000000),
                blurRadius: 12,
                offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (thumbs.isNotEmpty)
              SizedBox(
                width: 32.0 + (thumbs.length - 1) * 14,
                height: 32,
                child: Stack(
                  children: [
                    for (var i = 0; i < thumbs.length; i++)
                      Positioned(
                        left: i * 14.0,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: .6)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: PhotoThumb(uri: thumbs[i]),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(width: 7),
            Flexible(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (bubble.label != null && bubble.label!.isNotEmpty)
                    Text(
                      bubble.label!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFE9EEF6)),
                    ),
                  Text('${bubble.count} 张',
                      style: const TextStyle(
                          fontSize: 9, color: Color(0xFF9AA6B6))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
