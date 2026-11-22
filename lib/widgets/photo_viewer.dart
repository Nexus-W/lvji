import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/extensions.dart';
import '../core/theme.dart';
import '../data/models/photo.dart';
import 'app_sheet.dart';
import 'confirm_dialog.dart';
import 'photo_info_sheet.dart';
import 'photo_marks.dart';
import 'sheet_button.dart';

/// 大图查看器（技术方案 附录A：lightbox.js 的 .lbx → 这里）。
///
/// 全屏查看、左右滑动切换，底部显示时间/地点 + 三色标记 + 操作
/// （修改 / 设为封面 / 加入精选 / 写备注）。删除在阶段 E 接入。
/// 返回 [Future]，调用方可 await 后刷新列表。
class PhotoViewer {
  const PhotoViewer._();

  static Future<void> open(
    BuildContext context, {
    required List<Photo> photos,
    required int initialIndex,
    /// dayId → 第几天（1 起）。用于底部显示「第 3 天 · 12/47」。
    Map<String, int>? dayNumbers,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PhotoViewerPage(
          photos: photos,
          initialIndex: initialIndex.clamp(0, photos.length - 1),
          dayNumbers: dayNumbers ?? const {},
        ),
      ),
    );
  }
}

class _PhotoViewerPage extends StatefulWidget {
  const _PhotoViewerPage({
    required this.photos,
    required this.initialIndex,
    this.dayNumbers = const {},
  });

  final Map<String, int> dayNumbers;

  final List<Photo> photos;
  final int initialIndex;

  @override
  State<_PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<_PhotoViewerPage> {
  late final PageController _controller;
  late final List<Photo> _photos;
  late int _index;

  /// 底部区域亮度缓存（photoId → 0~1），翻页时按需计算。
  final _lumCache = <String, double>{};
  double? _bottomLum;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _photos = List.of(widget.photos);
    _controller = PageController(initialPage: widget.initialIndex);
    _updateLum();
  }

  /// 采样当前照片底部亮度，决定备注文字用深色还是浅色。
  void _updateLum() {
    final p = _current;
    final cached = _lumCache[p.id];
    if (cached != null) {
      _bottomLum = cached;
      return;
    }
    _bottomLum = null;
    _bottomLuminance(p.uri).then((v) {
      _lumCache[p.id] = v;
      if (mounted && _current.id == p.id) {
        setState(() => _bottomLum = v);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Photo get _current => _photos[_index];

  Future<void> _refreshCurrent() async {
    final p = await context.read<AppState>().photoRepo.find(_current.id);
    if (p != null && mounted) {
      setState(() => _photos[_index] = p);
    }
  }

  Future<void> _toggleFeatured() async {
    final p = _current;
    final appState = context.read<AppState>();
    await appState.photoRepo.setFeatured(p.id, p.isFeatured != 1);
    await _refreshCurrent();
    // 精选标记不影响行程统计，用轻量通知即可（省掉 3 次全表查询）
    appState.bumpPhotos();
  }

  Future<void> _setCover() async {
    final appState = context.read<AppState>();
    await appState.photoRepo.setCover(_current.id);
    await _refreshCurrent();
    await appState.reload(); // 列表卡片封面缓存必须刷新，否则看不到效果
  }

  Future<void> _editNote() async {
    final p = _current;
    final note = await AppSheet.show<String>(
      context,
      child: _NoteSheet(initial: p.note),
    );
    if (note == null || !mounted) return;
    final repo = context.read<AppState>().photoRepo;
    await repo.updateNote(p.id, note);
    await _refreshCurrent();
  }

  Future<void> _editInfo() async {
    final updated =
        await PhotoInfoSheet.show(context, photo: _current);
    if (updated != null) {
      setState(() => _photos[_index] = updated);
    }
  }

  Future<void> _delete() async {
    final p = _current;
    final ok = await ConfirmDialog.show(
      context,
      title: '删除这张照片？',
      desc: '只从这次行程里移除\n原图仍在系统相册',
      okText: '删除',
    );
    if (!ok || !mounted) return;
    final repo = context.read<AppState>().photoRepo;
    await repo.softDelete([p.id]);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final photo = _current;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: _photos.length,
            onPageChanged: (i) {
              setState(() => _index = i);
              _updateLum();
            },
            itemBuilder: (_, i) {
              final p = _photos[i];
              return InteractiveViewer(
                child: Center(child: _FullImage(uri: p.uri)),
              );
            },
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 20),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_index + 1} / ${_photos.length}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: fsCaption),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 备注：底部渐变 + 最多两行，不挡照片主体，点一下进编辑。
                  if (photo.note.isNotEmpty)
                    _NoteBar(
                        note: photo.note,
                        onTap: _editNote,
                        luminance: _bottomLum),
                  _Actions(
                    photo: photo,
                    onEdit: _editInfo,
                    onCover: _setCover,
                    onFeatured: _toggleFeatured,
                    onNote: _editNote,
                    onDelete: _delete,
                  ),
                  _InfoBar(
                    photo: photo,
                    index: _photos.indexOf(photo),
                    total: _photos.length,
                    dayNumber: widget.dayNumbers[photo.dayId],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 采样照片底部 20% 区域的平均亮度（0 黑 → 1 白），用于备注文字选色。
Future<double> _bottomLuminance(String uri) async {
  try {
    final file = File(uri);
    if (!await file.exists()) return 0;
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 48);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return 0;
    final w = image.width;
    final h = image.height;
    final startY = (h * 0.8).floor();
    var sum = 0.0;
    var n = 0;
    for (var y = startY; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        final r = data.getUint8(i);
        final g = data.getUint8(i + 1);
        final b = data.getUint8(i + 2);
        sum += (0.299 * r + 0.587 * g + 0.114 * b) / 255;
        n++;
      }
    }
    image.dispose();
    return n == 0 ? 0 : sum / n;
  } catch (_) {
    return 0;
  }
}

/// 单张照片备注（大图底部）：不加底色，按底部背景亮度自动切文字颜色，
/// 深底用浅字、浅底用深字，并带同色系描边保证可读性。
class _NoteBar extends StatelessWidget {
  const _NoteBar({required this.note, required this.onTap, this.luminance});

  final String note;
  final VoidCallback onTap;

  /// 底部区域平均亮度（0 黑 → 1 白）；null 时按深底处理。
  final double? luminance;

  @override
  Widget build(BuildContext context) {
    final light = (luminance ?? 0) > 0.55;
    final color = light ? const Color(0xFF11161C) : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Text(
          note,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: fsBody,
            height: 1.55,
            shadows: [
              Shadow(
                color: light
                    ? Colors.white.withValues(alpha: .75)
                    : Colors.black.withValues(alpha: .75),
                blurRadius: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullImage extends StatelessWidget {
  const _FullImage({required this.uri});

  final String uri;

  @override
  Widget build(BuildContext context) {
    if (uri.startsWith('content://')) {
      return const Icon(Icons.image_outlined, color: t3, size: 48);
    }
    return Image.file(
      File(uri),
      errorBuilder: (_, __, ___) =>
          const Icon(Icons.broken_image_outlined, color: t3, size: 48),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.photo,
    required this.onEdit,
    required this.onCover,
    required this.onFeatured,
    required this.onNote,
    required this.onDelete,
  });

  final Photo photo;
  final VoidCallback onEdit;
  final VoidCallback onCover;
  final VoidCallback onFeatured;
  final VoidCallback onNote;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _action('修改', Icons.edit_outlined, onEdit),
          _action('封面', Icons.bookmark_outline, onCover,
              active: photo.isCover == 1, activeColor: gold),
          _action('精选', Icons.star_outline, onFeatured,
              active: photo.isFeatured == 1, activeColor: accent),
          _action('备注', Icons.sticky_note_2_outlined, onNote,
              active: photo.note.isNotEmpty, activeColor: violet),
          _action('删除', Icons.delete_outline, onDelete, color: danger),
        ],
      ),
    );
  }

  Widget _action(String label, IconData icon, VoidCallback onTap,
      {bool active = false, Color? activeColor, Color? color}) {
    final c = color ?? (active ? (activeColor ?? accent) : Colors.white70);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: c),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 9, color: c)),
          ],
        ),
      ),
    );
  }
}

