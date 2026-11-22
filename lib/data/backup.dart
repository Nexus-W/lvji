import 'dart:io';


import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';

/// 数据备份：把 SQLite 数据库 + 私有目录下的照片一起打包成 zip，再调系统分享。
///
/// 为什么必须做：App 所有数据都在手机私有目录里，
/// 换机 / 误删 / 卸载都会永久丢失，导出是唯一的保命手段。
class BackupService {
  BackupService._();

  /// 打包并分享。返回生成的 zip 路径（失败抛异常，由调用方提示）。
  static Future<File> export({
    required String dbPath,
    required String photosDir,
    required Directory tempDir,
  }) async {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .substring(0, 15);
    final out = File(p.join(tempDir.path, 'luji-backup-$stamp.zip'));

    // 流式写：逐文件「读 → 压 → 写 → 释放」，内存占用与照片总量无关。
    // 之前把每个文件 readAsBytes 塞进 Archive，1000 张照片峰值 1~2GB，必 OOM。
    final encoder = ZipFileEncoder();
    encoder.create(out.path);
    try {
      // ① 数据库（行程、照片记录、手记、天气缓存全在里面）
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        await encoder.addFile(dbFile, 'luji.db');
      }

      // ② 照片副本（保留目录结构，恢复时按原路径写回）
      final dir = Directory(photosDir);
      if (await dir.exists()) {
        await for (final f in dir.list(recursive: true, followLinks: false)) {
          if (f is! File) continue;
          final rel = p.relative(f.path, from: photosDir);
          await encoder.addFile(f, 'photos/$rel');
        }
      }
    } finally {
      await encoder.close();
    }
    return out;
  }

  /// 打包后让用户自己选保存位置（原生 ACTION_CREATE_DOCUMENT）。
  /// 返回 true = 已保存，false = 用户取消。
  static Future<bool> exportToChosenFolder({
    required String dbPath,
    required String photosDir,
    required Directory tempDir,
  }) async {
    final out = await export(
      dbPath: dbPath,
      photosDir: photosDir,
      tempDir: tempDir,
    );
    // 传路径而不是 bytes：整个 zip 塞进 MethodChannel 会再占一份全量内存
    final uri = await const MethodChannel('luji/exif').invokeMethod<String>(
      'saveAs',
      {'path': out.path, 'name': p.basename(out.path)},
    );
    return uri != null;
  }

}

/// 恢复结果。
class RestoreResult {
  const RestoreResult({required this.photoFiles, required this.dbBytes});

  final int photoFiles;
  final int dbBytes;
}

/// 从备份 zip 恢复数据。
///
/// **前置条件**：调用方必须先关闭数据库连接（`AppState.closeDb()`），
/// 否则覆盖 `luji.db` 时 SQLite 还持有文件句柄。
///
/// 不做「合并」：备份是整库快照，合并会产生同 id 不同内容的分裂状态。
/// 恢复后必须重启进程，Flutter 侧的内存状态全是旧的。
class BackupRestore {
  BackupRestore._();

  static Future<RestoreResult> restore({
    required Uint8List zipBytes,
    required String dbPath,
    required String photosDir,
  }) async {
    final archive = ZipDecoder().decodeBytes(zipBytes, verify: false);

    // ① 校验：必须有 luji.db，否则不是本 App 的备份
    final dbEntry = archive.files
        .where((f) => f.isFile && f.name == 'luji.db')
        .cast<ArchiveFile?>()
        .firstWhere((f) => f != null, orElse: () => null);
    if (dbEntry == null) {
      throw '这个压缩包里没有 luji.db，不是旅迹的备份';
    }

    // ② 先落数据库（此时连接已关闭）
    final dbData = dbEntry.content as List<int>;
    await File(dbPath).writeAsBytes(dbData, flush: true);

    // ③ 再落照片：photos/ 下保留原目录结构
    final dir = Directory(photosDir);
    await dir.create(recursive: true);
    var count = 0;
    for (final f in archive.files) {
      if (!f.isFile || !f.name.startsWith('photos/')) continue;
      final rel = f.name.substring('photos/'.length);
      if (rel.isEmpty || rel.contains('..')) continue; // 防目录穿越
      final out = File(p.join(photosDir, rel));
      await out.parent.create(recursive: true);
      await out.writeAsBytes(f.content as List<int>, flush: true);
      count++;
    }

    return RestoreResult(photoFiles: count, dbBytes: dbData.length);
  }
}
