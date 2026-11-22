import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../data/models/trip.dart';
import '../../data/repository.dart';
import '../year/year_summary.dart';
import '../../data/weather.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/photo_thumb.dart';
import '../../widgets/sheet_button.dart';

/// 行程列表页（首页，底部第一个 tab）。
class TripsPage extends StatefulWidget {
  const TripsPage({super.key});

  @override
  State<TripsPage> createState() => _TripsPageState();
}

/// 行程搜索：匹配名称 / 手记 / 城市 / 省份（本地 LIKE，不联网）。
class _TripSearchDelegate extends SearchDelegate<Trip?> {
  _TripSearchDelegate(this.repo);

  final TripRepo repo;

  @override
  String get searchFieldLabel => '搜行程、城市或手记';

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  /// 缓存「查询词 → Future」：SearchDelegate 每次按键都会重建，
  /// 把 repo.search 写在 build 里会变成「每敲一个字全表扫一遍照片」。
  String _lastQuery = '';
  Future<List<Trip>>? _lastFuture;

  Future<List<Trip>> _searchOnce(String q) {
    if (q != _lastQuery || _lastFuture == null) {
      _lastQuery = q;
      _lastFuture = repo.search(q);
    }
    return _lastFuture!;
  }

  Widget _results(BuildContext context) {
    final q = query.trim();
    if (q.isEmpty) {
      _lastQuery = '';
      _lastFuture = null;
      return const Center(
        child: Text('输入关键字开始搜索',
            style: TextStyle(color: t3, fontSize: fsBody)),
      );
    }
    return FutureBuilder<List<Trip>>(
      future: _searchOnce(q),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: accent));
        }
        final list = snap.data!;
        if (list.isEmpty) {
          return const Center(
            child: Text('没有找到匹配的行程',
                style: TextStyle(color: t3, fontSize: fsBody)),
          );
        }
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, i) {
            final t = list[i];
            return ListTile(
              title: Text(t.name,
                  style: const TextStyle(fontSize: fsBody, color: t1)),
              subtitle: Text('${t.startDate} - ${t.endDate}',
                  style: const TextStyle(fontSize: fsCaption, color: t3)),
              trailing: const Icon(Icons.chevron_right, size: 16, color: t3),
              onTap: () {
                close(context, t);
                Navigator.of(context)
                    .pushNamed('/trip/map', arguments: t.id);
              },
            );
          },
        );
      },
    );
  }
}

/// 列表排布：卡片（看氛围）/ 列表（找行程）。
enum _TripLayout { card, list }

class _TripsPageState extends State<TripsPage> {
  _TripLayout _layout = _TripLayout.card;

  @override
  void initState() {
    super.initState();
    // 12 月 31 日第一次打开 → 自动弹年度总结（一年只弹一次）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowYearSummary(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final trips = appState.trips;
    final totalPhotos =
        trips.fold<int>(0, (s, t) => s + (appState.photoCounts[t.id] ?? 0));

    return AppScaffold(
      title: '旅迹',
      subtitle: trips.isEmpty ? '还没有行程' : '${trips.length} 次 · ${fmtNum(totalPhotos)} 张',
      actions: [
        HeaderIconButton(
          onTap: () => showSearch<Trip?>(
            context: context,
            delegate: _TripSearchDelegate(context.read<AppState>().tripRepo),
          ),
          child: const Icon(Icons.search, color: t2, size: 18),
        ),
        const SizedBox(width: 8),
        HeaderIconButton(
          // 图标表示「点了会变成什么」：卡片态显示列表图标，列表态显示网格图标
          onTap: () => setState(() =>
              _layout = _layout == _TripLayout.card
                  ? _TripLayout.list
                  : _TripLayout.card),
          child: Icon(
            _layout == _TripLayout.card
                ? Icons.view_list_rounded
                : Icons.grid_view_rounded,
            color: t2,
            size: 18,
          ),
        ),
        const SizedBox(width: 8),
        HeaderIconButton(
          onTap: () => _showAddMenu(context),
          child: const Icon(Icons.add, color: t2, size: 18),
        ),
      ],
      body: trips.isEmpty
          ? const _EmptyState()
          : Column(
              children: [
                if (appState.missingCount > 0)
                  _NoticeBar(
                    count: appState.missingCount,
                    // 不传 tripId → 补救页查「所有行程」的缺位置照片，
                    // 和主页的全局计数口径一致（不会再出现「说有 3 张只显示 2 张」）
                    onTap: () =>
                        Navigator.of(context).pushNamed('/trip/remedy'),
                  ),
                Expanded(
                    child: _TripList(trips: trips, layout: _layout)),
              ],
            ),
    );
  }

