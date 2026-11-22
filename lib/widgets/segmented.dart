import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 分段控件（苹果 HIG 的 Segmented Control）：灰底 + 滑块位移。
///
/// 之前精选页的「日期 / 地点」是两个纯文字按钮 + 一条竖线，
/// 点了只有文字变色，看不出「我还在同一组选项里」。
/// 这里给选中项一块会滑动的底，用位移表达空间关系。
///
/// 圆角：轨道 10（胶囊模式取高度一半），滑块 7，
/// 都留了内边距，不会出现直角矩形。
class Segmented extends StatelessWidget {
  const Segmented({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.width = 132,
    this.height = 30,
    this.pill = false,
  });

  /// `(key, label)`
  final List<(String, String)> items;
  final String selected;
  final ValueChanged<String> onChanged;
  final double width;
  final double height;

  /// true = 胶囊形（用于「精选 / 全部」），false = 圆角矩形（用于「日期 / 地点」）
  final bool pill;

  @override
  Widget build(BuildContext context) {
    const pad = 3.0;
    final radius = pill ? height / 2 : 10.0;
    final segW = (width - pad * 2) / items.length;
    final idx =
        items.indexWhere((e) => e.$1 == selected).clamp(0, items.length - 1);

    // 尊重系统的「减少动态效果」
    final animate = !MediaQuery.of(context).disableAnimations;

    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: line, width: .5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(pad),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: animate
                    ? const Duration(milliseconds: 260)
                    : Duration.zero,
                // 苹果分段控件的滑块曲线
                curve: const Cubic(.32, .72, 0, 1),
                left: idx * segW,
                top: 0,
                bottom: 0,
                width: segW,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: raised,
                    borderRadius:
                        BorderRadius.circular(pill ? height / 2 - pad : 7),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final e in items)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(e.$1),
                        child: Center(
                          child: Text(
                            e.$2,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: fsBody,
                              height: 1,
                              color: e.$1 == selected ? t1 : t3,
                              fontWeight: e.$1 == selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
