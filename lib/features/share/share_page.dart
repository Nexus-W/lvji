import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_state.dart';
import '../../core/theme.dart';
import '../../data/models/photo.dart';
import '../../data/models/trip.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/photo_thumb.dart';
import '../../widgets/sheet_button.dart';

/// 分享九宫格（技术方案 §5.5）：3×3 拼图导出，1080×1080 PNG。
class SharePage extends StatefulWidget {
  const SharePage({super.key, required this.tripId});

  final String tripId;

  @override
  State<SharePage> createState() => _SharePageState();
}

class _SharePageState extends State<SharePage> {
  final _repaintKey = GlobalKey();
  Trip? _trip;
  final List<Photo> _picked = [];
  bool _dark = true;
  bool _showInfo = true;
  bool _pickerOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final appState = context.read<AppState>();
    final trip = await appState.tripRepo.find(widget.tripId);
    if (trip == null) {
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    if (mounted) setState(() => _trip = trip);
    await _seed();
  }

  Future<void> _seed() async {
    final repo = context.read<AppState>().photoRepo;
    final featured = await repo.featuredPhotos(widget.tripId);
    final picked = <Photo>[];
    final seen = <String>{};
    for (final p in featured) {
      if (picked.length >= 9) break;
      picked.add(p);
      seen.add(p.id);
    }
    if (picked.length < 9) {
      final all = await repo.allPhotos(widget.tripId);
      for (final p in all) {
        if (picked.length >= 9) break;
        if (seen.contains(p.id)) continue;
        picked.add(p);
      }
    }
    if (mounted) setState(() => _picked..clear()..addAll(picked));
  }

  void _togglePicked(Photo p) {
    setState(() {
      final idx = _picked.indexWhere((x) => x.id == p.id);
      if (idx >= 0) {
        _picked.removeAt(idx);
      } else {
        if (_picked.length >= 9) {
          _toast('最多 9 张');
          return;
        }
        _picked.add(p);
      }
    });
  }

  Future<void> _save() async {
    if (_picked.isEmpty) {
      _toast('先选几张');
      return;
    }
    try {
      final bytes = await _renderPng();
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/luji_share.png');
      await file.writeAsBytes(bytes);
      // ignore: deprecated_member_use
      await Share.shareXFiles([XFile(file.path)], text: '旅迹 · 精选九宫格');
    } catch (_) {
      _toast('分享失败');
    }
  }

