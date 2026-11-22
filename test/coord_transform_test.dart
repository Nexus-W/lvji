import 'package:flutter_test/flutter_test.dart';
import 'package:luji/core/coord_transform.dart';

void main() {
  group('CoordTransform', () {
    test('国内 WGS-84 → GCJ-02 会偏移（几百米级）', () {
      // 天安门 WGS-84 约 (39.9087, 116.3975)
      final (lat, lng) = CoordTransform.wgs84ToGcj02(39.9087, 116.3975);
      final dLat = (lat - 39.9087).abs();
      final dLng = (lng - 116.3975).abs();
      // 纬度约 +0.001~0.003，经度约 +0.004~0.008
      expect(dLat, greaterThan(0.001));
      expect(dLng, greaterThan(0.004));
    });

    test('境外不做偏移', () {
      final (lat, lng) = CoordTransform.wgs84ToGcj02(48.8566, 2.3522); // 巴黎
      expect(lat, 48.8566);
      expect(lng, 2.3522);
    });

    test('正向 + 反解 往返误差 < 1 米', () {
      final (gLat, gLng) = CoordTransform.wgs84ToGcj02(30.57, 104.07); // 成都
      final (wLat, wLng) = CoordTransform.gcj02ToWgs84(gLat, gLng);
      expect((wLat - 30.57).abs(), lessThan(0.00001));
      expect((wLng - 104.07).abs(), lessThan(0.00001));
    });
  });
}
