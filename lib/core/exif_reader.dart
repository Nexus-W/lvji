import 'dart:typed_data';

/// 手写 EXIF 读取器：不依赖 `exif` 包。
///
/// 为什么不用现成库：
/// - `exif` 包在 release(AOT) 下对同一份字节会解出 `0/1, 0/1, 0/1`（JIT 下正常），
///   真机上表现为「时间能读、坐标全 0」；
/// - `androidx.exifinterface` 在部分 ROM（如 Android 17 的 OPPO）上同样返回 false。
///
/// 这里直接按规范解析：
/// - JPEG：扫 APP1(FFE1 + "Exif\0\0") → TIFF
/// - HEIC：扫 `meta` box → `iinf` 找 Exif item → `iloc` 取偏移 → TIFF
/// - TIFF：IFD0 → GPS IFD(0x8825) → 经纬度（0x0002 / 0x0004）+ 方向（0x0001 / 0x0003）
class ExifResult {
  final double? lat;
  final double? lng;
  final DateTime? takenAt;

  const ExifResult({this.lat, this.lng, this.takenAt});

  bool get hasLocation => lat != null && lng != null;
}

ExifResult readExif(Uint8List bytes) {
  try {
    final tiff = _locateTiff(bytes);
    if (tiff == null) return const ExifResult();
    return _parseTiff(tiff);
  } catch (_) {
    return const ExifResult();
  }
}

/// 从 JPEG 或 HEIC 中定位 TIFF 段。
Uint8List? _locateTiff(Uint8List b) {
  if (b.length < 12) return null;

  // JPEG: FF D8 ...
  if (b[0] == 0xFF && b[1] == 0xD8) return _findJpegApp1(b);

  // HEIC/HEIF: 4 字节 size + "ftyp"
  if (b.length > 12 &&
      b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
    return _findHeicExif(b);
  }
  return null;
}

// ---------------- JPEG ----------------

Uint8List? _findJpegApp1(Uint8List b) {
  var i = 2;
  while (i + 4 <= b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = b[i + 1];
    // 无长度的标记
    if (marker == 0xD8 || marker == 0xD9 || marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }
    if (i + 4 > b.length) break;
    final len = (b[i + 2] << 8) | b[i + 3];
    if (len < 2) break;
    // APP1 且以 "Exif\0\0" 开头
    if (marker == 0xE1 &&
        i + 10 <= b.length &&
        b[i + 4] == 0x45 && // E
        b[i + 5] == 0x78 && // x
        b[i + 6] == 0x69 && // i
        b[i + 7] == 0x66 && // f
        b[i + 8] == 0x00 &&
        b[i + 9] == 0x00) {
      final start = i + 10;
      final end = i + 2 + len;
      if (end <= b.length && end > start) {
        return Uint8List.sublistView(b, start, end);
      }
    }
    i += 2 + len;
  }
  return null;
}

// ---------------- HEIC ----------------

