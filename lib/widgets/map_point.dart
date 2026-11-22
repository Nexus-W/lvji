/// 地图上的一个点（照片或城市）。
///
/// 从原 `map_canvas.dart` 抽出：自绘地图组件已全部被真实地图/静态图替代，
/// 只剩这个数据结构还在用。
class MapPoint {
  final String id;
  final double lat;
  final double lng;
  final int count; // 单点 = 1；聚类后累加
  final String? label; // 城市名 / 地点名
  final String? thumbnail; // 照片缩略图 uri（气泡用）
  final Set<String> marks; // gold=封面 / green=精选 / violet=备注

  const MapPoint({
    required this.id,
    required this.lat,
    required this.lng,
    this.count = 1,
    this.label,
    this.thumbnail,
    this.marks = const {},
  });
}
