import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../data/models/day.dart';
import '../../data/models/photo.dart';
import '../../data/weather.dart';
import '../../data/models/trip.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/map_point.dart';
import '../../widgets/selection_bar.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/mini_route_map.dart';
import '../../widgets/photo_marks.dart';
import '../../widgets/photo_thumb.dart';
import '../../widgets/photo_viewer.dart';
import '../../widgets/segmented.dart';
import '../../widgets/trip_menu.dart';

/// 精选页 —— 1:1 还原原型 `timeline-page.html`：
/// 概览卡（小地图 + 统计）→ 手记 → 日期/地点切换 → 日期 chip → 优质照片展板。
class FeaturedPage extends StatefulWidget {
  const FeaturedPage({super.key, required this.tripId});

  final String tripId;

  @override
  State<FeaturedPage> createState() => _FeaturedPageState();
}

class _FeaturedPageState extends State<FeaturedPage> {
  Trip? _trip;
  List<Day> _days = [];
  Map<String, List<Photo>> _photosByDay = {};
  List<Photo> _ungrouped = [];
  List<Photo> _located = [];
  bool _loading = true;
  int _lastRev = -1;
  Map<String, DayWeather> _weather = const {};

  String _dim = 'day';
  String? _filter;
  final _sectionKeys = <String, GlobalKey>{};
  String? _activeKey;
  /// true = 显示全部照片；false = 只看精选
  bool _showAll = true;
  double? _activeLat;
  double? _activeLng;
  List<_Section> _sectionsCache = const [];
  final Set<String> _expanded = {};

  bool _selecting = false;
  final Set<String> _selected = {};

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
    final days = await appState.tripRepo.listDays(trip.id);