  /// 渲染成固定 1080 宽的 PNG（分享与保存相册共用）。
  Future<Uint8List?> _renderPng() async {
    final boundary =
        _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final logical = boundary.size.width;
    final ratio = logical > 0 ? 1080 / logical : 3.0;
    final image = await boundary.toImage(pixelRatio: ratio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  /// 保存到系统相册（之前只能走系统分享面板，部分机型没有「保存」入口）。
  Future<void> _saveToGallery() async {
    if (_picked.isEmpty) {
      _toast('先选几张');
      return;
    }
    try {
      final bytes = await _renderPng();
      if (bytes == null) return;
      if (!await Gal.hasAccess()) {
        await Gal.requestAccess();
      }
      await Gal.putImageBytes(bytes, album: '旅迹');
      _toast('已保存到相册「旅迹」');
    } catch (e) {
      _toast('保存失败：$e');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    return AppScaffold(
      title: '分享精选',
      subtitle: '挑九张，拼成一张',
      onBack: () => Navigator.of(context).pop(),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    children: [
                      _buildCanvas(trip),
                      _pickRow(),
                      _ctrls(),
                    ],
                  ),
                ),
              ),
              _foot(),
            ],
          ),
          if (_pickerOpen) _buildPicker(),
        ],
      ),
    );
  }

  Widget _buildCanvas(Trip? trip) {
    final bg = _dark ? const Color(0xFF0B1218) : const Color(0xFFF2F1ED);
    final titleColor = _dark ? Colors.white : const Color(0xFF1A1A1C);
    final subColor =
        _dark ? Colors.white.withValues(alpha: .72) : const Color(0xFF6E6E73);
    final markColor =
        _dark ? Colors.white.withValues(alpha: .55) : const Color(0xFFB0B0B5);

    final range = trip != null
        ? '${trip.startDate.replaceAll('-', '.')} - ${trip.endDate.replaceAll('-', '.')}'
        : '';
    final days = trip != null
        ? (DateTime.parse(trip.endDate)
                    .difference(DateTime.parse(trip.startDate))
                    .inDays +
                1)
            .toString()
        : '';

    return RepaintBoundary(
      key: _repaintKey,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
                itemCount: 9,
                itemBuilder: (_, i) {
                  if (i < _picked.length) {
                    return PhotoThumb(uri: _picked[i].uri);
                  }
                  return Container(
                    color: _dark ? const Color(0xFF0E1720) : const Color(0xFFE8E7E2),
                    alignment: Alignment.center,
                    child: const Icon(Icons.add, color: Color(0xFF3A4A58), size: 22),
                  );
                },
              ),
              if (_showInfo)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 44, 14, 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: _dark
                              ? [
                                  Colors.transparent,
                                  const Color(0xFF04080C).withValues(alpha: .94),
                                ]
                              : [
                                  Colors.transparent,
                                  Colors.white.withValues(alpha: .97),
                                ],
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  trip?.name ?? '旅迹',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: titleColor),
                                ),
                                const SizedBox(height: 2),
                                Text('$range · $days 天',
                                    style: TextStyle(
                                        fontSize: 8.5, color: subColor)),
                              ],
                            ),
                          ),
                          Text('旅迹',
                              style: TextStyle(
                                  fontSize: 8,
                                  letterSpacing: .08,
                                  color: markColor)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pickRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 2),
      child: Row(
        children: [
          Text.rich(
            TextSpan(
              text: '已选 ',
              style: const TextStyle(fontSize: 11, color: t3),
              children: [
                TextSpan(
                  text: '${_picked.length}',
                  style: const TextStyle(
                      color: accent, fontWeight: FontWeight.w600),
                ),
                const TextSpan(text: ' / 9 张'),
              ],
            ),
          ),
          const Spacer(),
          _SmallBtn(label: '选照片', onTap: () => setState(() => _pickerOpen = true)),
        ],
      ),
    );
  }

  Widget _ctrls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
      child: Row(
        children: [
          _SmallChip(label: '深色', on: _dark, onTap: () => setState(() => _dark = true)),
          const SizedBox(width: 6),
          _SmallChip(label: '浅色', on: !_dark, onTap: () => setState(() => _dark = false)),
          const Spacer(),
          _SmallChip(
              label: '显示信息',
              on: _showInfo,
              onTap: () => setState(() => _showInfo = !_showInfo)),
        ],
      ),
    );
  }

  Widget _foot() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        color: panel,
        border: Border(top: BorderSide(color: line)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // 主按钮：真的存进系统相册
            Expanded(
              flex: 3,
              child: GestureDetector(
                onTap: _picked.isEmpty ? null : _saveToGallery,
                child: Container(
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(radiusBtn),
                  ),
                  child: Opacity(
                    opacity: _picked.isEmpty ? .45 : 1,
                    child: const Text(
                      '保存到相册',
                      style: TextStyle(
                          fontSize: fsBody,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF04170F)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // 次按钮：调系统分享面板
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: _picked.isEmpty ? null : _save,
                child: Container(
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radiusBtn),
                    border: Border.all(color: line),
                  ),
                  child: Opacity(
                    opacity: _picked.isEmpty ? .45 : 1,
                    child: const Text('分享',
                        style: TextStyle(fontSize: fsBody, color: t2)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPicker() {
    return _PhotoPicker(
      picked: _picked,
      currentTripId: widget.tripId,
      onToggle: _togglePicked,
      onClear: () => setState(() => _picked.clear()),
      onDone: () => setState(() => _pickerOpen = false),
    );
  }
}

/// 选片面板（全屏覆盖，跨行程混选，最多 9 张）。
class _PhotoPicker extends StatefulWidget {
  const _PhotoPicker({
    required this.picked,
    required this.currentTripId,
    required this.onToggle,
    required this.onClear,
    required this.onDone,
  });

  final List<Photo> picked;
  final String currentTripId;
  final ValueChanged<Photo> onToggle;
  final VoidCallback onClear;
  final VoidCallback onDone;

  @override
  State<_PhotoPicker> createState() => _PhotoPickerState();
}

class _PhotoPickerState extends State<_PhotoPicker> {
  late String _tripId;
  List<Photo> _pool = [];

  @override
  void initState() {
    super.initState();
    _tripId = widget.currentTripId;
    _loadPool();
  }

  Future<void> _loadPool() async {
    final photos =
        await context.read<AppState>().photoRepo.allPhotos(_tripId);
    if (mounted) setState(() => _pool = photos);
  }

  bool _isPicked(String id) => widget.picked.any((p) => p.id == id);

  int _orderOf(String id) {
    for (var i = 0; i < widget.picked.length; i++) {
      if (widget.picked[i].id == id) return i + 1;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final trips = context.watch<AppState>().trips;
    return Positioned.fill(
      child: Container(
        color: const Color(0xFF060A0E).withValues(alpha: .985),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: Row(
                  children: [
                    const Text('选择照片',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: t1)),
                    const Spacer(),
                    Text.rich(
                      TextSpan(
                        text: '已选 ',
                        style: const TextStyle(fontSize: 11, color: t3),
                        children: [
                          TextSpan(
                            text: '${widget.picked.length}',
                            style: const TextStyle(
                                color: accent, fontWeight: FontWeight.w600),
                          ),
                          const TextSpan(text: ' / 9'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final t in trips)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _tripId = t.id);
                            _loadPool();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 11),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _tripId == t.id
                                  ? accent.withValues(alpha: .08)
                                  : panel2,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: _tripId == t.id
                                      ? accent.withValues(alpha: .45)
                                      : line),
                            ),
                            child: Text(
                              t.id == widget.currentTripId ? '本次 · ${t.name}' : t.name,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: _tripId == t.id ? accent : t3),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _pool.isEmpty
                    ? const Center(
                        child: Text('这个行程还没有照片',
                            style: TextStyle(color: t3, fontSize: fsBody)),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                        ),
                        itemCount: _pool.length,
                        itemBuilder: (_, i) {
                          final p = _pool[i];
                          final on = _isPicked(p.id);
                          return GestureDetector(
                            onTap: () => widget.onToggle(p),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: PhotoThumb(uri: p.uri),
                                ),
                                if (on) ...[
                                  Positioned(
                                    right: 4,
                                    top: 4,
                                    child: Container(
                                      constraints: const BoxConstraints(minWidth: 17),
                                      height: 17,
                                      padding:
                                          const EdgeInsets.symmetric(horizontal: 4),
                                      decoration: BoxDecoration(
                                        color: accent,
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text('${_orderOf(p.id)}',
                                          style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF04170F))),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF04080C)
                                            .withValues(alpha: .55),
                                        border: Border.all(
                                            color: accent, width: 2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: line)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SheetButton(height: 40, 
                          label: '清空',
                          primary: false,
                          onTap: widget.onClear),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: SheetButton(height: 40, 
                          label: '完成',
                          primary: true,
                          onTap: widget.onDone),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  const _SmallBtn({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: .4)),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 11, color: accent)),
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  const _SmallChip(
      {required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? accent.withValues(alpha: .08) : panel2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: on ? accent.withValues(alpha: .45) : Colors.transparent),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 11, color: on ? accent : t3)),
      ),
    );
  }
}