  Future<void> _showAddMenu(BuildContext context) async {
    final action = await AppSheet.show<String>(
      context,
      child: const _AddMenuSheet(),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'new':
        await _showNewTripSheet(context);
      case 'import':
        Navigator.of(context).pushNamed('/import');
      case 'settings':
        Navigator.of(context).pushNamed('/settings');
    }
  }

  Future<void> _showNewTripSheet(BuildContext context) async {
    final appState = context.read<AppState>();
    final data = await AppSheet.show<_NewTripData>(
      context,
      child: const _NewTripSheet(),
    );
    if (data == null || !context.mounted) return;
    await appState.createTrip(
        name: data.name, start: data.start, end: data.end);
    if (context.mounted) _toast(context, '已创建「${data.name}」');
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// 顶部橙色提醒条（原型 .notice）：缺位置素材总数。
class _NoticeBar extends StatelessWidget {
  const _NoticeBar({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(padPage, 12, padPage, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: gold.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: gold.withValues(alpha: .3)),
        ),
        child: Row(
          children: [
            Container(
                width: 6,
                height: 6,
                decoration:
                    const BoxDecoration(color: gold, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('$count 张素材缺少位置信息',
                  style: const TextStyle(fontSize: fsBody, color: gold)),
            ),
            const Text('去补全 ›',
                style: TextStyle(
                    fontSize: fsBody,
                    fontWeight: FontWeight.w700,
                    color: gold)),
          ],
        ),
      ),
    );
  }
}

/// 年份分隔标题：小字 + 一条细线，不抢行程卡片的视觉重心。
class _YearHeader extends StatelessWidget {
  const _YearHeader({
    required this.year,
    required this.collapsed,
    required this.count,
    required this.onTap,
  });

  final String year;
  final bool collapsed;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Row(
          children: [
            Text(year,
                style: const TextStyle(
                    fontSize: fsCardTitle,
                    fontWeight: FontWeight.w600,
                    color: t2)),
            const SizedBox(width: 8),
            // 收起时用「N 次」提示还有多少内容，不画箭头
            if (collapsed)
              Text('$count 次',
                  style: const TextStyle(fontSize: fsCaption, color: t3)),
            const SizedBox(width: 10),
            const Expanded(child: Divider(color: line, height: 1)),
          ],
        ),
      ),
    );
  }
}

class _TripList extends StatefulWidget {
  const _TripList({required this.trips, this.layout = _TripLayout.card});

  final List<Trip> trips;
  final _TripLayout layout;

  @override
  State<_TripList> createState() => _TripListState();
}

class _TripListState extends State<_TripList> {
  /// 收起的年份。默认只展开「今年」，其余年份收起。
  late Set<String> _collapsed = _initialCollapsed();

  List<Trip> get trips => widget.trips;
  _TripLayout get layout => widget.layout;

  Set<String> _initialCollapsed() {
    final thisYear = DateTime.now().year.toString();
    return {
      for (final t in widget.trips)
        if (t.startDate.length >= 4 &&
            t.startDate.substring(0, 4) != thisYear)
          t.startDate.substring(0, 4),
    };
  }

