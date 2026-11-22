import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 缩略图（技术方案 §6.2 红线：页面层禁止自建 Image + 占位，一律用这里）。
///
/// 加载中显示 panel2 底色；加载失败或 uri 不可用显示占位图标。
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({super.key, required this.uri, this.fit = BoxFit.cover});

  final String uri;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    // content:// 需经 ContentResolver 读取。阶段 C 导入时会把文件复制到私有目录，
    // 阶段 B 只读链路若遇到 content:// 先显示占位。
    if (uri.startsWith('content://')) {
      return const _ThumbPlaceholder();
    }
    return Container(
      color: panel2,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 按显示宽度解码（规格 §12）：否则相册大图整张解码会 OOM。
          final dpr = MediaQuery.of(context).devicePixelRatio;
          final w = constraints.maxWidth.isFinite && constraints.maxWidth > 0
              ? (constraints.maxWidth * dpr).round()
              : null;
          return Image.file(
            File(uri),
            fit: fit,
            cacheWidth: w,
            errorBuilder: (_, __, ___) => const _ThumbPlaceholder(),
          );
        },
      ),
    );
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: panel2,
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: t3, size: 20),
    );
  }
}
