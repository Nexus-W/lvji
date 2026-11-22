import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../../core/coord_transform.dart';
import '../../core/exif_reader.dart';
import '../../core/filename_time.dart';
import '../../data/models/import_item.dart';

// 时间解析统一走 core/exif_reader.dart；这里 re-export，
// 保持既有 import 路径不变（测试引用本文件）。
export '../../core/exif_reader.dart' show parseExifDateTime;

/// 处理一批照片的结果。
class ProcessResult {
  final List<ImportItem> items;
  final int failed; // 读取失败（文件损坏/无权限）的张数

  const ProcessResult({required this.items, required this.failed});
}

/// 原生 EXIF 通道（Android `ExifInterface`，支持 HEIC）。
const _exifChannel = MethodChannel('luji/exif');

/// 逐张处理照片：原生 EXIF → Dart EXIF 兜底 → 转码降采样 → 落盘。
///
/// **刻意不用 Isolate**：原生 EXIF 与图片转码都是 MethodChannel，
/// 必须在主 isolate 调用。每张几百毫秒，几十张完全可接受，换来的是
/// HEIC 也能读到 GPS（之前 Dart 的 `exif` 包对 HEIC 完全无解）。
Future<ProcessResult> processPhotos(
  List<(String path, double? lat, double? lng, String sourceName)> picked,
  String importDir, {
  required void Function(int done, int total) onProgress,
}) async {
  final items = <ImportItem>[];
  var failed = 0;
  for (var i = 0; i < picked.length; i++) {
    try {
      items.add(await _processOne(
          picked[i].$1, picked[i].$2, picked[i].$3, importDir,
          sourceName: picked[i].$4));
    } catch (_) {
      failed++;
    }
    onProgress(i + 1, picked.length);
  }
  return ProcessResult(items: items, failed: failed);
}

/// 调 Android 原生读 EXIF；非 Android 或失败时返回 null（走 Dart 兜底）。
Future<Map<String, dynamic>?> _nativeExif(String path) async {
  if (!Platform.isAndroid) return null;
  try {
    final r = await _exifChannel.invokeMethod<Map>('read', {'path': path});
    if (r == null) return null;
    return r.map((k, v) => MapEntry(k.toString(), v));
  } catch (_) {
    return null;
  }
}

Future<ImportItem> _processOne(
    String path, double? mediaLat, double? mediaLng, String importDir,
    {String sourceName = ''}) async {
  var bytes = await File(path).readAsBytes();
  // 诊断：确认拿到的是原图还是被转码的副本（看文件头魔数）
  final magic = bytes.length >= 4
      ? bytes.take(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join()
      : '';
  // ignore: avoid_print
  print('[Exif] path=$path len=${bytes.length} magic=$magic');
  // hash 必须基于原文件：转码后的 JPEG 每次编码字节都不同，
  // 用转码结果会导致同一张照片被反复新增（还会保留旧的脏地名）。
  final originalBytes = bytes;

  // ① MediaStore 坐标（系统库写入的，跨机型最稳；相机照片通常为空）
  double? lat = mediaLat;
  double? lng = mediaLng;
  DateTime? takenAt;
  var width = 0;
  var height = 0;
  if (lat != null && lng != null) {
    // ignore: avoid_print
    print('[Exif] 用 MediaStore 坐标 lat=$lat lng=$lng');
  }

  // ② 原生 EXIF（HEIC 也能读）
  final native = lat == null ? await _nativeExif(path) : null;
  if (native != null) {
    final nLat = (native['lat'] as num?)?.toDouble();
    final nLng = (native['lng'] as num?)?.toDouble();
    // 关键：ExifInterface 在 HEIC 上可能返回 true 但填 (0,0)（数组默认值），
    // 这种值必须丢弃，否则会覆盖掉 Dart 侧能读到的真实坐标。
    if (nLat != null &&
        nLng != null &&
        !(nLat.abs() < 0.01 && nLng.abs() < 0.01) &&
        nLat.abs() <= 90 &&
        nLng.abs() <= 180) {
      lat = nLat;
      lng = nLng;
    }
    final t = native['takenAt'] as String?;
    if (t != null) takenAt = parseExifDateTime(t);
    width = (native['width'] as num?)?.toInt() ?? 0;
    height = (native['height'] as num?)?.toInt() ?? 0;
    // ignore: avoid_print
    print('[Exif] native lat=${native['lat']} lng=${native['lng']} '
        'takenAt=$takenAt w=$width');
  } else {
    // ignore: avoid_print
    print('[Exif] native 返回 null（通道不可用或文件读不到）');
  }

  // ② 自写解析器（不依赖 exif 包：它在 release/AOT 下会把坐标解成 0/1）
  if (lat == null || takenAt == null) {
    final r = readExif(bytes);
    lat ??= r.lat;
    lng ??= r.lng;
    takenAt ??= r.takenAt;
    // ignore: avoid_print
    print('[Exif] 自写解析 lat=$lat lng=$lng takenAt=$takenAt');
  }

  // ②b 仍没有时间 → 从文件名兜底（微信/QQ 传图会剥 EXIF，但文件名常带时间）
  if (takenAt == null) {
    // 优先用原始文件名：path 是临时文件 pm_<id>.img，里面没有日期。
    final fromName = timeFromFileName(
        sourceName.isNotEmpty ? sourceName : path);
    if (fromName != null) {
      takenAt = fromName;
      // ignore: avoid_print
      print('[Exif] 时间取自文件名: $takenAt');
    }
  }

  // ③ 转码降采样：HEIC/超大图 → JPEG（长边 2048），防 OOM
  try {
    final lower = path.toLowerCase();
    final need = lower.endsWith('.heic') ||
        lower.endsWith('.heif') ||
        bytes.length > 6 * 1024 * 1024;
    if (need) {
      final c = await FlutterImageCompress.compressWithList(
        bytes,
        format: CompressFormat.jpeg,
        quality: 92,
        minWidth: 2048,
        minHeight: 2048,
      );
      if (c.isNotEmpty) bytes = c;
    }
  } catch (_) {}

  final hash = sha1.convert(originalBytes).toString();
  final dest = '$importDir/$hash';
  if (!await File(dest).exists()) {
    await File(dest).writeAsBytes(bytes);
  }

  // 过滤伪坐标：(0,0) 会落到非洲西海岸，越界值一律视为「没有位置」。
  if (lat != null &&
      lng != null &&
      !(lat.abs() < 0.01 && lng.abs() < 0.01) &&
      lat.abs() <= 90 &&
      lng.abs() <= 180) {
    // 坐标统一 WGS-84 → GCJ-02（数据库只存 GCJ-02）
    final (gcjLat, gcjLng) = CoordTransform.wgs84ToGcj02(lat, lng);
    lat = gcjLat;
    lng = gcjLng;
  } else {
    lat = null;
    lng = null;
  }

  return ImportItem(
    uri: dest,
    hash: hash,
    takenAt: takenAt,
    lat: lat,
    lng: lng,
    width: width,
    height: height,
  );
}






/// '40/1, 26/1, 771/100' → 40.43475。公开供测试。
double dmsToDecimal(String raw) {
  final parts = raw.split(',');
  double result = 0;
  for (var i = 0; i < parts.length && i < 3; i++) {
    final frac = parts[i].trim().split('/');
    final num = double.tryParse(frac[0]) ?? 0;
    final den = frac.length > 1 ? (double.tryParse(frac[1]) ?? 1) : 1;
    final val = den == 0 ? 0 : num / den;
    result += val / (i == 0 ? 1 : (i == 1 ? 60 : 3600));
  }
  return result;
}