    // 一次查全部照片 + 内存分组（原来每个 day 查一次，30 天要 32 次往返）
    final allPhotos = await appState.photoRepo.allPhotos(trip.id);
    final dayIds = {for (final d in days) d.id};
    final byDay = <String, List<Photo>>{};
    final ungrouped = <Photo>[];
    final located = <Photo>[];
    for (final p in allPhotos) {
      final did = p.dayId;
      if (did != null && dayIds.contains(did)) {
        byDay.putIfAbsent(did, () => []).add(p);
      } else {
        ungrouped.add(p); // day_id 失效 → 时间未知，保证可见
      }
      if (p.lat != null && p.lng != null) located.add(p);
    }
    // 天气：整段行程一次拉取（失败返回空 map，不影响页面）
    var weather = <String, DayWeather>{};
    try {
      // 按天坐标取：跨城行程每天的城市不同，用整趟一个点会串味
      final dayCoords = await appState.tripRepo.dayLocations(trip.id);
      if (dayCoords.isNotEmpty) {
        weather = await appState.weather.forDays(
          tripId: trip.id,
          dayCoords: dayCoords,
        );
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _trip = trip;
      _days = days;
      _photosByDay = byDay;
      _ungrouped = ungrouped;
      _located = located;
      _weather = weather;
      _loading = false;
    });
  }

  bool _isFeatured(Photo p) =>
      p.isCover == 1 || p.isFeatured == 1 || p.note.isNotEmpty;

  int get _totalPhotos =>
      _days.fold<int>(0, (s, d) => s + (_photosByDay[d.id]?.length ?? 0)) +
      _ungrouped.length;

  /// 路线点：全部有坐标照片，按拍摄时间排序（同一天多张也能连成线）。
  List<MapPoint> _routePoints() {
    final all = <Photo>[];
    for (final d in _days) {
      all.addAll(_photosByDay[d.id] ?? []);
    }
    all.addAll(_ungrouped);
    all.sort((a, b) => (a.takenAt ?? '').compareTo(b.takenAt ?? ''));
    final pts = <MapPoint>[];
    for (final p in all) {
      if (p.lat != null && p.lng != null) {
        pts.add(MapPoint(id: p.id, lat: p.lat!, lng: p.lng!));
      }
    }
    return pts;
  }

  /// 箭头在第几个路线点上（随选中的日期或地点前后移动）。
  int _arrowIndex(List<MapPoint> route) {
    if (route.isEmpty || _filter == null) return 0;

    String? targetPhotoId;
    if (_dim == 'day') {
      for (final p in _photosByDay[_filter] ?? []) {
        if (p.lat != null && p.lng != null) {
          targetPhotoId = p.id;
          break;
        }
      }
    } else {
      // 地点维度：取该地点第一张有坐标的照片。
      for (final d in _days) {
        for (final p in _photosByDay[d.id] ?? []) {
          final place = (p.place?.isNotEmpty ?? false) ? p.place! : '未标注';
          if (place == _filter && p.lat != null && p.lng != null) {
            targetPhotoId = p.id;
            break;
          }
        }
        if (targetPhotoId != null) break;
      }
    }
    if (targetPhotoId == null) return 0;
    final idx = route.indexWhere((p) => p.id == targetPhotoId);
    return idx >= 0 ? idx : 0;
  }

  @override
  Widget build(BuildContext context) {
    // 数据版本号变了 → 重新加载（分组/chip 才会跟着位置变化更新）
    final rev = context.watch<AppState>().rev;
    if (rev != _lastRev) {
      _lastRev = rev;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
    if (_loading) {
      return const Scaffold(
        backgroundColor: bg,
        body: Center(child: CircularProgressIndicator(color: accent)),
      );
    }
    final trip = _trip!;
    final route = _routePoints();
    return AppScaffold(
      title: trip.name,
      subtitle:
          '${trip.startDate.replaceAll('-', '.')} - ${trip.endDate.substring(5).replaceAll('-', '.')} · ${_days.length} 天 · ${fmtNum(_totalPhotos)} 张',
      onBack: () => Navigator.of(context).pop(),
      actions: [
        HeaderIconButton(
          onTap: () => _showMenu(trip),
          child: const Icon(Icons.more_horiz, color: t2, size: 16),
        ),
      ],
      body: GestureDetector(
        // 点空白处退出备注编辑（收起光标）——规格外的体验修正。
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
          Column(
            children: [
              _OverviewCard(
                days: _days.length,
                photoCount: _totalPhotos,
                located: _located,
                route: route,
                arrowIndex: _arrowIndex(route),
                activeLat: _activeLat,
                activeLng: _activeLng,
                onTapMap: () => Navigator.of(context)
                    .pushNamed('/trip/map', arguments: trip.id),
              ),
              _NoteEditor(
                initial: trip.note,
                onSave: (v) async {
                  await context
                      .read<AppState>()
                      .tripRepo
                      .updateNote(trip.id, v);
                  await _load();
                },
              ),
              _HeaderSwitches(
                dim: _dim,
                showAll: _showAll,
                onDim: (d) => setState(() {
                  _dim = d;
                  _filter = null;
                }),
                onShowAll: (v) => setState(() => _showAll = v),
              ),
              _ChipBar(
                entries: _chips(),
                selected: _activeKey,
                onJump: _jumpTo,
              ),
              Expanded(child: _buildWall()),
            ],
          ),
          if (_selecting)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SelectionBar(
                count: _selected.length,
                onAll: _toggleAll,
                actions: [
                  SelectionAction('加精选', _addSelectedToFeatured),
                  SelectionAction('删除', _deleteSelected, isDanger: true),
                ],
                onCancel: _exitSelect,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 分组 / chip ----------------

  List<MapEntry<String, String>> _chips() {
    final list = <MapEntry<String, String>>[
      MapEntry('__all', '全部 ${_days.length} 天'),
    ];
    if (_dim == 'day') {
      for (final d in _days) {
        final n = _photosByDay[d.id]?.length ?? 0;
        if (n == 0) continue;
        // 日期 chip 也只显示日期（同一天可能去多个地点，地址放分组标题下方）。
        list.add(MapEntry(d.id, dayLabel(d.date)));
      }
    } else {
      // place → 该地点第一张照片（用来取坐标反查城市）
      final byPlace = <String, Photo>{};
      void add(Photo p) {
        final k = (p.place?.isNotEmpty ?? false) ? p.place! : '未标注';
        byPlace.putIfAbsent(k, () => p);
      }

      for (final d in _days) {
        (_photosByDay[d.id] ?? []).forEach(add);
      }
      _ungrouped.forEach(add);
      // 按「城市」去重：同一城市只出一个 chip（原来按景点出，同城多景点 → 多个同名 chip）。
      // key 仍保留该城市第一个景点的 place，点击时能正常跳到对应分组。
      final byCity = <String, MapEntry<String, String>>{};
      for (final e in byPlace.entries) {
        final city = cityOf(e.key, lat: e.value.lat, lng: e.value.lng);
        byCity.putIfAbsent(city, () => MapEntry(e.key, city));
      }
      list.addAll(byCity.values);
    }
    return list;
  }

  /// 点顶部时间/地点 chip → 滚到对应分组，并在 chip 下方显示小红箭头。
  void _jumpTo(String key) {
    // 「全部」不是真实分组：回到顶部即可，以前会走到下面「找不到分组」的分支弹提示
    if (key == '__all') {
      // 只切换高亮，不滚动（页面是 CustomScrollView，没有独立 controller；
      // 滚到顶部交给用户自己，避免误触时页面跳动）
      // _filter 必须跟着清空，否则小地图箭头还停在上一组的点位
      setState(() {
        _activeKey = key;
        _filter = null;
      });
      return;
    }
    // 关键：_filter 之前只有 `= null` 一种写法，从未被赋过具体分组，
    // 导致 _arrowIndex() 第一行就 return 0 —— 小地图红箭头永远停在第 1 个点。
    setState(() => _filter = key);
    // 小地图箭头 → 移到该分组第一张有坐标的照片
    for (final sec in _sectionsCache) {
      if (sec.key != key) continue;
      for (final p in sec.all) {
        if (p.lat != null &&
            p.lng != null &&
            !(p.lat!.abs() < 0.01 && p.lng!.abs() < 0.01)) {
          _activeLat = p.lat;
          _activeLng = p.lng;
          break;
        }
      }
      break;
    }
    // 分组没有坐标时静默跳过：分组本身是有效的，只是小地图箭头无处可指，
    // 弹「这个分组没有有效坐标」只会打扰（尤其「全部」分组）。
    setState(() => _activeKey = key);
    final ctx = _sectionKeys[key]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        alignment: 0.02,
      );
    }
  }

  Widget _buildWall() {
    final sections = _sections();
    // chip 现在是「跳转」而不是筛选：始终显示全部分组
    final filtered = sections;
    _sectionsCache = sections;
    // 默认高亮第一个（进来就能看到红三角）
    if (_activeKey == null && sections.isNotEmpty) {
      _activeKey = sections.first.key;
    }
    if (filtered.isEmpty) {
      final hasPhotos = _photosByDay.values.any((l) => l.isNotEmpty) ||
          _ungrouped.isNotEmpty;
      if (!hasPhotos) {
        // 刚建好的行程：提示去地图页导入（入口统一放在地图页）
        return const _ExEmpty(
          big: '这个行程还没有照片',
          small: '去「地图」页导入素材，开始记录这趟旅行。',
        );
      }
      return _ExEmpty(
        big: '还没有优质照片',
        small: '把喜欢的照片设为封面、加入精选或写一句备注，\n它们会集中出现在这里。',
        action: PillButton(
          label: '查看全部照片',
          onTap: () => Navigator.of(context)
              .pushNamed('/trip/map', arguments: widget.tripId),
        ),
      );
    }
    final showAddMore =
        filtered.fold<int>(0, (sum, s) => sum + s.featured.length) <= 1;
    // ListView.builder：只构建可见分组（原来 children: [...] 会把所有分组
    // 一次性建出来，分组一多首屏就卡）。
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: filtered.length + (showAddMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= filtered.length) {
          // 原型：优质照片只有 1 张时，追加「再加几张」提示卡。
          return Padding(
            padding: const EdgeInsets.fromLTRB(padPage, 8, padPage, 20),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: BoxDecoration(
                color: panel2,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Column(
                children: [
                  Text('再加几张',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: t2)),
                  SizedBox(height: 6),
                  Text(
                    '在地图页点开照片，可以设为封面、加入精选或写备注。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: fsBody, height: 1.9, color: t3),
                  ),
                ],
              ),
            ),
          );
        }

        final s = filtered[i];
        return _ExhibitSection(
          key: _sectionKeys.putIfAbsent(s.key, () => GlobalKey()),
          section: s,
          expanded: _expanded.contains(s.key),
          selecting: _selecting,
          selected: _selected,
          weather: _weather,
          onToggleExpand: () => setState(() {
            _expanded.contains(s.key)
                ? _expanded.remove(s.key)
                : _expanded.add(s.key);
          }),
          onTapPhoto: _openPhoto,
          onToggleSelect: (id) => setState(() {
            _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
          }),
          onLongPress: (id) => setState(() {
            _selecting = true;
            _selected
              ..clear()
              ..add(id);
          }),
        );
      },
    );
  }

  List<_Section> _sections() {
    final out = <_Section>[];
    if (_dim == 'day') {
      for (final d in _days) {
        final all = _photosByDay[d.id] ?? [];
        final featured =
            _showAll ? all : all.where(_isFeatured).toList();
        if (featured.isEmpty) continue;
        final places = <String>{};
        for (final p in all) {
          if (p.place != null && p.place!.isNotEmpty) places.add(p.place!);
        }
        out.add(_Section(
            key: d.id,
            date: d.date,
            title: dayLabel(d.date),
            places: places.toList(),
            all: all,
            featured: featured));
      }
      final uf =
          _showAll ? _ungrouped : _ungrouped.where(_isFeatured).toList();
      if (uf.isNotEmpty) {
        // 有 takenAt 却不在行程日期范围内 ≠ 没有时间，标题要如实区分
        final hasTime = _ungrouped.any((p) => p.takenAt != null);
        out.add(_Section(
            key: '__ungrouped',
            title: hasTime ? '未归入行程日期' : '时间未知',
            all: _ungrouped,
            featured: uf));
      }
    } else {
      final byPlace = <String, List<Photo>>{};
      void add(Photo p) {
        final k = (p.place?.isNotEmpty ?? false) ? p.place! : '未标注';
        byPlace.putIfAbsent(k, () => []).add(p);
      }

      for (final d in _days) {
        (_photosByDay[d.id] ?? []).forEach(add);
      }
      _ungrouped.forEach(add);
      byPlace.forEach((place, all) {
        final featured = _showAll ? all : all.where(_isFeatured).toList();
        if (featured.isEmpty) return;
        out.add(_Section(
            key: place,
            title: place,
            placeMode: true,
            all: all,
            featured: featured));
      });
    }
    return out;
  }

  // ---------------- 交互 ----------------

  Future<void> _openPhoto(List<Photo> photos, int index) async {
    await PhotoViewer.open(
      context,
      photos: photos,
      initialIndex: index,
      // dayId → 第几天：底部显示「第 3 天 · 12/47」
      dayNumbers: {
        for (var i = 0; i < _days.length; i++) _days[i].id: i + 1,
      },
    );
    if (mounted) await _load();
  }

  void _toggleAll() {
    final visible = _visibleIds();
    setState(() {
      if (_selected.containsAll(visible)) {
        _selected.removeAll(visible);
      } else {
        _selected.addAll(visible);
      }
    });
  }

  List<String> _visibleIds() {
    final ids = <String>[];
    for (final s in _sections()) {
      if (_filter != null && s.key != _filter) continue;
      ids.addAll((_expanded.contains(s.key) ? s.all : s.featured)
          .map((p) => p.id));
    }
    return ids;
  }

  void _exitSelect() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  /// 批量加入精选。
  Future<void> _addSelectedToFeatured() async {
    if (_selected.isEmpty) return;
    final repo = context.read<AppState>().photoRepo;
    for (final id in _selected) {
      await repo.setFeatured(id, true);
    }
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    await _load();
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final ok = await ConfirmDialog.show(
      context,
      title: '删除这 ${ids.length} 张照片？',
      desc: '只从这次行程里移除\n原图仍在系统相册',
      okText: '删除',
    );
    if (!ok || !mounted) return;
    await context.read<AppState>().photoRepo.softDelete(ids);
    _exitSelect();
    await _load();
  }

  Future<void> _showMenu(Trip trip) async {
    final action = await showTripMenu(context);
    if (action == null || !mounted) return;
    switch (action) {
      case 'share':
        Navigator.of(context).pushNamed('/share', arguments: trip.id);
      case 'rename':
        await showRenameTripSheet(context, trip);
        await _load();
      case 'dates':
        await showTripDatesSheet(context, trip);
        await _load();
      case 'delete':
        if (await confirmDeleteTrip(context, trip) && mounted) {
          Navigator.of(context).popUntil((r) => r.isFirst);
        }
    }
  }
}


