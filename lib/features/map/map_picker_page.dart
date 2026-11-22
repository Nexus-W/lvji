import 'package:flutter/material.dart';
import 'package:flutter_tencent_map/flutter_tencent_map.dart';

import '../../core/theme.dart';

/// 全屏地图选点页。
///
/// 为什么不用底部弹层：`showModalBottomSheet` 里放腾讯地图（PlatformView）时，
/// 关闭弹层后原生地图视图经常**残留在屏幕上**（遮挡照片），切到后台再回来
/// 也容易把 UI 卡住。独立页面 push/pop 的生命周期干净得多。
class MapPickerPage extends StatefulWidget {
  const MapPickerPage({super.key, this.initialLat, this.initialLng});

  final double? initialLat;
  final double? initialLng;

  /// 返回 (lat, lng)；用户取消返回 null。
  static Future<(double, double)?> open(
    BuildContext context, {
    double? lat,
    double? lng,
  }) {
    return Navigator.of(context).push<(double, double)>(
      MaterialPageRoute(
        builder: (_) => MapPickerPage(initialLat: lat, initialLng: lng),
      ),
    );
  }

  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  double? _lat;
  double? _lng;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _lat = widget.initialLat;
    _lng = widget.initialLng;
  }

  @override
  Widget build(BuildContext context) {
    // 0,0 / 越界坐标视为无效（坏数据会把地图带到印度洋）
    final valid = _lat != null &&
        _lng != null &&
        !(_lat!.abs() < 0.01 && _lng!.abs() < 0.01) &&
        _lat!.abs() <= 90 &&
        _lng!.abs() <= 180;
    final has = valid;
    final target =
        has ? LatLng(_lat!, _lng!) : const LatLng(30.2741, 120.1551);

    return Scaffold(
      backgroundColor: panel2,
      appBar: AppBar(
        backgroundColor: panel,
        elevation: 0,
        title: const Text('选择位置',
            style: TextStyle(fontSize: fsCardTitle, color: t1)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: t2),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed:
                has ? () => Navigator.of(context).pop((_lat!, _lng!)) : null,
            child: Text('确定',
                style: TextStyle(
                    fontSize: fsBody,
                    fontWeight: FontWeight.w600,
                    color: has ? accent : t3)),
          ),
        ],
      ),
      body: Stack(
        children: [
          TencentMap(
            mapType: MapType.dark,
            initialCameraPosition:
                CameraPosition(target: target, zoom: has ? 14 : 4),
            // 只允许缩放/拖动，禁用旋转和倾斜（手机上很容易误触）
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            onMapLoaded: () {
              if (mounted) setState(() => _loaded = true);
            },
            onTap: (pos) => setState(() {
              _lat = pos.latitude;
              _lng = pos.longitude;
            }),
            markers: {
              if (has)
                Marker(
                  position: LatLng(_lat!, _lng!),
                  icon: BitmapDescriptor.defaultMarker,
                ),
            },
          ),
          if (!_loaded)
            const Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Color(0xCC0B1116),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: accent),
                        ),
                        SizedBox(height: 10),
                        Text('地图加载中…',
                            style: TextStyle(fontSize: 11, color: t3)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF080E12).withValues(alpha: .88),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: accent.withValues(alpha: .35)),
                ),
                child: Text(
                  has ? '拖动微调，点地图重新选点' : '点地图选择位置',
                  style: const TextStyle(fontSize: fsCaption, color: t2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
