import 'package:flutter_test/flutter_test.dart';
import 'package:luji/core/extensions.dart';

void main() {
  test('城市级：区名在前也不被切错（北山杭州市）', () {
    expect(cityOf('西湖区北山杭州市'), '杭州市');
  });

  test('城市级：有市名直接用', () {
    expect(cityOf('四川省成都市锦江区东大街'), '成都市');
  });

  test('城市级：无市名用坐标反查', () {
    // 重庆两江新区
    expect(cityOf('两江新区华宇北国风光南(北滨一路)', lat: 29.60, lng: 106.50),
        '重庆市');
  });

  test('市区级：补上市名', () {
    expect(
        districtOf('旌阳区玉泉桂冠景城(屏山街东)', lat: 31.13, lng: 104.40),
        '德阳市旌阳区');
  });

  test('市区级：已有市名', () {
    expect(districtOf('四川省成都市锦江区东大街'), '成都市锦江区');
  });
}