class _Section {
  const _Section({
    required this.key,
    required this.title,
    this.date = '',
    this.placeMode = false,
    required this.all,
    required this.featured,
    this.places = const [],
  });

  final String key;
  final String title;

  /// YYYY-MM-DD（查天气用）；「时间未知」分组为空串。
  final String date;

  /// 地点模式：标题本身就是完整地址，照片不再按地点二次分组、也不显示天气。
  final bool placeMode;
  final List<Photo> all;
  final List<Photo> featured;

  /// 该天出现过的所有地点（去重）——标题只显示日期，地址放这行。
  final List<String> places;
}

// ---------------- 概览卡（原型 .ov） ----------------

class _OverviewCard extends StatelessWidget {
  /// 有坐标的照片 → 地图点（缩略路线图用）。
  List<MapPoint> _routePoints(List<Photo> photos) => [
        for (final p in photos)
          if (p.lat != null && p.lng != null)
            MapPoint(
              id: p.id,
              lat: p.lat!,
              lng: p.lng!,
              count: 1,
              label: p.place,
              thumbnail: p.uri,
              marks: {
                if (p.isCover == 1) 'gold',
                if (p.isFeatured == 1) 'green',
                if (p.note.isNotEmpty) 'violet',
              },
            ),
      ];

  const _OverviewCard({
    required this.days,
    required this.photoCount,
    required this.located,
    required this.onTapMap,
    this.route,
    this.arrowIndex,
    this.activeLat,
    this.activeLng,
  });

