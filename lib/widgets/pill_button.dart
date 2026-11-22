import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 胶囊形强调按钮（绿字 + 半透明绿底）。
/// 用于「选择照片 / 去补位置 / 去导入」这类轻量主操作，
/// 原来 import_page 与 trip_map_page 各写了一份。
class PillButton extends StatelessWidget {
  const PillButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent.withValues(alpha: .45)),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: fsBody,
                color: accent,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}
