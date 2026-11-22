import 'package:flutter_test/flutter_test.dart';

import 'package:luji/features/import/photo_processor.dart';

void main() {
  group('dmsToDecimal（GPS 度分秒 → 十进制）', () {
    test('整数度', () {
      expect(dmsToDecimal('30/1, 0/1, 0/1'), 30.0);
    });

    test('度分秒', () {
      // 40 + 26/60 + 7.71/3600 ≈ 40.43548
      expect(dmsToDecimal('40/1, 26/1, 771/100'), closeTo(40.43548, 0.0001));
    });

    test('负数度（南纬/西经由调用方处理符号）', () {
      expect(dmsToDecimal('10/1, 30/1, 0/1'), closeTo(10.5, 0.0001));
    });
  });

  group('parseExifDateTime（EXIF 时间字符串）', () {
    test('标准格式', () {
      expect(parseExifDateTime('2026:10:02 14:32:01'),
          DateTime(2026, 10, 2, 14, 32, 1));
    });

    test('缺少时间部分补零', () {
      expect(parseExifDateTime('2026:10:02'), DateTime(2026, 10, 2));
    });

    test('空字符串返回 null', () {
      expect(parseExifDateTime(''), isNull);
    });
  });
}