  @override
  void didUpdateWidget(covariant _TripList old) {
    super.didUpdateWidget(old);
    // 行程增删后重算：新出现的年份保持收起（除非是今年）
    if (old.trips.length != widget.trips.length) {
      _collapsed = _initialCollapsed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    // 按年份分组：行程多了以后，滚动找「去年那次」会很痛苦。
    // 用扁平列表（String=年份标题，Trip=行程），保持 ListView.builder 的懒加载。
    // 先按开始日期倒序：`listAlive()` 是按「最近导入时间」排的，
    // 往旧行程补照片会把它顶到前面 → 年份标题会重复出现（2026→2025→2024→2025）。
    final sorted = [...trips]
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    final items = <Object>[];
    String? lastYear;
    for (final t in sorted) {
      final y = t.startDate.length >= 4
          ? t.startDate.substring(0, 4)
          : t.startDate;
      if (y != lastYear) {
        items.add(y);
        lastYear = y;
      }
      // 收起的年份只保留标题，不铺卡片
      if (!_collapsed.contains(y)) items.add(t);
    }

    // 下拉刷新：在行程页补/改数据后不用退出重进
    return RefreshIndicator(
      color: accent,
      backgroundColor: panel,
      onRefresh: () => appState.reload(),
      child: ListView.builder(
        // 内容不足一屏时也要能下拉（否则手势不触发）
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 14),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[i];
          if (item is String) {
            final collapsed = _collapsed.contains(item);
            return _YearHeader(
              year: item,
              collapsed: collapsed,
              count: sorted
                  .where((t) =>
                      t.startDate.length >= 4 &&
                      t.startDate.substring(0, 4) == item)
                  .length,
              onTap: () => setState(() {
                if (collapsed) {
                  _collapsed.remove(item);
                } else {
                  _collapsed.add(item);
                }
              }),
            );
          }
          final t = item as Trip;
          final count = appState.photoCounts[t.id] ?? 0;
          final covers = appState.covers[t.id] ?? const <String>[];
          final tile = layout == _TripLayout.list
              ? _TripRow(
                  key: ValueKey(t.id), trip: t, count: count, covers: covers)
              : _TripCard(
                  key: ValueKey(t.id), trip: t, count: count, covers: covers);
          // 长按快捷删除（不用进详情页再找菜单）
          return GestureDetector(
            onLongPress: () => _confirmDelete(context, appState, t),
            child: tile,
          );
        },
      ),
    );
  }
}

/// 长按行程卡片的删除确认。
Future<void> _confirmDelete(
    BuildContext context, AppState appState, Trip trip) async {
  final ok = await ConfirmDialog.show(
    context,
    title: '删除「${trip.name}」？',
    desc: '行程和其中的照片记录会一起移除，'
        '**系统相册里的原图不受影响**。\n\n'
        '这个操作不可撤销。',
    okText: '删除',
  );
  if (!ok) return;
  await appState.tripRepo.delete(trip.id);
  await appState.reload();
}

/// 列表视图的一行（参照 App Store 风格：三行文字等大，行距略松）。
class _TripRow extends StatelessWidget {
  const _TripRow(
      {super.key,
      required this.trip,
      required this.count,
      required this.covers});

  final Trip trip;
  final int count;
  final List<String> covers;

