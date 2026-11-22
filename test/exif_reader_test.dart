import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luji/core/exif_reader.dart';

void main() {
  // 示例照片放在仓库外的临时位置，不在代码里托管。
  // 找不到就跳过，而不是让整个测试套红 —— 否则换台机器/清过目录就误报。
  final jpgPath = Platform.environment['LUJI_TEST_JPG'] ?? 'test/fixtures/sample.jpg';
  final heicPath = Platform.environment['LUJI_TEST_HEIC'] ?? 'test/fixtures/sample.heic';

  test('手写解析：JPEG 原图', () {
    if (!File(jpgPath).existsSync()) {
      markTestSkipped('缺少示例照片 $jpgPath');
      return;
    }
    final b = File(jpgPath).readAsBytesSync();
    final r = readExif(b);
    // ignore: avoid_print
    print('JPG  lat=${r.lat} lng=${r.lng} takenAt=${r.takenAt}');
    expect(r.lat, isNotNull);
    expect(r.lat!, closeTo(31.12, 0.05));
    expect(r.lng!, closeTo(104.40, 0.05));
  });

  test('手写解析：HEIC 原图', () {
    if (!File(heicPath).existsSync()) {
      markTestSkipped('缺少示例照片 $heicPath');
      return;
    }
    final b = File(heicPath).readAsBytesSync();
    final r = readExif(b);
    // ignore: avoid_print
    print('HEIC lat=${r.lat} lng=${r.lng} takenAt=${r.takenAt}');
    expect(r.lat, isNotNull);
    expect(r.lat!, closeTo(31.12, 0.05));
    expect(r.lng!, closeTo(104.40, 0.05));
  });
}