  final int days;
  final int photoCount;
  final List<Photo> located;
  final VoidCallback onTapMap;
  final List<MapPoint>? route;
  final double? activeLat;
  final double? activeLng;
  final int? arrowIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(padPage, 12, padPage, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: line.withValues(alpha: .7))),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onTapMap,
            child: Container(
              width: 96,
              height: 96,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: line),
                color: const Color(0xFF08131A),
              ),
              child: located.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(6),
                        child: Text('还没有位置信息\n先去补坐标',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: t3, fontSize: 9, height: 1.6)),
                      ),
                    )
                  : GestureDetector(
                      onTap: onTapMap,
                      // 自绘缩略图：自动 fit 行程范围，城市内几天也能看清路线
                      child: MiniRouteMap(
                        points: _routePoints(located),
                        activeLat: activeLat,
                        activeLng: activeLng,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                _stat('$days', '天'),
                _sep(),
                _stat('0', '公里'),
                _sep(),
                _stat(fmtNum(photoCount), '张'),
                _sep(),
                _stat('0', '视频'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: fsTitle,
                    fontWeight: FontWeight.w600,
                    color: t1,
                    letterSpacing: -.4)),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(fontSize: fsSubtitle, color: t3)),
          ],
        ),
      );

  Widget _sep() => Container(width: 1, height: 24, color: line);
}

