import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 地图页的通用小控件（从 trip_map_page 抽出，纯无状态）。
///
/// 先抽这些零风险的 UI 原子，状态机（抽屉/多选）仍留在页面里，
/// 避免一次性重写引入回归。
class TripPill extends StatelessWidget {
  const TripPill({super.key, required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        constraints: const BoxConstraints(maxWidth: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF080E12).withValues(alpha: .86),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t1)),
            ),
            const SizedBox(width: 4),
            const Text('▾', style: TextStyle(fontSize: 10, color: t2)),
          ],
        ),
      ),
    );
  }
}

class SmallBtn extends StatelessWidget {
  const SmallBtn(
      {super.key,
      required this.label,
      required this.width,
      required this.onTap});

  final String label;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        width: width,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF080E12).withValues(alpha: .86),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 12, color: t1)),
      ),
    );
  }
}

/// 右侧方按钮（+ / − / ›）：36×36，圆角 10。
class SquareBtn extends StatelessWidget {
  const SquareBtn({super.key, required this.icon, required this.onTap});

  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF080E12).withValues(alpha: .86),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Text(icon,
            style: const TextStyle(fontSize: 16, color: t1, height: 1)),
      ),
    );
  }
}

/// 提示条（规格 §6）：居中、高 30、圆角 15。
class HintBar extends StatelessWidget {
  const HintBar({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF080E12).withValues(alpha: .9),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: Color(0xFF8C97A9))),
    );
  }
}

/// 拖拽条（规格 §7.1）：全宽 24，中间 40×4 圆角 2。
class GrabZone extends StatelessWidget {
  const GrabZone({super.key, 
    required this.onDrag,
    required this.onRelease,
    required this.onTap,
  });

  final ValueChanged<double> onDrag;
  final VoidCallback onRelease;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
      onVerticalDragEnd: (_) => onRelease(),
      onTap: onTap,
      child: Container(
        height: 24,
        decoration: const BoxDecoration(color: panel),
        child: Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF2A3441),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部 tab（规格 §8）：图标 20 + 文字 10sp。
