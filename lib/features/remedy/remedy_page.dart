import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/extensions.dart';
import '../../core/place_table.dart';
import '../../core/theme.dart';
import '../../data/geocoding.dart';
import '../../data/models/photo.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/photo_info_sheet.dart';
import '../../widgets/photo_thumb.dart';

/// 坐标补救页 —— 按原型 `remedy-page.html` 的版式：
/// 橙色提示卡 → 过滤 chip → 缺位置照片列表（缩略图 + 时间 + 地点 + 修改）→ 底部大按钮。
class RemedyPage extends StatefulWidget {
  const RemedyPage({super.key, this.tripId});

  /// 为空表示「所有行程」——主页提示条点进来就是这种。
  final String? tripId;

  @override
  State<RemedyPage> createState() => _RemedyPageState();
}

class _RemedyPageState extends State<RemedyPage> {
  List<Photo> _photos = [];
  bool _loading = true;
  bool _showAlert = true;
  String _filter = 'all'; // all / withTime / noTime
  // 多选：批量把多张照片设成同一时间/地点
  bool _selecting = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final appState = context.read<AppState>();
    final photos = await appState.photoRepo.photosMissingLocation(widget.tripId);
    if (!mounted) return;
    setState(() {
      _photos = photos;
      _loading = false;
    });
  }

  List<Photo> get _filtered {
    if (_filter == 'withTime') {
      return _photos.where((p) => p.takenAt != null).toList();
    }
    if (_filter == 'noTime') {
      return _photos.where((p) => p.takenAt == null).toList();
    }
    return _photos;
  }

  Future<void> _edit(Photo p) async {
    final updated = await PhotoInfoSheet.show(context, photo: p, focusMap: true);
    if (updated != null) await _load();
  }

  /// 批量设置：时间（可选）+ 地点，应用到所有选中照片。
  Future<void> _batchEdit() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    DateTime? when;
    final ctrl = TextEditingController();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: panel2,
      isScrollControlled: true,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('批量设置 ${ids.length} 张',
                  style: const TextStyle(
                      fontSize: fsCardTitle,
                      fontWeight: FontWeight.w600,
                      color: t1)),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Text('拍摄时间',
                      style: TextStyle(fontSize: fsBody, color: t3)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: when ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (d == null || !ctx.mounted) return;
                        final t = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay.now(),
                        );
                        setInner(() {
                          when = DateTime(d.year, d.month, d.day, t?.hour ?? 12,
                              t?.minute ?? 0);
                        });
                      },
                      child: Container(
                        height: 38,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: panel,
                          borderRadius: BorderRadius.circular(radiusTag + 1),
                          border: Border.all(color: line),
                        ),
                        child: Text(
                          when == null ? '保持原时间' : ymdHm(when!),
                          style: TextStyle(
                              fontSize: fsBody, color: when == null ? t3 : t1),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                style: const TextStyle(color: t1, fontSize: fsBody),
                decoration: InputDecoration(
                  hintText: '地点（留空则保持原地点）',
                  hintStyle: const TextStyle(color: t3, fontSize: fsBody),
                  filled: true,
                  fillColor: panel,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(radiusTag + 1),
                    borderSide: const BorderSide(color: line),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(false),
                      child: Container(
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(radiusBtn),
                          border: Border.all(color: line),
                        ),
                        child: const Text('取消',
                            style: TextStyle(fontSize: fsBody, color: t2)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(true),
                      child: Container(
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(radiusBtn),
                        ),
                        child: const Text('应用到全部',
                            style: TextStyle(
                                fontSize: fsBody,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0A0F14))),
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

    if (ok != true || !mounted) {
      // 提前返回也要释放，否则每批量操作一次泄漏一个 controller
      ctrl.dispose();
      return;
    }
    final repo = context.read<AppState>().photoRepo;
    final place = ctrl.text.trim();

    // 地名 → 坐标（只解析一次）：补位置页只保留「没有坐标」的照片，
    // 所以批量设置地点时必须同时写坐标，否则这些照片不会从列表消失。
    (double?, double?)? coords;
    if (place.isNotEmpty) {
      var c = placeToLatLng(place);
      if (c.$1 == null) {
        final remote = await Geocoding.forward(place);
        if (remote != null) c = (remote.$1, remote.$2);
      }
      coords = c;
    }

    ctrl.dispose();
    for (final id in ids) {
      if (when != null) await repo.setTakenAt(id, when);
      if (place.isNotEmpty) await repo.setPlace(id, place);
      if (coords != null && coords.$1 != null && coords.$2 != null) {
        await repo.setLocation(id, coords.$1, coords.$2);
      }
    }
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    await _load();
    // 同步刷新全局「缺少位置」计数（主页卡片上的数字）
    if (mounted) await context.read<AppState>().reload();
  }


  @override
  Widget build(BuildContext context) {
    final withTime = _photos.where((p) => p.takenAt != null).length;
    final noTime = _photos.length - withTime;
    return AppScaffold(
      title: '坐标补救',
      subtitle: _loading ? '—' : '${_photos.length} 张缺位置',
      onBack: () => Navigator.of(context).pop(),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: accent))
          : Column(
              children: [
                if (_showAlert && _photos.isNotEmpty)
                  _AlertCard(onClose: () => setState(() => _showAlert = false)),
                _chips(withTime, noTime),
                Expanded(child: _list()),
              ],
            ),
      bottomNavigationBar:
          _loading || _photos.isEmpty ? null : _foot(),
    );
  }

  Widget _chips(int withTime, int noTime) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: line.withValues(alpha: .7))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _chip('全部 ${_photos.length}', 'all'),
            const SizedBox(width: 8),
            _chip('有时间 $withTime', 'withTime'),
            const SizedBox(width: 8),
            _chip('时间未知 $noTime', 'noTime'),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String key) {
    final on = _filter == key;
    return GestureDetector(
      onTap: () => setState(() => _filter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? t1 : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? t1 : line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: fsBody,
            color: on ? const Color(0xFF0A0F14) : t2,
            fontWeight: on ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _list() {
    final list = _filtered;
    if (list.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('没有缺位置的照片',
              style: TextStyle(color: t3, fontSize: fsBody)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: list.length,
      separatorBuilder: (_, __) => Divider(
          height: 1, color: line.withValues(alpha: .55)),
      itemBuilder: (_, i) {
        final p = list[i];
        final isSel = _selected.contains(p.id);
        return GestureDetector(
          onTap: _selecting
              ? () => setState(() {
                    isSel ? _selected.remove(p.id) : _selected.add(p.id);
                    if (_selected.isEmpty) _selecting = false;
                  })
              : null,
          onLongPress: () {
            if (!_selecting) {
              setState(() {
                _selecting = true;
                _selected.add(p.id);
              });
            }
          },
          child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              if (_selecting) ...[
                Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSel ? accent : Colors.transparent,
                    border: Border.all(color: isSel ? accent : line),
                  ),
                  child: isSel
                      ? const Icon(Icons.check,
                          size: 12, color: Color(0xFF0A0F14))
                      : null,
                ),
              ],
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: PhotoThumb(uri: p.uri),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.takenAt != null
                          ? ymdHm(DateTime.parse(p.takenAt!))
                          : '时间未知',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: fsBody, color: t1),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      (p.place?.isNotEmpty ?? false) ? p.place! : '位置未知',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: fsCaption, color: t3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _edit(p),
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: accent.withValues(alpha: .4)),
                  ),
                  child: const Text('修改',
                      style: TextStyle(fontSize: fsBody, color: accent)),
                ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }

  Widget _foot() {
    if (_selecting) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        decoration: const BoxDecoration(
          color: panel,
          border: Border(top: BorderSide(color: line)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _selecting = false;
                    _selected.clear();
                  }),
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radiusBtn),
                      border: Border.all(color: line),
                    ),
                    child: const Text('取消',
                        style: TextStyle(fontSize: fsBody, color: t2)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 全选/取消全选（与地图页、精选页的行为保持一致）
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    final all = _filtered.map((p) => p.id).toSet();
                    if (_selected.length == all.length) {
                      _selected.clear();
                    } else {
                      _selected
                        ..clear()
                        ..addAll(all);
                    }
                  }),
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radiusBtn),
                      border: Border.all(color: line),
                    ),
                    child: Text(
                      _selected.length == _filtered.length &&
                              _filtered.isNotEmpty
                          ? '取消全选'
                          : '全选',
                      style: const TextStyle(fontSize: fsBody, color: t2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: _selected.isEmpty ? null : _batchEdit,
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(radiusBtn),
                    ),
                    child: Opacity(
                      opacity: _selected.isEmpty ? .45 : 1,
                      child: Text(
                        '批量设置时间/地点（${_selected.length}）',
                        style: const TextStyle(
                            fontSize: fsBody,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0A0F14)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final list = _filtered;
    final canStart = list.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(
        color: panel,
        border: Border(top: BorderSide(color: line)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: canStart ? () => _edit(list.first) : null,
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(radiusBtn),
                ),
                child: Opacity(
                  opacity: canStart ? 1 : .45,
                  child: Text(
                    '逐张补位置（${list.length}）',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF04170F)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text('补好位置的照片会自动从队列移除',
                style: TextStyle(fontSize: 9, color: t3)),
          ],
        ),
      ),
    );
  }
}

/// 橙色提示卡（原型 .warn / .alert）。
class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.onClose});

  final VoidCallback onClose;


  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: gold.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gold.withValues(alpha: .3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber_rounded, size: 18, color: gold),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('这些照片缺少位置信息',
                    style: TextStyle(
                        fontSize: fsBody,
                        fontWeight: FontWeight.w600,
                        color: gold)),
                SizedBox(height: 4),
                Text('点「修改」逐张补，或在地图上点选位置。',
                    style: TextStyle(fontSize: fsCaption, color: t3)),
              ],
            ),
          ),
          GestureDetector(
            onTap: onClose,
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.close, size: 16, color: t3),
            ),
          ),
        ],
      ),
    );
  }
}