Uint8List? _findHeicExif(Uint8List b) {
  // meta box 通常是顶层 box 之一，也可能在 moov 里；这里做一次浅层扫描
  final meta = _findBox(b, 0, b.length, 'meta');
  if (meta == null) return null;

  // meta 是 full box：box 头 8 字节 + version(1) + flags(3)
  var p = meta.start + meta.header + 4;
  final children = <_Box>[];
  while (p + 8 <= meta.end) {
    final size = _readU32(b, p);
    final type = String.fromCharCodes(b, p + 4, p + 8);
    var boxSize = size;
    var header = 8;
    if (size == 1) {
      // 64 位大小
      if (p + 16 > meta.end) break;
      boxSize = _readU64(b, p + 8);
      header = 16;
    } else if (size == 0) {
      boxSize = meta.end - p;
    }
    if (boxSize < header) break;
    children.add(_Box(type, p, p + boxSize, header));
    p += boxSize;
  }

  // iinf：找 itemType == 'Exif' 的 itemID
  final exifIds = <int>[];
  for (final c in children) {
    if (c.type == 'iinf') {
      exifIds.addAll(_parseIinf(b, c));
    }
  }
  if (exifIds.isEmpty) return null;

  // iloc：取对应 item 的绝对偏移与长度
  for (final c in children) {
    if (c.type == 'iloc') {
      final loc = _parseIloc(b, c, exifIds.first);
      if (loc != null) {
        final (offset, length) = loc;
        var e = offset + length;
        if (e > b.length) e = b.length;
        var s = offset;

        // HEIC 的 Exif item 结构（实测 OPPO/iPhone 一致）：
        //   4 字节头（值 = "Exif\0\0" 的长度 0x0a）
        //   FF E1 + 2 字节长度（JPEG APP1）
        //   "Exif\0\0"
        //   TIFF（"II"/"MM" 开始）
        // 逐段跳过，最后落到 TIFF 起点。
        if (s + 4 <= e) s += 4;
        if (s + 2 <= e && b[s] == 0xFF && b[s + 1] == 0xE1) s += 4;
        if (s + 6 <= e &&
            b[s] == 0x45 && b[s + 1] == 0x78 && b[s + 2] == 0x69 &&
            b[s + 3] == 0x66) {
          s += 6;
        }
        // 兜底：直接搜 "II"/"MM"
        if (s + 4 > e ||
            !((b[s] == 0x49 && b[s + 1] == 0x49) ||
                (b[s] == 0x4D && b[s + 1] == 0x4D))) {
          for (var k = offset; k + 4 <= e; k++) {
            if ((b[k] == 0x49 && b[k + 1] == 0x49 && b[k + 2] == 0x2A) ||
                (b[k] == 0x4D && b[k + 1] == 0x4D && b[k + 3] == 0x2A)) {
              s = k;
              break;
            }
          }
        }
        if (e > s) return Uint8List.sublistView(b, s, e);
      }
    }
  }
  return null;
}

class _Box {
  final String type;
  final int start;
  final int end;
  final int header;
  const _Box(this.type, this.start, this.end, this.header);
}

_Box? _findBox(Uint8List b, int from, int to, String type) {
  var p = from;
  while (p + 8 <= to) {
    final size = _readU32(b, p);
    final t = String.fromCharCodes(b, p + 4, p + 8);
    var boxSize = size;
    var header = 8;
    if (size == 1) {
      if (p + 16 > to) return null;
      boxSize = _readU64(b, p + 8);
      header = 16;
    } else if (size == 0) {
      boxSize = to - p;
    }
    if (boxSize < header) return null;
    if (t == type) return _Box(t, p, p + boxSize, header);
    p += boxSize;
  }
  return null;
}

/// iinf 里收集 itemType == 'Exif' 的 itemID。
List<int> _parseIinf(Uint8List b, _Box box) {
  final ids = <int>[];
  var p = box.start + box.header;
  // iinf 是 full box
  if (p + 4 > box.end) return ids;
  final version = b[p];
  p += 4;
  int count;
  if (version == 0) {
    if (p + 2 > box.end) return ids;
    count = (b[p] << 8) | b[p + 1];
    p += 2;
  } else {
    if (p + 4 > box.end) return ids;
    count = _readU32(b, p);
    p += 4;
  }
  for (var i = 0; i < count && p + 8 <= box.end; i++) {
    final size = _readU32(b, p);
    if (size < 8 || p + size > box.end) break;
    final type = String.fromCharCodes(b, p + 4, p + 8);
    if (type == 'infe') {
      // infe: full box(4) + itemID(2/4) + protection(2) + itemType(4) + name
      var q = p + 8;
      final v = b[q];
      q += 4;
      int itemId;
      if (v == 2) {
        itemId = (b[q] << 8) | b[q + 1];
        q += 2;
      } else if (v >= 3) {
        itemId = _readU32(b, q);
        q += 4;
      } else {
        itemId = (b[q] << 8) | b[q + 1];
        q += 2;
      }
      q += 2; // protection index
      if (q + 4 <= p + size) {
        final itemType = String.fromCharCodes(b, q, q + 4);
        if (itemType == 'Exif') ids.add(itemId);
      }
    }
    p += size;
  }
  return ids;
}

