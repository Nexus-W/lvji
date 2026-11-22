import 'package:flutter_test/flutter_test.dart';
import 'package:luji/core/country_index.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await CountryIndex.ensureLoaded();
  });

  test('中国坐标判为中国', () {
    expect(CountryIndex.countryOf(30.57, 104.07), '中国');
    expect(CountryIndex.countryOf(39.90, 116.41), '中国');
  });

  test('泰国坐标判为泰国', () {
    expect(CountryIndex.countryOf(13.75, 100.50), '泰国');     // 曼谷
    // 普吉岛：数据源是低精度轮廓，小岛不在多边形内。宁可返回 null（归入
    // 「未知」）也不要用 bbox 兜底判成邻国。
    final phuket = CountryIndex.countryOf(7.88, 98.39);
    expect(phuket == null || phuket == '泰国', isTrue);
  });

  test('波兰坐标判为波兰', () {
    expect(CountryIndex.countryOf(49.62, 21.90), '波兰');      // Krosno
    expect(CountryIndex.countryOf(52.23, 21.01), '波兰');      // 华沙
  });

  test('地名前缀识别国家', () {
    expect(CountryIndex.byPlace('泰国普吉府直辖县'), '泰国');
    expect(CountryIndex.byPlace('波兰喀尔巴阡山省Krosno'), '波兰');
    expect(CountryIndex.byPlace('日本东京都新宿区'), '日本');
    expect(CountryIndex.byPlace('Thailand Phuket'), '泰国');
    // 中国地名通常不带「中国」前缀，应该返回 null，交给坐标判定
    expect(CountryIndex.byPlace('四川省德阳市'), isNull);
    expect(CountryIndex.byPlace(''), isNull);
  });

  test('地名前缀 → 数据原名（地图点亮用）', () {
    expect(CountryIndex.byPlaceRaw('泰国普吉府直辖县'), 'Thailand');
    expect(CountryIndex.byPlaceRaw('波兰喀尔巴阡山省Krosno'), 'Poland');
    expect(CountryIndex.byPlaceRaw('四川省德阳市'), isNull);
  });

  test('海上坐标返回 null', () {
    expect(CountryIndex.countryOf(0, -160), isNull);
  });
}