  int _days() {
    try {
      final a = DateTime.parse(trip.startDate);
      final b = DateTime.parse(trip.endDate);
      return b.difference(a).inDays + 1;
    } catch (_) {
      return 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cover = covers.isNotEmpty ? covers.first : null;
    // 标题 15（fsTitle）、副行 13（苹果 Footnote 档）、张数 11（fsCaption）
    const sub = TextStyle(fontSize: 13, height: 1.5, color: t3);
    return GestureDetector(
      onTap: () =>
          Navigator.of(context).pushNamed('/trip/map', arguments: trip.id),
      child: Container(
        // 边距必须和卡片模式一致：左右 16、项间距 12。
        // 之前这里是 EdgeInsets.only(bottom: 8)，左右为 0，整行贴着屏幕边缘。
        margin: const EdgeInsets.fromLTRB(padPage, 0, padPage, gapCard),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: panel2,
          borderRadius: BorderRadius.circular(radiusCard),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 64,
                height: 64,
                child: cover == null
                    ? const ColoredBox(color: panel)
                    : PhotoThumb(uri: cover, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          trip.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: fsTitle,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              color: t1),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(fmtNum(count),
                          style:
                              const TextStyle(fontSize: fsCaption, color: t3)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    // 用 dayLabel 统一成「10月14日」，不再显示 2026-10-14 这种机器格式
                    '${dayLabel(trip.startDate)} — ${dayLabel(trip.endDate)}'
                    ' · ${_days()} 天',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sub,
                  ),
                  // 没写手记就整行省略，等用户自己进精选写
                  if (trip.note.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      trip.note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sub.copyWith(color: t2),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard(
      {super.key,
      required this.trip,
      required this.count,
      required this.covers});

  final Trip trip;
  final int count;
  final List<String> covers;

  @override
  Widget build(BuildContext context) {
    final days = DateTime.parse(trip.endDate)
            .difference(DateTime.parse(trip.startDate))
            .inDays +
        1;
    final noteLine = trip.note.split('\n').first.trim();

    return GestureDetector(
      onTap: () =>
          Navigator.of(context).pushNamed('/trip/map', arguments: trip.id),
      child: Container(
        margin: const EdgeInsets.fromLTRB(padPage, 0, padPage, gapCard),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: panel2,
          borderRadius: BorderRadius.circular(radiusCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 原型 .cover：1 大 + 2 小，高 120。
            SizedBox(
              height: 120,
              width: double.infinity,
              child: _CoverCollage(uris: covers),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          trip.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: t1),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 时间与张数都在标题这一行，右对齐
                      Text(
                        '${dayLabel(trip.startDate)} — '
                        '${dayLabel(trip.endDate)} · $days 天',
                        style: const TextStyle(fontSize: 9, color: t3),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${fmtNum(count)} 张',
                        style: const TextStyle(fontSize: 9, color: t3),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // 天气条独占整行
                  _DateStrip(trip: trip),
                  const SizedBox(height: 6),
                  // 没写手记就不显示这一行
                  if (noteLine.isNotEmpty)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            noteLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontSize: fsBody, color: t2),
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 14, color: t3),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 卡片里的日期条（原型 .wstrip）：日期数字 + 天气图标（V1 无天气数据，用统一图标占位）。
/// 卡片里的天气条：日期 + 天气图标 + 最高温。
///
/// 真实数据来自 Open-Meteo 历史天气（按行程整段一次拉取并缓存）；
/// 离线或拿不到时退回原来的太阳占位，不阻塞、不报错。
class _DateStrip extends StatefulWidget {
  const _DateStrip({required this.trip});

  final Trip trip;
  @override
  State<_DateStrip> createState() => _DateStripState();
}

class _DateStripState extends State<_DateStrip> {
  /// 必须缓存 future：放在 build 里会导致「每重建一次就重新请求一次」，
  /// 日志里同一行程刷几十行 [Weather] 就是这个原因。
  Future<(Map<String, DayWeather>, Map<String, int>)>? _future;

  Trip get trip => widget.trip;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _DateStrip old) {
    super.didUpdateWidget(old);
    if (old.trip.id != trip.id ||
        old.trip.startDate != trip.startDate ||
        old.trip.endDate != trip.endDate) {
      _future = _load();
    }
  }

  Future<(Map<String, DayWeather>, Map<String, int>)> _load() async {
    final appState = context.read<AppState>();
    final counts = await appState.tripRepo.dayCounts(trip.id);
    // 按「每天各自的坐标」取天气：跨城行程（成都→德阳）才对得上。
    final dayCoords = await appState.tripRepo.dayLocations(trip.id);
    Map<String, DayWeather> map = const {};
    if (dayCoords.isNotEmpty) {
      map = await appState.weather.forDays(
        tripId: trip.id,
        dayCoords: dayCoords,
      );
    }
    // ignore: avoid_print
    print('[DateStrip] trip=${trip.id.substring(0, 8)} '
        'counts=$counts weatherKeys=${map.keys.toList()}');
    return (map, counts);
  }

  IconData _icon(DayWeather w) {
    if (w.isThunder) return Icons.thunderstorm_outlined;
    if (w.isSnow) return Icons.ac_unit;
    if (w.isRain) return Icons.water_drop_outlined;
    if (w.isFog) return Icons.foggy;
    if (w.isCloudy) return Icons.cloud_outlined;
    return Icons.wb_sunny_outlined;
  }

  @override
  Widget build(BuildContext context) {
    // 兜底：没有天气数据时**只列有照片的日期**，不画假的晴天图标
    Widget placeholder(List<String> photoDays) {
      if (photoDays.isEmpty) return const SizedBox.shrink();
      return Row(
        children: [
          for (final key in photoDays.take(7))
            Padding(
              padding: const EdgeInsets.only(right: 9),
              child: Text(key.substring(8),
                  style: const TextStyle(fontSize: 9, color: t3)),
            ),
        ],
      );
    }


    return FutureBuilder<(Map<String, DayWeather>, Map<String, int>)>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) return const SizedBox.shrink();
        final map = data.$1;
        final counts = data.$2;
        // 只遍历「确实有照片的日期」，且**不按行程天数截断**：
        // 10-14 开始的 19 天行程里，10-28 / 10-31 才不会漏掉。
        final photoDays =
            counts.keys.where((k) => (counts[k] ?? 0) > 0).toList()..sort();
        if (map.isEmpty) return placeholder(photoDays);
        if (photoDays.isEmpty) return const SizedBox.shrink();
        final rows = <Widget>[];
        for (final key in photoDays.take(7)) {
          final w = map[key];
          rows.add(Padding(
            padding: const EdgeInsets.only(right: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(key.substring(8),
                    style: const TextStyle(fontSize: 9, color: t3)),
                // 拿不到天气就别画太阳：那会把「不知道」显示成「晴天」。
                // 只留日期，如实表达「这天有照片但没有天气数据」。
                if (w != null) ...[
                  const SizedBox(width: 3),
                  Icon(_icon(w), size: 11, color: t2),
                ],
              ],
            ),
          ));
        }
        return Row(children: rows);
      },
    );
  }
}

class _CoverCollage extends StatelessWidget {
  const _CoverCollage({required this.uris});

  final List<String> uris;

  @override
  Widget build(BuildContext context) {
    if (uris.isEmpty) return const _CoverPlaceholder();
    if (uris.length == 1) return PhotoThumb(uri: uris[0]);
    return Row(
      children: [
        Expanded(flex: 17, child: PhotoThumb(uri: uris[0])),
        const SizedBox(width: 2),
        Expanded(
          flex: 10,
          child: Column(
            children: [
              Expanded(child: PhotoThumb(uri: uris[1])),
              const SizedBox(height: 2),
              Expanded(
                child: uris.length > 2
                    ? PhotoThumb(uri: uris[2])
                    : Container(color: const Color(0xFF0A0F14)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0A0F14),
      alignment: Alignment.center,
      child: const Icon(Icons.landscape_outlined, color: t3, size: 26),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library_outlined, color: t3, size: 40),
          SizedBox(height: 12),
          Text(
            '点击右上角「+」创建行程，\n'
            '导入的照片会按时间和地点自动排好，\n'
            '最后在地图上看见自己走过的路。',
            textAlign: TextAlign.center,
            style: TextStyle(color: t3, fontSize: fsBody, height: 1.9),
          ),
        ],
      ),
    );
  }
}

/// 「＋」菜单（底部弹层）。
class _AddMenuSheet extends StatelessWidget {
  const _AddMenuSheet();

  @override
  Widget build(BuildContext context) {
    Widget item(String key, String title, String subtitle, {IconData? icon}) {
      // 用 InkWell + 撑满宽度：原来 GestureDetector 只包住文字，
      // 点击区域仅文字大小（Column 的 mainAxisSize: min 决定的）。
      return InkWell(
        onTap: () => Navigator.of(context).pop(key),
        child: Container(
          width: double.infinity,
          color: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: t2),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: fsCardTitle,
                            fontWeight: FontWeight.w600,
                            color: t1)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(fontSize: fsBody, color: t3)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('新建',
              style: TextStyle(fontSize: fsBody, color: t3)),
          const SizedBox(height: 6),
          item('import', '导入素材', '从相册或文件夹里挑照片',
              icon: Icons.add_photo_alternate_outlined),
          item('new', '新建旅程', '先建一个空行程，照片随后补',
              icon: Icons.map_outlined),
          item('settings', '设置', '数据占用 · 关于旅迹',
              icon: Icons.settings_outlined),
        ],
      ),
    );
  }
}

class _NewTripData {
  const _NewTripData(
      {required this.name, required this.start, required this.end});

  final String name;
  final DateTime start;
  final DateTime end;
}

/// 新建旅程表单（底部弹层）。
class _NewTripSheet extends StatefulWidget {
  const _NewTripSheet();

  @override
  State<_NewTripSheet> createState() => _NewTripSheetState();
}

class _NewTripSheetState extends State<_NewTripSheet> {
  final _nameCtrl = TextEditingController();
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now().add(const Duration(days: 2));

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  /// 一次选完起止：行程本来就是一个区间，分两次弹窗既慢又可能先后颠倒。
  /// 组件自身保证 start <= end，不需要额外校验。
  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _start, end: _end),
      helpText: '选择行程日期',
      saveText: '确定',
    );
    if (picked != null) {
      setState(() {
        _start = picked.start;
        _end = picked.end;
      });
    }
  }

  /// 「共 N 天」的提示文案。
  String _rangeHint() {
    final n = _end.difference(_start).inDays + 1;
    return n > 0 ? '共 $n 天' : '';
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _toast('给这次旅程起个名字');
      return;
    }
    if (_end.isBefore(_start)) {
      _toast('结束日期不能早于开始');
      return;
    }
    Navigator.of(context)
        .pop(_NewTripData(name: name, start: _start, end: _end));
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(padPage, padPage, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('新建旅程',
              style: TextStyle(
                  fontSize: fsTitle, fontWeight: FontWeight.w600, color: t1)),
          const SizedBox(height: 16),
          _Field(
            label: '名称',
            child: TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: const TextStyle(color: t1, fontSize: fsBody),
              decoration: const InputDecoration(
                hintText: '例如 川西 · 稻城',
                hintStyle: TextStyle(color: t3),
                isDense: true,
                border: InputBorder.none,
              ),
            ),
          ),
          _Field(
            label: '日期',
            child: _DateField(
              text: '${ymd(_start)}  —  ${ymd(_end)}',
              hint: _rangeHint(),
              onTap: _pickRange,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SheetButton(
                  label: '取消',
                  onTap: () => Navigator.of(context).pop(),
                  primary: false,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SheetButton(
                    label: '创建', onTap: _submit, primary: true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(label,
                style: const TextStyle(fontSize: fsBody, color: t3)),
          ),
          Expanded(
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.circular(radiusTag + 1),
                border: Border.all(color: line),
              ),
              child: Align(alignment: Alignment.centerLeft, child: child),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.text, required this.onTap, this.hint});

  final String text;
  final VoidCallback onTap;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Text(text, style: const TextStyle(color: t1, fontSize: fsBody)),
          if (hint != null && hint!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(hint!,
                style: const TextStyle(color: t3, fontSize: fsCaption)),
          ],
          const Spacer(),
          const Icon(Icons.calendar_today_outlined, size: 15, color: t3),
        ],
      ),
    );
  }
}