/// iloc 里取指定 item 的 (绝对偏移, 长度)。
(int, int)? _parseIloc(Uint8List b, _Box box, int targetId) {
  var p = box.start + box.header;
  if (p + 4 > box.end) return null;
  final version = b[p];
  p += 4;
  if (p + 2 > box.end) return null;
  // offset_size(4bit) + length_size(4bit)
  final s1 = b[p];
  p++;
  final s2 = b[p];
  p++;
  final offsetSize = s1 >> 4;
  final lengthSize = s1 & 0x0F;
  final baseOffsetSize = s2 >> 4;
  final indexSize = (version >= 1) ? (s2 & 0x0F) : 0;

  int itemCount;
  if (version < 2) {
    itemCount = (b[p] << 8) | b[p + 1];
    p += 2;
  } else {
    if (p + 4 > box.end) return null;
    itemCount = _readU32(b, p);
    p += 4;
  }

  for (var i = 0; i < itemCount; i++) {
    int itemId;
    if (version < 2) {
      if (p + 2 > box.end) return null;
      itemId = (b[p] << 8) | b[p + 1];
      p += 2;
    } else {
      if (p + 4 > box.end) return null;
      itemId = _readU32(b, p);
      p += 4;
    }

    int method = 0;
    if (version >= 1) {
      if (p + 2 > box.end) return null;
      method = (b[p] & 0x0F);
      p += 2;
    }
    if (p + 2 > box.end) return null;
    p += 2; // data_reference_index

    int baseOffset = 0;
    if (baseOffsetSize > 0) {
      if (p + baseOffsetSize > box.end) return null;
      baseOffset = _readN(b, p, baseOffsetSize);
      p += baseOffsetSize;
    }
    if (p + 2 > box.end) return null;
    final extentCount = (b[p] << 8) | b[p + 1];
    p += 2;

    int? firstOffset;
    int firstLength = 0;
    for (var e = 0; e < extentCount; e++) {
      if (indexSize > 0) p += indexSize;
      final off = _readN(b, p, offsetSize);
      p += offsetSize;
      final len = _readN(b, p, lengthSize);
      p += lengthSize;
      if (firstOffset == null) {
        firstOffset = (method == 0) ? off : baseOffset + off;
        firstLength = len;
      }
    }
    if (itemId == targetId && firstOffset != null) {
      return (firstOffset, firstLength);
    }
  }
  return null;
}

int _readU32(Uint8List b, int p) =>
    (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3];

int _readU64(Uint8List b, int p) {
  final hi = _readU32(b, p);
  final lo = _readU32(b, p + 4);
  return (hi << 32) | lo;
}

int _readN(Uint8List b, int p, int n) {
  var v = 0;
  for (var i = 0; i < n; i++) {
    v = (v << 8) | b[p + i];
  }
  return v;
}

// ---------------- TIFF ----------------

ExifResult _parseTiff(Uint8List t) {
  if (t.length < 8) return const ExifResult();
  final little = t[0] == 0x49 && t[1] == 0x49; // II
  final big = t[0] == 0x4D && t[1] == 0x4D; // MM
  if (!little && !big) return const ExifResult();

  int u16(int p) =>
      little ? (t[p] | (t[p + 1] << 8)) : ((t[p] << 8) | t[p + 1]);
  int u32(int p) => little
      ? (t[p] | (t[p + 1] << 8) | (t[p + 2] << 16) | (t[p + 3] << 24))
      : _readU32(t, p);

  final ifd0 = u32(4);
  // 没有 GPS IFD / 指针越界都**不能提前 return**：
  // 拍摄时间在后面的 Exif 子 IFD（0x8769），无 GPS 的照片也有 DateTimeOriginal。
  double? lat;
  double? lng;
  String latRef = 'N';
  String lngRef = 'E';
  DateTime? takenAt;

  final gpsPtr = _findTagValue(t, ifd0, 0x8825, u16, u32, little);
  if (gpsPtr != null && gpsPtr > 0 && gpsPtr < t.length) {
    for (final e in _readIfd(t, gpsPtr, u16, u32, little)) {
      if (e.tag == 0x0001) latRef = e.ascii(t, little);
      if (e.tag == 0x0003) lngRef = e.ascii(t, little);
      if (e.tag == 0x0002) lat = e.rationals(t, u32, little);
      if (e.tag == 0x0004) lng = e.rationals(t, u32, little);
    }
  }

  // 拍摄时间在 IFD0 的 Exif 子 IFD（0x8769）里
  final exifPtr = _findTagValue(t, ifd0, 0x8769, u16, u32, little);
  if (exifPtr != null && exifPtr > 0 && exifPtr < t.length) {
    for (final e in _readIfd(t, exifPtr, u16, u32, little)) {
      if (e.tag == 0x9003 || e.tag == 0x9004) {
        final s = e.ascii(t, little);
        takenAt = _parseDateTime(s);
        if (takenAt != null) break;
      }
    }
  }

  if (lat == null || lng == null) {
    return ExifResult(takenAt: takenAt);
  }
  if (latRef.toUpperCase().startsWith('S')) lat = -lat;
  if (lngRef.toUpperCase().startsWith('W')) lng = -lng;
  return ExifResult(lat: lat, lng: lng, takenAt: takenAt);
}

