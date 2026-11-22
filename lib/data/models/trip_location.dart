/// 行程在足迹地图上的「城市点」（聚合自该行程内有坐标的照片）。
class TripLocation {
  final String tripId;
  final String name;
  final double lat;
  final double lng;
  final String? place; // 取自第一张有坐标照片的地名（可空）
  final int photoCount;

  const TripLocation({
    required this.tripId,
    required this.name,
    required this.lat,
    required this.lng,
    this.place,
    required this.photoCount,
  });
}
