import 'package:flutter_test/flutter_test.dart';

import 'package:luji/data/models/day.dart';
import 'package:luji/data/repository.dart';

void main() {
  const d02 = Day(id: 'd02', tripId: 't', date: '2026-10-02', sort: 0);
  const d03 = Day(id: 'd03', tripId: 't', date: '2026-10-03', sort: 1);
  final days = [d02, d03];

  test('T17 无时间 → 未分组', () {
    expect(pickDayId(null, days), isNull);
  });

  test('T18 凌晨归前一天（4 点是分界）', () {
    // 注：验收标准原文第一例写「2026-10-02 03:59」，但 §4.4 规则是
    // hour<4 减一天，10-02 03:59 应归 10-01（不在列表 → null），与
    // 「返回 10-02」的断言矛盾，判断为笔误。此处按规则意图用 10-03 03:59。
    expect(pickDayId(DateTime(2026, 10, 3, 3, 59), days), 'd02');
    expect(pickDayId(DateTime(2026, 10, 2, 4, 0), days), 'd02');
  });

  test('T19 行程范围外 → 未分组', () {
    expect(pickDayId(DateTime(2026, 9, 20, 12, 0), days), isNull);
  });
}
