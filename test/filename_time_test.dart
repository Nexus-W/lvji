import 'package:flutter_test/flutter_test.dart';

import 'package:luji/core/filename_time.dart';

void main() {
  group('文件名兜底解析拍摄时间', () {
    test('微信图片', () {
      expect(timeFromFileName('微信图片_20261029203600.jpg'),
          DateTime(2026, 10, 29, 20, 36, 00));
    });

    test('微信导出（Unix 毫秒）', () {
      final t = timeFromFileName('mmexport1698567890123.jpg');
      expect(t, isNotNull);
      expect(t!.year, 2023);
    });

    test('截图（Screenshot_2026-10-31-11-58-47）', () {
      expect(timeFromFileName('Screenshot_2026-10-31-11-58-47.png'),
          DateTime(2026, 10, 31, 11, 58, 47));
    });

    test('相机 IMG_ 命名', () {
      expect(timeFromFileName('IMG_20261029_203600.jpg'),
          DateTime(2026, 10, 29, 20, 36, 00));
    });

    test('纯数字命名', () {
      expect(timeFromFileName('20261029_203600.jpg'),
          DateTime(2026, 10, 29, 20, 36, 00));
    });

    test('pic_ 前缀 / 无扩展名（微信保存的图）', () {
      expect(timeFromFileName('pic_20261028142142_0.jpg'),
          DateTime(2026, 10, 28, 14, 21, 42));
      expect(timeFromFileName('/storage/emulated/0/Pictures/WeiXin/pic_20261028142142_0'),
          DateTime(2026, 10, 28, 14, 21, 42));
    });

    test('解析不出来就返回 null（绝不瞎猜）', () {
      expect(timeFromFileName('IMG_0001.jpg'), isNull);
      expect(timeFromFileName('微信图片.jpg'), isNull);
      expect(timeFromFileName(''), isNull);
    });

    test('非法日期不采纳', () {
      expect(timeFromFileName('20261340_256099.jpg'), isNull);
    });
  });
}
