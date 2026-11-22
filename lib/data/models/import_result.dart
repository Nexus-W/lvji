/// 一次导入批次的结果。
/// `byDay`：dayId -> 张数，key 为 'unknown' 表示时间未知（未分组）。
class ImportResult {
  final int inserted;
  final int skipped; // 因 UNIQUE(trip_id, hash) 被跳过
  final int failed; // 读取失败
  final Map<String, int> byDay;

  const ImportResult({
    required this.inserted,
    required this.skipped,
    required this.failed,
    required this.byDay,
  });
}
