import '../../core/extensions.dart';

/// 照片索引。只管理索引，不持有像素数据；`uri` 指向本地文件或 content://。
class Photo {
  final String id;
  final String tripId;
  final String? dayId; // 无时间 = NULL
  final String uri;
  final String hash; // 文件 SHA1，用于去重
  final String? takenAt; // ISO8601，可空
  final double? lat;
  final double? lng;
  final String? place;
  final int width;
  final int height;
  final int isCover; // 0/1
  final int isFeatured; // 0/1
  final String note;
  final String? deletedAt;
  final String createdAt;

  const Photo({
    required this.id,
    required this.tripId,
    this.dayId,
    required this.uri,
    required this.hash,
    this.takenAt,
    this.lat,
    this.lng,
    this.place,
    required this.width,
    required this.height,
    this.isCover = 0,
    this.isFeatured = 0,
    this.note = '',
    this.deletedAt,
    required this.createdAt,
  });

  factory Photo.fromMap(Map<String, Object?> m) => Photo(
        id: m['id'] as String,
        tripId: m['trip_id'] as String,
        dayId: m['day_id'] as String?,
        uri: m['uri'] as String,
        hash: m['hash'] as String,
        takenAt: m['taken_at'] as String?,
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        place: m['place'] as String?,
        width: m['width'] as int,
        height: m['height'] as int,
        isCover: m['is_cover'] as int? ?? 0,
        isFeatured: m['is_featured'] as int? ?? 0,
        note: m['note'] as String? ?? '',
        deletedAt: m['deleted_at'] as String?,
        createdAt: m['created_at'] as String,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'trip_id': tripId,
        'day_id': dayId,
        'uri': uri,
        'hash': hash,
        'taken_at': takenAt,
        'lat': lat,
        'lng': lng,
        'place': place,
        'width': width,
        'height': height,
        'is_cover': isCover,
        'is_featured': isFeatured,
        'note': note,
        'deleted_at': deletedAt,
        'created_at': createdAt,
      };

  /// 统一的城市名（纯城市，如「成都市」）。
  /// 内部会：地址里有市名直接用，没有就用坐标反查城市表。
  String get city => cityOf(place, lat: lat, lng: lng);

  /// 统一的区县名（如「成都市锦江区」）。
  String get district => districtOf(place, lat: lat, lng: lng);
}