// ---------------- 手记（原型 .jnote） ----------------

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({required this.initial, required this.onSave});

  final String initial;
  final ValueChanged<String> onSave;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final TextEditingController _ctrl;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
    _focus.addListener(() {
      if (!_focus.hasFocus) widget.onSave(_ctrl.text.trim());
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 底 8 与下方筛选栏顶 8 相加 = gapBlock(16)，和「筛选栏→chips」保持一致
      padding: const EdgeInsets.fromLTRB(padPage, 10, padPage, gapInner),
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        maxLines: 6,
        minLines: 2,
        style: const TextStyle(
            color: Color(0xFFB9C3D0), fontSize: fsBody, height: 1.8),
        decoration: InputDecoration(
          hintText: '这一趟发生了什么？写一句。',
          hintStyle: const TextStyle(
              color: Color(0xFF7C8796),
              fontSize: fsBody,
              fontStyle: FontStyle.italic),
          filled: true,
          fillColor: panel2,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: accent.withValues(alpha: .4)),
          ),
        ),
      ),
    );
  }
}

// ---------------- 日期 / 地点切换（原型 .dims） ----------------


// ---------------- 日期 chip（原型 .days） ----------------

/// 顶部两个筛选器：左边「日期 / 地点」，右边「精选 / 全部」。
///
/// 之前是两行独立控件，各占一整行、各带 16 边距，竖向浪费 ~40px。
/// 现在合成一行：左对齐 + 右对齐，左右边距与页面一致（padPage）。
class _HeaderSwitches extends StatelessWidget {
  const _HeaderSwitches({
    required this.dim,
    required this.showAll,
    required this.onDim,
    required this.onShowAll,
  });

