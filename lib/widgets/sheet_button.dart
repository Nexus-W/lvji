import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 底部弹层的「取消 / 确认」类按钮（原来 import / trips / photo_viewer /
/// photo_info_sheet / trip_menu 五处各写了一份完全相同的实现，现统一到这里）。
class SheetButton extends StatelessWidget {
  const SheetButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.height = 38,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final double height;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(radiusBtn),
          border: primary ? null : Border.all(color: line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: fsBody,
            fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
            color: primary ? const Color(0xFF04170F) : t2,
          ),
        ),
      ),
    );
  }
}
