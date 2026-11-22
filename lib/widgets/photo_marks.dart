import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models/photo.dart';

/// 三色标记（技术方案 §7.1 语义固定：金=封面 / 绿=精选 / 紫=备注）。
///
/// 时间轴、地图、大图三处共用，保证语义一致（§9 验收项）。
class PhotoMarks extends StatelessWidget {
  const PhotoMarks({
    super.key,
    required this.isCover,
    required this.isFeatured,
    required this.hasNote,
    this.size = 8,
  });

  factory PhotoMarks.fromPhoto(Photo p, {double size = 8}) => PhotoMarks(
        isCover: p.isCover == 1,
        isFeatured: p.isFeatured == 1,
        hasNote: p.note.isNotEmpty,
        size: size,
      );

  final bool isCover;
  final bool isFeatured;
  final bool hasNote;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dots = <Widget>[
      if (isCover) _dot(gold),
      if (isFeatured) _dot(accent),
      if (hasNote) _dot(violet),
    ];
    if (dots.isEmpty) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: dots);
  }

  Widget _dot(Color color) => Container(
        width: size,
        height: size,
        margin: EdgeInsets.only(right: size / 2),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .55), blurRadius: 1)],
        ),
      );
}
