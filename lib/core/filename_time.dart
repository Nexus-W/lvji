/// 从文件名推断拍摄时间（**只在 EXIF 没有时间时兜底**）。
///
/// 微信/QQ 传图会剥掉 EXIF，但文件名通常保留了时间：
/// - `IMG_20261029_203600.jpg`
/// - `20261029_203600.jpg`
/// - `微信图片_20261029203600.jpg`
/// - `mmexport1698567890123.jpg`（Unix 毫秒）
///
/// 解析不出来就返回 null，**绝不瞎猜**（宁可显示"时间未知"）。
DateTime? timeFromFileName(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final base = name.contains('.')
      ? name.substring(0, name.lastIndexOf('.'))
      : name;

  // ① 13 位 Unix 毫秒（微信 mmexport 导出）
  final ms = RegExp(r'(1[5-9]\d{11})').firstMatch(base);
  if (ms != null) {
    final v = int.tryParse(ms.group(1)!);
    if (v != null) {
      final t = DateTime.fromMillisecondsSinceEpoch(v);
      if (t.year >= 2010 && t.year <= 2100) return t;
    }
  }

  // ② 年月日 + 时分秒：20261029_203600 / 2026-10-29 20.36.00 / 2026:10:29 20:36:00
  final m = RegExp(
    r'(20\d{2})[-_.: ]?(\d{2})[-_.: ]?(\d{2})[-_.: T]?(\d{2})[-_.:]?(\d{2})[-_.:]?(\d{2})',
  ).firstMatch(base);
  if (m != null) {
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    final h = int.parse(m.group(4)!);
    final mi = int.parse(m.group(5)!);
    final s = int.parse(m.group(6)!);
    if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31 &&
        h <= 23 && mi <= 59 && s <= 59) {
      return DateTime(y, mo, d, h, mi, s);
    }
  }

  // ③ 只有日期：20261029（时分默认为 12:00，放中午避免跨天歧义）
  final dm = RegExp(r'(20\d{2})[-_.]?(\d{2})[-_.]?(\d{2})').firstMatch(base);
  if (dm != null) {
    final y = int.parse(dm.group(1)!);
    final mo = int.parse(dm.group(2)!);
    final d = int.parse(dm.group(3)!);
    if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
      return DateTime(y, mo, d, 12);
    }
  }
  return null;
}
