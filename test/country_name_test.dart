import 'package:flutter_test/flutter_test.dart';

import 'package:luji/core/country_index.dart';

void main() {
  group('国家名映射（地图点亮必须用数据原名）', () {
    test('中文显示名 → 数据原名', () {
      // world_countries.json 里是 Indonesia / Thailand，界面上是中文
      expect(CountryIndex.rawOf('印度尼西亚'), 'Indonesia');
      expect(CountryIndex.rawOf('泰国'), 'Thailand');
      expect(CountryIndex.rawOf('日本'), 'Japan');
    });

    test('数据本身就是中文的，原样返回', () {
      // 中国在 json 里就是「中国」，不能映射成 China（会匹配不到多边形）
      expect(CountryIndex.rawOf('中国'), '中国');
    });

    test('未知名字原样返回，不崩', () {
      expect(CountryIndex.rawOf('瓦坎达'), '瓦坎达');
    });
  });
}