class _InfoBar extends StatelessWidget {
  const _InfoBar({
    required this.photo,
    required this.index,
    required this.total,
    this.dayNumber,
  });

  final Photo photo;
  final int index;
  final int total;
  final int? dayNumber;

  @override
  Widget build(BuildContext context) {
    final taken = photo.takenAt != null
        ? ymdHm(DateTime.parse(photo.takenAt!))
        : '时间未知';
    final place = (photo.place?.isNotEmpty ?? false) ? photo.place! : '位置未知';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: .7),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(taken,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(color: t1, fontSize: fsBody)),
                    ),
                    const SizedBox(width: 8),
                    // 位置提示：不新增行，跟在时间右侧，弱化到 caption 级
                    Text(
                      '${dayNumber != null ? '第 $dayNumber 天 · ' : ''}'
                      '${index + 1}/$total',
                      style: const TextStyle(color: t3, fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(place,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: t2, fontSize: fsCaption)),
              ],
            ),
          ),
          PhotoMarks.fromPhoto(photo, size: 10),
        ],
      ),
    );
  }
}

class _NoteSheet extends StatefulWidget {
  const _NoteSheet({required this.initial});

  final String initial;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('写备注',
              style: TextStyle(
                  fontSize: fsCardTitle,
                  fontWeight: FontWeight.w600,
                  color: t1)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLength: 500,
            maxLines: 3,
            style: const TextStyle(color: t1, fontSize: fsBody),
            decoration: InputDecoration(
              hintText: '这张照片的故事…',
              hintStyle: const TextStyle(color: t3),
              counterStyle: const TextStyle(color: t3, fontSize: 9),
              filled: true,
              fillColor: panel,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(radiusTag + 2),
                borderSide: const BorderSide(color: line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(radiusTag + 2),
                borderSide: const BorderSide(color: line),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SheetButton(
                    label: '取消',
                    primary: false,
                    onTap: () => Navigator.of(context).pop()),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: SheetButton(
                    label: '保存',
                    primary: true,
                    onTap: () => Navigator.of(context).pop(_ctrl.text.trim())),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


