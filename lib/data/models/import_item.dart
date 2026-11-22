/// 待导入的一条照片。
///
/// 设计约束（验收标准 §2）：DAO 不读文件、不解析 EXIF，
/// `hash` 由调用方在 Isolate 里算好传入。
/// `uri` 可空：null 表示该条在读取阶段已失败（对应 T13「模拟损坏」），
/// `importBatch` 会把它计入 `failed` 而非中断整批。
class ImportItem {
  final String? uri;
  final String hash;
  final DateTime? takenAt;
  final double? lat;
  final double? lng;
  final int width;
  final int height;

  const ImportItem({
    this.uri,
    required this.hash,
    this.takenAt,
    this.lat,
    this.lng,
    required this.width,
    required this.height,
  });
}
