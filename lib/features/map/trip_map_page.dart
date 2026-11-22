import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/route_observer.dart';
import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../data/models/day.dart';
import '../../data/models/photo.dart';
import '../../data/weather.dart';
import '../../data/models/trip.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/map_controls.dart';
import '../../widgets/selection_bar.dart';
import '../../widgets/map_point.dart';
import '../../widgets/photo_marks.dart';
import '../../widgets/photo_thumb.dart';
import '../../widgets/photo_viewer.dart';
import '../../widgets/real_bubble_map.dart';
import '../../widgets/pill_button.dart';

/// 行程地图页 —— 严格按《页面规格-行程地图》实现五个垂直区域：
/// ② 地图区 46% → ③ 拖拽条 24 → ④ 抽屉（按天网格）→ ⑤ 底部导航 56+安全区。
class TripMapPage extends StatefulWidget {
  const TripMapPage({super.key, required this.tripId});

  final String tripId;

  @override
  State<TripMapPage> createState() => _TripMapPageState();
}

class _TripMapPageState extends State<TripMapPage>
    with SingleTickerProviderStateMixin, RouteAware {
  final _scrollCtrl = ScrollController();
  final _sheetKey = GlobalKey();
  final _sectionKeys = <String, GlobalKey>{};

  Trip? _trip;
  List<Day> _days = [];
  Map<String, List<Photo>> _photosByDay = {};
  List<Photo> _ungrouped = [];
  List<Photo> _located = [];
  // 整个行程的全部照片（按时间排序）：大图模式左右滑动的范围
  List<Photo> _allPhotos = [];
  bool _loading = true;
  // 当前页面是否在最上层（被 push 盖住时移除地图，避免 PlatformView 遮挡）
  bool _routeVisible = true;
  int _lastRev = -1;
  Map<String, DayWeather> _weather = const {};

  double _mapH = 0;
  double _h = 0; // H = 屏高 − 状态栏 − 底部导航
  late final AnimationController _snapCtrl;
  double _snapFrom = 0;
  double _snapTarget = 0;

  String? _hint;
  Timer? _hintTimer;
  bool _firstHintShown = false;
  Timer? _scrollDebounce;

  String? _highlightPlace;

  bool _selecting = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200))
      ..addListener(() {
        setState(() {
          _mapH = _snapFrom +
              (_snapTarget - _snapFrom) *
                  Curves.easeOut.transform(_snapCtrl.value);
        });
      });
    _scrollCtrl.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _hintTimer?.cancel();
    _scrollDebounce?.cancel();
    _snapCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final appState = context.read<AppState>();
    final trip = await appState.tripRepo.find(widget.tripId);
    if (trip == null) {
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    final days = await appState.tripRepo.listDays(trip.id);

    // 一次查全部照片，在内存里分组。
    // 之前是「每个 day 查一次」（30 天 = 34 次数据库往返），
    // 现在固定 1 次查询，进页面/返回都明显更快。
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
        // day_id 为空、或指向已删除的天 → 归「时间未知」，保证一定可见
        ungrouped.add(p);
      }
      if (p.lat != null && p.lng != null) located.add(p);
    }

    located.sort((a, b) => (a.takenAt ?? '').compareTo(b.takenAt ?? ''));
    final all = <Photo>[
      for (final d in days) ...(byDay[d.id] ?? const <Photo>[]),
      ...ungrouped,
    ]..sort((a, b) => (a.takenAt ?? '').compareTo(b.takenAt ?? ''));

    // 天气：整段行程一次拉取（失败静默，标题只显示日期和城市）
    var weather = <String, DayWeather>{};
    try {
      final dayCoords =
          await appState.tripRepo.dayLocations(widget.tripId);
      if (dayCoords.isNotEmpty) {
        weather = await appState.weather.forDays(
          tripId: widget.tripId,
          dayCoords: dayCoords,
        );
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _allPhotos = all;
      _trip = trip;
      _days = days;
      _photosByDay = byDay;
      _ungrouped = ungrouped;
      _located = located;
      _weather = weather;
      _loading = false;
    });
    if (!_firstHintShown) {
      _firstHintShown = true;
      _showHint('滚动下方时间轴，地图会跟着走', 4000);
    }
  }

  // ---------------- 提示条 ----------------

  void _showHint(String text, int ms) {
    _hintTimer?.cancel();
    setState(() => _hint = text);
    _hintTimer = Timer(Duration(milliseconds: ms), () {
      if (mounted) setState(() => _hint = null);
    });
  }

  // ---------------- 抽屉 / 联动 ----------------

  String? _dayPlace(List<Photo> photos) {
    for (final p in photos) {
      if (p.place != null && p.place!.isNotEmpty) return p.place;
    }
    return null;
  }

  String _sectionKey(String dayId) => dayId;

  void _onScroll() {
    if (_scrollCtrl.position.pixels <= 0) return;
    _scrollDebounce?.cancel();
    _scrollDebounce =
        Timer(const Duration(milliseconds: 120), _detectCurrentDay);
  }

  void _detectCurrentDay() {
    if (!mounted) return;
    final sheetCtx = _sheetKey.currentContext;
    if (sheetCtx == null) return;
    final sheetBox = sheetCtx.findRenderObject() as RenderBox?;
    if (sheetBox == null) return;
    final sheetTop = sheetBox.localToGlobal(Offset.zero).dy;

    String? bestKey;
    var bestDist = double.infinity;
    for (final d in _days) {
      final key = _sectionKeys[_sectionKey(d.id)];
      final ctx = key?.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final dist = (top - sheetTop).abs();
      if (dist < bestDist) {
        bestDist = dist;
        bestKey = _sectionKey(d.id);
      }
    }
    if (bestKey == null) return;
    final day = _days.firstWhere((d) => d.id == bestKey);
    final place = _dayPlace(_photosByDay[day.id] ?? []);
    if (place != null && place != _highlightPlace) {
      setState(() => _highlightPlace = place);
      _showHint('${dayLabel(day.date)} · 地图已跟随', 1500);
    }
  }

  void _scrollToDay(String place) {
    // 找「包含这个地点照片」的第一天 —— 不再要求它必须是该天的首个地点
    // （同一天可能去多个地方，之前点后面的地点会找不到）。
    for (final d in _days) {
      final list = _photosByDay[d.id] ?? [];
      final hit = list.any((p) => (p.place ?? '').trim() == place);
      if (!hit) continue;
      final ctx = _sectionKeys[_sectionKey(d.id)]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0,
        );
      }
      setState(() => _highlightPlace = place);
      return;
    }
  }


  // ---------------- 地图控件 ----------------

  void _snapTo(double target) {
    _snapFrom = _mapH;
    _snapTarget = target;
    _snapCtrl.forward(from: 0);
  }

  Future<void> _openPhoto(List<Photo> photos, int index) async {
    await PhotoViewer.open(
      context,
      photos: photos,
      initialIndex: index,
      dayNumbers: {
        for (var i = 0; i < _days.length; i++) _days[i].id: i + 1,
      },
    );
    if (mounted) await _load();
  }

  Future<void> _showTripPicker(Trip current) async {
    final trips = context.read<AppState>().trips;
    final picked = await AppSheet.show<Trip>(
      context,
      child: _TripPickerSheet(trips: trips, currentId: current.id),
    );
    if (picked == null || picked.id == current.id || !mounted) return;
    Navigator.of(context)
        .pushReplacementNamed('/trip/map', arguments: picked.id);
  }

  // ---------------- 选中模式 ----------------

  void _enterSelect(String id) {
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..add(id);
      _mapH = _h * .30;
    });
  }

  void _exitSelect() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _addToFeatured() async {
    if (_selected.isEmpty) return;
    final repo = context.read<AppState>().photoRepo;
    for (final id in _selected) {
      await repo.setFeatured(id, true);
    }
    _exitSelect();
    await _load();
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final ok = await ConfirmDialog.show(
      context,
      title: '删除这 ${_selected.length} 张照片？',
      desc: '只从这次行程里移除\n原图仍在系统相册',
      okText: '删除',
    );
    if (!ok || !mounted) return;
    await context.read<AppState>().photoRepo.softDelete(_selected.toList());
    _exitSelect();
    await _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) routeObserver.subscribe(this, route);
  }

  @override
  void didPushNext() {
    if (mounted) setState(() => _routeVisible = false);
  }

  @override
  void didPopNext() {
    if (!mounted) return;
    setState(() => _routeVisible = true);
    // 从导入/补位置/精选返回时数据可能已变，必须重新查一次，
    // 否则抽屉停在上次的空列表（用户看到「导入成功但看不见」）。
    _load();
  }

  @override
  Widget build(BuildContext context) {
    // 数据版本号变了（补完位置/改完地点）→ 重新加载，地图 pin 和抽屉才会更新
    final rev = context.watch<AppState>().rev;
    if (rev != _lastRev) {
      _lastRev = rev;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
    if (!_routeVisible) {
      // 被别的页面盖住：直接不渲染地图（PlatformView 必须销毁）
      return const Scaffold(backgroundColor: bg);
    }
    if (_loading) {
      // 骨架屏（规格 §7.5）：4 列 × 3 行灰块，不带闪烁动画。
      return Scaffold(
        backgroundColor: const Color(0xFF07100F),
        body: Column(
          children: [
            const Expanded(child: SizedBox.shrink()),
            Container(height: 24, color: panel),
            Container(
              color: panel,
              padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
                itemCount: 12,
                itemBuilder: (_, __) =>
                    Container(color: const Color(0xFF1A2028)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      );
    }
    final trip = _trip!;
    final media = MediaQuery.of(context);
    final topPad = media.padding.top;
    final bottomPad = media.padding.bottom;
    const navH = 56.0;
    final h = media.size.height - topPad - navH - bottomPad;
    if (_h == 0) _h = h;
    if (_mapH == 0) _mapH = h * .46;
    final mapH = _mapH.clamp(h * .10, h * .88);

    return Scaffold(
      backgroundColor: const Color(0xFF07100F),
      body: Column(
        children: [
          // ② 地图区
          SizedBox(
            height: mapH,
            child: Stack(
              children: [
                Positioned.fill(
                  child: RealBubbleMap(
                    points: [
                      for (final p in _located)
                        if (p.lat != null && p.lng != null)
                          MapPoint(
                              id: p.id,
                              lat: p.lat!,
                              lng: p.lng!,
                              label: p.place,
                              thumbnail: p.uri),
                    ],
                    onClusterTap: (label) => _scrollToDay(label),
                    onPointTap: (id) {
                      final p = _located.firstWhere((x) => x.id == id);
                      if (p.place != null) _scrollToDay(p.place!);
                    },
                  ),
                ),
                // 顶部：行程胶囊 + 复位（避让状态栏）
                Positioned(
                  top: topPad + 8,
                  left: 12,
                  child: TripPill(
                    name: trip.name,
                    onTap: () => _showTripPicker(trip),
                  ),
                ),
                Positioned(
                  top: topPad + 8,
                  right: 12,
                  child: Row(
                    children: [
                      // 导入入口常驻地图页顶部（不再只藏在抽屉空态里）
                      SmallBtn(
                        label: '导入',
                        width: 52,
                        onTap: () async {
                          // 必须带上当前行程：否则导入页会默认选「列表第一个」，
// 照片就进了别的行程，当前行程里什么都看不到。
                          await Navigator.of(context)
                              .pushNamed('/import', arguments: widget.tripId);
                          if (mounted) await _load();
                        },
                      ),
                    ],
                  ),
                ),
                // 提示条（在控件下方，不压标签）
                if (_hint != null)
                  Positioned(
                    top: topPad + 56,
                    left: 24,
                    right: 24,
                    child: Center(child: HintBar(text: _hint!)),
                  ),
                // 右侧：+/−/›（锚定抽屉顶 −12）
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Column(
                    children: [
                      SquareBtn(
                          icon: '+',
                          onTap: () {}),
                      const SizedBox(height: 10),
                      SquareBtn(
                          icon: '−',
                          onTap: () {}),
                      const SizedBox(height: 10),
                      SquareBtn(
                        icon: '›',
                        onTap: () => Navigator.of(context)
                            .pushNamed('/trip/featured', arguments: trip.id),
                      ),
                    ],
                  ),
                ),
                // 全部无坐标（规格 §10）：地图中央提示 + 去补位置
                if (_located.isEmpty)
                  Align(
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                            _allPhotos.isEmpty
                                ? '这个行程还没有照片'
                                : '这些照片没有位置信息',
                            style: const TextStyle(color: t3, fontSize: fsBody)),
                        const SizedBox(height: 8),
                        PillButton(
                          label: '去补位置',
                          onTap: () async {
                            await Navigator.of(context).pushNamed(
                                '/trip/remedy',
                                arguments: trip.id);
                            if (mounted) await _load();
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // ③ 拖拽条
          GrabZone(
            onDrag: (dy) {
              if (_snapCtrl.isAnimating) _snapCtrl.stop();
              setState(() => _mapH = (_mapH + dy).clamp(h * .10, h * .88));
            },
            onRelease: () {
              final targets = [h * .10, h * .46, h * .88];
              var best = targets.first;
              for (final v in targets) {
                if ((v - _mapH).abs() < (best - _mapH).abs()) best = v;
              }
              _snapTo(best);
            },
            onTap: () => _snapTo(_mapH > h * .46 ? h * .10 : h * .88),
          ),
          // ④ 抽屉
          Expanded(child: _sheet()),
        ],
      ),
      // ⑤ 底部导航（2 tab）
      bottomNavigationBar: _selecting
          ? null
          : Container(
              height: navH + bottomPad,
              padding: EdgeInsets.only(bottom: bottomPad),
              decoration: const BoxDecoration(
                color: panel,
                border: Border(top: BorderSide(color: line)),
              ),
              child: Row(
                children: [
                  _NavTab(
                      icon: Icons.grid_view_outlined,
                      label: '行程',
                      active: false,
                      onTap: () => Navigator.of(context).pop()),
                  _NavTab(
                      icon: Icons.map_outlined,
                      label: '地图',
                      active: true,
                      onTap: () {}),
                ],
              ),
            ),
    );
  }

  Widget _sheet() {
    return Container(
      key: _sheetKey,
      decoration: const BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Column(
        children: [
          if (_selecting)
            SelectionBar(
              count: _selected.length,
              onAll: () => setState(() {
                _selected
                  ..clear()
                  ..addAll(_allPhotos.map((p) => p.id));
              }),
              actions: [
                SelectionAction('加精选', _addToFeatured),
                SelectionAction('删除', _deleteSelected, isDanger: true),
              ],
              onCancel: _exitSelect,
            ),
          Expanded(
            child: _photosByDay.isEmpty && _ungrouped.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _allPhotos.isEmpty
                              ? '还没有照片，先导入一些'
                              : '共 ${_allPhotos.length} 张照片（分组异常，正在重新加载）',
                          style: const TextStyle(color: t3, fontSize: fsBody),
                        ),
                        const SizedBox(height: 12),
                        PillButton(
                          label: '去导入',
                          onTap: () async {
                            // 必须带上当前行程：否则导入页会默认选「列表第一个」，
// 照片就进了别的行程，当前行程里什么都看不到。
                          await Navigator.of(context)
                              .pushNamed('/import', arguments: widget.tripId);
                            if (mounted) await _load();
                          },
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: _days.length + (_ungrouped.isEmpty ? 0 : 1),
                    itemBuilder: (_, i) {
                      if (i < _days.length) {
                        final d = _days[i];
                        final list = _photosByDay[d.id] ?? [];
                        // 没有导入照片的日期不显示。
                        if (list.isEmpty) return const SizedBox.shrink();
                        return _section(
                          key: _sectionKey(d.id),
                          weather: _weather[d.date],
                          // 只传日期：城市由 _section 内部的 _dayCities 算，
                          // 之前这里已经把长地址拼进 title，导致标题一直是「10月28日 · 两江新区…」
                          title: dayLabel(d.date),
                          photos: list,
                        );
                      }
                      return _section(
                        key: '__ungrouped',
                        title: _ungrouped.any((p) => p.takenAt != null)
                            ? '未归入行程日期'
                            : '时间未知',
                        photos: _ungrouped,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String key,
    required String title,
    required List<Photo> photos,
    DayWeather? weather,
  }) {
    final gk = _sectionKeys.putIfAbsent(key, () => GlobalKey());

    // 同一天里按地点再分组：每个地点一个小标题 + 一组图片
    final byPlace = <String, List<Photo>>{};
    for (final p in photos) {
      final place = (p.place == null || p.place!.trim().isEmpty)
          ? '未标注地点'
          : p.place!.trim();
      byPlace.putIfAbsent(place, () => []).add(p);
    }
    // 每个地点内按拍摄时间升序
    for (final list in byPlace.values) {
      list.sort((a, b) => (a.takenAt ?? '').compareTo(b.takenAt ?? ''));
    }
    // 地点之间也按时间排序（第一张照片的时间）
    final orderedPlaces = byPlace.entries.toList()
      ..sort((a, b) => (a.value.first.takenAt ?? '')
          .compareTo(b.value.first.takenAt ?? ''));

    return Column(
      key: gk,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 日期标题行高 36
        SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                      photos.isEmpty
                          ? title
                          : '$title · ${_dayCities(photos)}'
                              '${weather == null ? '' : ' · ${weather.tmin.round()}/${weather.tmax.round()}° ${weather.label}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: t1)),
                ),
                Text('${photos.length} 张',
                    style: const TextStyle(fontSize: 10, color: t3)),
              ],
            ),
          ),
        ),
        if (photos.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 6, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('这天还没有照片',
                    style: TextStyle(fontSize: 12, color: t3)),
                SizedBox(height: 4),
                Text('去导入素材',
                    style: TextStyle(fontSize: 10, color: t3)),
              ],
            ),
          )
        else
          for (final e in orderedPlaces) ...[
            // 地点小字（同一天不同地点之间的分隔）
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 5),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 3,
                    decoration: const BoxDecoration(
                        color: accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${districtOf(e.key, lat: e.value.first.lat, lng: e.value.first.lng)} · ${e.value.length} 张',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, color: t2),
                        ),
                        // 精确地址放下一行小字（与「到区」不同才显示）
                        if (e.key !=
                            districtOf(e.key,
                                lat: e.value.first.lat,
                                lng: e.value.first.lng))
                          Text(
                            e.key,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 9, height: 1.4, color: t3),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _photoGrid(e.value),
          ],
      ],
    );
  }

  /// 一天内涉及的城市（去重，多个用「、」连起来）。
  String _dayCities(List<Photo> photos) {
    final cities = <String>[];
    for (final p in photos) {
      // 没坐标的照片无法反查城市，跳过（否则会把整段长地址塞进标题）
      if (p.lat == null || p.lng == null) continue;
      final c = p.city;
      if (c.isNotEmpty && !cities.contains(c)) cities.add(c);
    }
    if (cities.isEmpty) {
      return photos.isEmpty ? '未标注' : shortPlace(photos.first.place);
    }
    return cities.join('、');
  }

  Widget _photoGrid(List<Photo> photos) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: photos.length,
      itemBuilder: (_, i) {
        final p = photos[i];
        final isSel = _selected.contains(p.id);
        return GestureDetector(
          onTap: () {
            if (_selecting) {
              setState(() {
                isSel ? _selected.remove(p.id) : _selected.add(p.id);
                if (_selected.isEmpty) _exitSelect();
              });
            } else {
              final idx = _allPhotos.indexWhere((x) => x.id == p.id);
              _openPhoto(_allPhotos.isEmpty ? photos : _allPhotos,
                  idx < 0 ? i : idx);
            }
          },
          onLongPress: () {
            if (!_selecting) _enterSelect(p.id);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              PhotoThumb(uri: p.uri),
              if (!_selecting)
                Positioned(left: 6, top: 6, child: PhotoMarks.fromPhoto(p)),
              if (_selecting && isSel)
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
    );
  }

}


/// 顶部行程胶囊（规格 §4）：高 36，最大宽 180。

class _TripPickerSheet extends StatelessWidget {
  const _TripPickerSheet({required this.trips, required this.currentId});

  final List<Trip> trips;
  final String currentId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('切换行程',
              style: TextStyle(fontSize: fsBody, color: t3)),
          const SizedBox(height: 6),
          ...trips.map((t) => GestureDetector(
                onTap: () => Navigator.of(context).pop(t),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(t.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: fsCardTitle,
                                fontWeight: FontWeight.w600,
                                color: t.id == currentId ? accent : t1)),
                      ),
                      if (t.id == currentId)
                        const Icon(Icons.check, size: 18, color: accent),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

/// 底部 tab（行程 / 地图）。
class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? accent : t3;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(fontSize: 10, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
