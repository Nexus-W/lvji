/// 行程里的"一天"（由起止日期生成，改日期时重建）。`date` 存 'YYYY-MM-DD'。
class Day {
  final String id;
  final String tripId;
  final String date;
  final String place;
  final int sort;

  const Day({
    required this.id,
    required this.tripId,
    required this.date,
    this.place = '',
    required this.sort,
  });

  factory Day.fromMap(Map<String, Object?> m) => Day(
        id: m['id'] as String,
        tripId: m['trip_id'] as String,
        date: m['date'] as String,
        place: m['place'] as String? ?? '',
        sort: m['sort'] as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'trip_id': tripId,
        'date': date,
        'place': place,
        'sort': sort,
      };
}