  final String dim;
  final bool showAll;
  final ValueChanged<String> onDim;
  final ValueChanged<bool> onShowAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 上下都留 gapInner：与备忘底(8)、chips 顶(8)相加各得 16，视觉间距相等
      padding: const EdgeInsets.fromLTRB(padPage, gapInner, padPage, gapInner),
      child: Row(
        children: [
          Segmented(
            items: const [('day', '日期'), ('place', '地点')],
            selected: dim,
            onChanged: onDim,
            width: 128,
            height: 28,
          ),
          const Spacer(),
          Segmented(
            items: const [('featured', '精选'), ('all', '全部')],
            selected: showAll ? 'all' : 'featured',
            onChanged: (k) => onShowAll(k == 'all'),
            width: 108,
            height: 28,
            pill: true,
          ),
        ],
      ),
    );
  }
}

class _ChipBar extends StatelessWidget {
  const _ChipBar({
    required this.entries,
    required this.selected,
    required this.onJump,
  });

  final List<MapEntry<String, String>> entries;
  final String? selected;
  final ValueChanged<String> onJump;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: padPage, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: line.withValues(alpha: .7))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _Chip(
                  label: e.value,
                  on: selected == e.key,
                  showArrow: selected == e.key,
                  onTap: () => onJump(e.key),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.on,
    required this.onTap,
    this.showArrow = false,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
}


// ---------------- 展板分组（原型 datehead + .grid） ----------------

class _ExhibitSection extends StatelessWidget {
  /// 按地点分组（保持出现顺序）。
  Map<String, List<Photo>> _groupByPlace(List<Photo> photos) {
    final out = <String, List<Photo>>{};
    for (final p in photos) {
      final k = (p.place?.isNotEmpty ?? false) ? p.place! : '未标注';
      out.putIfAbsent(k, () => <Photo>[]).add(p);
    }
    return out;
  }

  final Map<String, DayWeather> weather;

  DayWeather? get _weatherHere {
    if (section.date.isEmpty) return null;
    return weather[section.date];
  }

  IconData _weatherIcon(DayWeather w) {
    if (w.isThunder) return Icons.thunderstorm_outlined;
    if (w.isSnow) return Icons.ac_unit;
    if (w.isRain) return Icons.water_drop_outlined;
    if (w.isFog) return Icons.foggy;
    if (w.isCloudy) return Icons.cloud_outlined;
    return Icons.wb_sunny_outlined;
  }