class _Entry {
  final int tag;
  final int type;
  final int count;
  final int valueOffset;
  const _Entry(this.tag, this.type, this.count, this.valueOffset);

  /// ASCII（type=2）
  String ascii(Uint8List t, bool little) {
    final n = count;
    final start = (n <= 4) ? valueOffset : _u32At(t, valueOffset, little);
    final end = (start + n).clamp(0, t.length);
    if (start < 0 || start >= t.length) return '';
    var s = String.fromCharCodes(t, start, end);
    final z = s.indexOf('\x00');
    if (z >= 0) s = s.substring(0, z);
    return s.trim();
  }

  /// RATIONAL（type=5）：count 个 8 字节
  double? rationals(Uint8List t, int Function(int) u32, bool little) {
    if (count < 1) return null;
    final start = (count * 8 <= 4) ? valueOffset : _u32At(t, valueOffset, little);
    if (start < 0 || start + 8 > t.length) return null;
    final num = u32(start);
    final den = u32(start + 4);
    if (den == 0) return null;
    final first = num / den;
    if (count >= 3) {
      if (start + 24 > t.length) return first;
      final n2 = u32(start + 8);
      final d2 = u32(start + 12);
      final n3 = u32(start + 16);
      final d3 = u32(start + 20);
      final m = d2 == 0 ? 0.0 : n2 / d2;
      final s = d3 == 0 ? 0.0 : n3 / d3;
      final deg = first + m / 60 + s / 3600;
      if (deg.isNaN || deg.isInfinite || deg.abs() < 0.0001) return null;
      return deg;
    }
    if (first.isNaN || first.isInfinite || first.abs() < 0.0001) return null;
    return first;
  }
}

int _u32At(Uint8List t, int p, bool little) {
  if (p + 4 > t.length) return 0;
  return little
      ? (t[p] | (t[p + 1] << 8) | (t[p + 2] << 16) | (t[p + 3] << 24))
      : _readU32(t, p);
}

List<_Entry> _readIfd(Uint8List t, int offset, int Function(int) u16,
    int Function(int) u32, bool little) {
  final out = <_Entry>[];
  if (offset + 2 > t.length) return out;
  final n = u16(offset);
  var p = offset + 2;
  for (var i = 0; i < n; i++) {
    if (p + 12 > t.length) break;
    final tag = u16(p);
    final type = u16(p + 2);
    final count = u32(p + 4);
    // value 字段：<=4 字节内联，>4 字节是偏移
    final valueOffset = p + 8;
    out.add(_Entry(tag, type, count, valueOffset));
    p += 12;
  }
  return out;
}

int? _findTagValue(Uint8List t, int ifdOffset, int targetTag,
    int Function(int) u16, int Function(int) u32, bool little) {
  final entries = _readIfd(t, ifdOffset, u16, u32, little);
  for (final e in entries) {
    if (e.tag == targetTag) {
      // 这些指针都是 LONG(4)，直接内联读
      return _u32At(t, e.valueOffset, little);
    }
  }
  return null;
}

/// EXIF 时间字符串 `2026:10:02 14:32:01` → `DateTime`。
///
/// 全项目**唯一**实现：原生 EXIF 与 Dart 兜底解析两条链路都调这里，
/// 不要在别处再写一份（之前 photo_processor 里就重复了一遍）。
DateTime? parseExifDateTime(String raw) {
  final s = raw.trim();
  if (s.length < 10) return null;
  final date = s.substring(0, 10).replaceAll(':', '-');
  final time = s.length >= 19 ? s.substring(11, 19) : '00:00:00';
  return DateTime.tryParse('$date $time');
}

DateTime? _parseDateTime(String raw) => parseExifDateTime(raw);
