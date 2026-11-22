/// 行程。纯数据对象，无 UI。
/// 日期字段 `startDate`/`endDate` 存 'YYYY-MM-DD'。
class Trip {
  final String id;
  final String name;
  final String startDate;
  final String endDate;
  final String? country;
  final String? province;
  final String? city;
  final double? lat;
  final double? lng;
  final String note;
  final String? coverPhoto;
  final String? deletedAt;
  final String createdAt;
  final String updatedAt;

  const Trip({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    this.country,
    this.province,
    this.city,
    this.lat,
    this.lng,
    this.note = '',
    this.coverPhoto,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Trip.fromMap(Map<String, Object?> m) => Trip(
        id: m['id'] as String,
        name: m['name'] as String,
        startDate: m['start_date'] as String,
        endDate: m['end_date'] as String,
        country: m['country'] as String?,
        province: m['province'] as String?,
        city: m['city'] as String?,
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        note: m['note'] as String? ?? '',
        coverPhoto: m['cover_photo'] as String?,
        deletedAt: m['deleted_at'] as String?,
        createdAt: m['created_at'] as String,
        updatedAt: m['updated_at'] as String,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'start_date': startDate,
        'end_date': endDate,
        'country': country,
        'province': province,
        'city': city,
        'lat': lat,
        'lng': lng,
        'note': note,
        'cover_photo': coverPhoto,
        'deleted_at': deletedAt,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}