  const _ExhibitSection({
    super.key,
    required this.section,
    required this.expanded,
    required this.selecting,
    required this.selected,
    this.weather = const {},
    required this.onToggleExpand,
    required this.onTapPhoto,
    required this.onToggleSelect,
    required this.onLongPress,
  });

  final _Section section;
  final bool expanded;
  final bool selecting;
  final Set<String> selected;
  final VoidCallback onToggleExpand;
  final void Function(List<Photo>, int) onTapPhoto;
  final ValueChanged<String> onToggleSelect;
  final ValueChanged<String> onLongPress;

  @override
  Widget build(BuildContext context) {
    final photos = expanded ? section.all : section.featured;
    final canExpand = section.featured.length < section.all.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(padPage, 12, padPage, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      section.title,
                      // 地点模式的标题是完整地址，允许折两行；日期模式保持一行
                      maxLines: section.placeMode ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: fsBody,
                          fontWeight: FontWeight.w600,
                          color: accent),
                    ),
                  ),
                  if (!section.placeMode) ...[
                  const SizedBox(width: 6),
                  // 天气：温度在前、图标在后（无数据时显示占位）
                  Text(
                    _weatherHere == null
                        ? '—°'
                        : '${_weatherHere!.tmin.round()}/${_weatherHere!.tmax.round()}°',
                    style: const TextStyle(fontSize: 14, color: t3),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _weatherHere == null
                        ? Icons.wb_sunny_outlined
                        : _weatherIcon(_weatherHere!),
                    size: 15,
                    color: t2,
                  ),
                  ],
                  if (canExpand) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onToggleExpand,
                      child: Container(
                        height: 24,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: line),
                        ),
                        child: Text(expanded ? '收起' : '展开全部',
                            style: const TextStyle(fontSize: 9, color: t3)),
                      ),
                    ),
                  ],
                ],
              ),
              // 同一天可能去了多个地点：地址统一放标题下方，标题只留日期。
            ],
          ),
        ),
        // 日期模式：同一天按地点分段（城市 · N 张）；地点模式：标题已是地址，直接铺图
        for (final e in (section.placeMode
                ? {section.key: photos}
                : _groupByPlace(photos))
            .entries) ...[
          if (!section.placeMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
              child: Text(
                '${cityOf(e.key, lat: e.value.first.lat, lng: e.value.first.lng)} · ${e.value.length} 张',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: t3),
              ),
            ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: e.value.length,
            itemBuilder: (_, i) {
              final p = e.value[i];
              final isSel = selected.contains(p.id);
              return GestureDetector(
                onTap: () =>
                    selecting ? onToggleSelect(p.id) : onTapPhoto(e.value, i),
                onLongPress: () {
                  if (!selecting) onLongPress(p.id);
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PhotoThumb(uri: p.uri),
                    if (!selecting)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: PhotoMarks.fromPhoto(p),
                      ),
                    if (selecting)
                      Positioned(right: 5, top: 5, child: _Dot(on: isSel)),
                    if (selecting && isSel)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: accent, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: on ? accent : Colors.black.withValues(alpha: .4),
        shape: BoxShape.circle,
        border: Border.all(
            color: on ? accent : Colors.white.withValues(alpha: .9)),
      ),
      child: on
          ? const Icon(Icons.check, color: Color(0xFF04170F), size: 12)
          : null,
    );
  }
}

// ---------------- 空态（原型 .exempty） ----------------

class _ExEmpty extends StatelessWidget {
  const _ExEmpty({required this.big, required this.small, this.action});

  final String big;
  final String small;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(padPage, 8, padPage, 20),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          decoration: BoxDecoration(
            color: panel2,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Text(big,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t2)),
              const SizedBox(height: 6),
              Text(small,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: fsBody, height: 1.9, color: t3)),
              if (action != null) ...[
                const SizedBox(height: 16),
                action!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------- 选片条（原型 .selbar） ----------------


