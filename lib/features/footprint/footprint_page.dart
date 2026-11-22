import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../widgets/segmented.dart';
import '../../widgets/app_sheet.dart';
import '../../core/extensions.dart';
import '../../core/country_index.dart';
import '../../core/theme.dart';
import '../../data/models/trip_location.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/map_point.dart';
import '../../widgets/static_world_map.dart';
import '../../widgets/province_index.dart';
import '../../widgets/static_china_map.dart';

/// 足迹页（底部第二个 tab，scale: world）。技术方案 §1.3 / §8.4。
class FootprintPage extends StatefulWidget {
  const FootprintPage({super.key});

  @override
  State<FootprintPage> createState() => _FootprintPageState();
}

class _FootprintPageState extends State<FootprintPage> {
  List<TripLocation> _locations = [];
  /// 中国视图用：同省去重（一个省一个点）
  List<MapPoint> _points = [];
  /// 世界地图用：**原始坐标**，不做任何合并。
  /// dedupe 会把「匹配不到省份」的点用 `'__id'` 分组，但同省平均会让
  /// 波兰这类点的坐标被拉到别处（实测 49.62/21.9 变成 54.9/20.1），
  /// 国家判定随之出错。
  List<MapPoint> _worldPoints = [];

  /// 世界地图要点亮的国家（含中国）。
  /// 不能用 `_worldPoints` 反推：那个列表故意排除了中国境内的点，
  /// 反推的话「中国」永远点不亮。
  Set<String> _worldLit = {};

  /// 每张照片一个点（未聚合）。国家/省份统计必须用它：
  /// `_locations` 是「按地点平均」后的点，跨城一趟会把坐标拉到中间，
  /// 用它判国会和地图点亮不一致（波兰被拉成伊朗那种）。
  List<TripLocation> _rawLocations = [];
  int _lastRev = -1;
  bool _china = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final appState = context.read<AppState>();
    final locations = await appState.tripRepo.tripsWithLocation();
    // 世界地图用「每张照片一个点」，完全不聚合
    final rawPhotos = await appState.tripRepo.photoLocations();
    await ProvinceIndex.ensureLoaded();
    await CountryIndex.ensureLoaded();
    final raw = [
      for (final l in locations)
        MapPoint(id: l.tripId, lat: l.lat, lng: l.lng, label: _cityName(l)),
    ];
    if (!mounted) return;
    setState(() {
      _locations = locations;
      _rawLocations = rawPhotos;
      // 中国视图：先筛掉境外点（普吉岛会落在中国地图右下角，很怪），
      // 再同省去重（用户要求：一个省份最多一个点）
      final inChina = raw
          .where((p) =>
              CountryIndex.byPlace(p.label) == '中国' ||
              (CountryIndex.byPlace(p.label) == null &&
                  CountryIndex.countryOf(p.lat, p.lng) == '中国'))
          .toList();
      _points = ProvinceIndex.dedupe(inChina);
      // ignore: avoid_print
      print('[Footprint] raw=${raw.length} inChina=${inChina.length} '
          'points=${_points.length} '
          'labels=${inChina.take(3).map((p) => p.label).toList()}');
      // 世界地图：直接用每张照片的原始坐标，连 place 分组都不做
      // 世界地图**不含中国境内的点**：国内照片太多会把中国糊成一片红点，
      // 国内去哪看旁边的「中国」视图更清楚（两页功能分离）。
      _worldPoints = [
        for (final l in rawPhotos)
          if ((CountryIndex.byPlace(l.place) ??
                  CountryIndex.countryOf(l.lat, l.lng)) !=
              '中国')
            MapPoint(id: l.tripId, lat: l.lat, lng: l.lng, label: l.place),
      ];

      // 点亮集合从**全部照片**算（含中国），而不是从 _worldPoints。
      // 关键：必须转成**数据原名**再放进去 ——
      // `CountryShape.name` 是 `Indonesia` 这种英文名，
      // 直接放显示名（「印度尼西亚」）会导致 contains 永远失败。
      _worldLit = {};
      for (final l in rawPhotos) {
        final display = CountryIndex.byPlace(l.place) ??
            CountryIndex.countryOf(l.lat, l.lng);
        if (display == null || display.isEmpty) continue;
        final raw = CountryIndex.rawOf(display);
        if (raw != null && raw.isNotEmpty) _worldLit.add(raw);
      }
    });
  }

  /// 国家数：用 `CountryIndex` 做真实的多边形判定（与地图点亮同一份数据）。
  /// 老实现只分「中国 / 境外」，泰国和波兰会被算成同一个国家。
  int get _countryCount => _byCountry().length;

  /// 已去过的省份数（只统计中国境内）。
  int get _provinceCount {
    final set = <String>{};
    for (final l in _rawLocations) {
      if ((CountryIndex.byPlace(l.place) ??
              CountryIndex.countryOf(l.lat, l.lng)) !=
          '中国') {
        continue;
      }
      final prov = ProvinceIndex.provinceOf(l.lat, l.lng);
      if (prov != null && prov.isNotEmpty) set.add(prov);
    }
    return set.length;
  }

  /// 按国家聚合成「国家 → 该国的地点」。
  Map<String, List<TripLocation>> _byCountry() {
    final out = <String, List<TripLocation>>{};
    for (final l in _rawLocations) {
      // 地名前缀最可靠（"泰国普吉府…"、"波兰喀尔巴阡山省…"），
      // 其次才用坐标多边形（小岛/小国常判不出）。
      // 判不出国家就跳过，不要塞进「未知」桶：
      // 那会让「国家数」多加 1，并在列表里多出一个叫「未知」的分组。
      final c = CountryIndex.byPlace(l.place) ??
          CountryIndex.countryOf(l.lat, l.lng);
      if (c == null || c.isEmpty) continue;
      out.putIfAbsent(c, () => []).add(l);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    // 足迹页在 IndexedStack 里，initState 只跑一次；
    // 行程/照片数变化时必须重新拉取，否则永远停在第一次进页面时的数据。
    // watch 数据版本号：补完位置/改完地点后 reload 会 +1，这里自动重载。
    final appState = context.watch<AppState>();
    if (appState.rev != _lastRev) {
      _lastRev = appState.rev;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
    final totalPhotos =
        _locations.fold<int>(0, (s, l) => s + l.photoCount);
    final countries = _countryCount;
    return AppScaffold(
      title: '足迹',
      // 副标题（国家/城市/照片）与下方统计行完全重复，删掉；
      // 标题放大到 22 补住腾出来的视觉重量。
      titleSize: 22,
      body: Column(
        children: [
          SizedBox(
            height: 292,
            child: Stack(
              children: [
                // 世界：静态图，点亮国家；点国家 → 展开去过的城市
                // 中国：静态图，点亮城市
                if (_china)
                  StaticChinaMap(
                    points: _points,
                    onCityTap: (tripId) => Navigator.of(context)
                        .pushNamed('/trip/map', arguments: tripId),
                  )
                else
                  StaticWorldMap(
                    points: _worldPoints,
                    lit: _worldLit,
                    onCountryTap: (_) => _showCities(),
                  ),
              ],
            ),
          ),
          // 左边统计、右边切换器。
          // 统计整体缩进 19 —— 与下方城市行的「绿点 9 + 间距 10」对齐，
          // 这样数字的左边缘正好落在城市名上，而不是对着绿点。
          Padding(
            padding: const EdgeInsets.fromLTRB(padPage, gapInner, padPage, gapInner),
            child: Row(
              // 顶对齐：切换器上沿与统计数字上沿平齐（居中会低约 2.5px）
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 19),
                // 世界视角看国家级，中国视角看省级（用户要求）
                if (!_china)
                  _Stat(n: countries, label: '国家')
                else
                  _Stat(n: _provinceCount, label: '省份'),
                // 统计之间用两倍块间距：三项数字字号大，16 太挤
                const SizedBox(width: gapBlock * 2),
                _Stat(n: _locations.length, label: '城市'),
                const SizedBox(width: gapBlock * 2),
                _Stat(n: totalPhotos, label: '照片'),
                const Spacer(),
                Segmented(
                  items: const [('world', '世界'), ('china', '中国')],
                  selected: _china ? 'china' : 'world',
                  onChanged: (k) => setState(() => _china = k == 'china'),
                  width: 112,
                  height: 28,
                ),
              ],
            ),
          ),
          Expanded(child: _cityList()),
        ],
      ),
    );
  }

  /// 点「已点亮国家」→ 底部弹层展开去过的城市。
  void _showCities() {
    AppSheet.show(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('去过的城市',
                  style: TextStyle(fontSize: fsBody, color: t3)),
            ),
          ),
          for (final l in _locations)
            GestureDetector(
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context)
                    .pushNamed('/trip/map', arguments: l.tripId);
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_cityName(l),
                          style: const TextStyle(
                              fontSize: fsCardTitle,
                              fontWeight: FontWeight.w600,
                              color: t1)),
                    ),
                    Text('${l.photoCount} 张',
                        style:
                            const TextStyle(fontSize: fsCaption, color: t3)),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right, size: 16, color: t3),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _cityList() {
    if (_locations.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '还没有点亮的城市\n去行程里导入素材，这里会自动亮起来',
            textAlign: TextAlign.center,
            style: TextStyle(color: t3, fontSize: fsBody, height: 1.9),
          ),
        ),
      );
    }

    // 中国视图：按「省份」分组（中国地图下方不该只有「中国」一个选项）
    if (_china) {
      final byProvince = <String, List<TripLocation>>{};
      for (final l in _locations) {
        if ((CountryIndex.byPlace(l.place) ??
                CountryIndex.countryOf(l.lat, l.lng)) !=
            '中国') {
          continue;
        }
        final prov = ProvinceIndex.provinceOf(l.lat, l.lng) ?? '其他';
        byProvince.putIfAbsent(prov, () => []).add(l);
      }
      final provNames = byProvince.keys.toList()..sort();
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: padPage, vertical: 4),
        children: [
          for (final n in provNames) _provinceTile(n, byProvince[n]!),
        ],
      );
    }

    // 世界视图：按国家分组
    final byCountry = _byCountry();
    final names = byCountry.keys.toList()
      ..sort((a, b) {
        if (a == '中国') return -1;
        if (b == '中国') return 1;
        return a.compareTo(b);
      });

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: padPage, vertical: 4),
      children: [
        for (final n in names) _countryTile(n, byCountry[n]!),
      ],
    );
  }

  /// 单个省份分组（中国视图：省份 → 城市）。
  Widget _provinceTile(String province, List<TripLocation> locs) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 8),
      iconColor: t3,
      collapsedIconColor: t3,
      shape: const Border(),
      collapsedShape: const Border(),
      title: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration:
                const BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(province,
              style: const TextStyle(
                  fontSize: fsBody,
                  fontWeight: FontWeight.w600,
                  color: t1)),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(left: 19, top: 2),
        child: Text(
          '${locs.length} 个地点 · '
          '${fmtNum(locs.fold<int>(0, (s, l) => s + l.photoCount))} 张',
          style: const TextStyle(fontSize: fsCaption, color: t3),
        ),
      ),
      children: [
        for (final l in locs)
          ListTile(
            dense: true,
            title: Text(_cityName(l),
                style: const TextStyle(fontSize: fsBody, color: t1)),
            trailing: Text('${l.photoCount} 张',
                style: const TextStyle(fontSize: fsCaption, color: t3)),
            onTap: () => Navigator.of(context)
                .pushNamed('/trip/map', arguments: l.tripId),
          ),
      ],
    );
  }

  /// 单个国家分组（世界地图：国家 → 行程 → 城市）。
  Widget _countryTile(String country, List<TripLocation> locs) {
    final byTrip = <String, List<TripLocation>>{};
    for (final l in locs) {
      byTrip.putIfAbsent(l.tripId, () => []).add(l);
    }
    return ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(left: 8),
          iconColor: t3,
          collapsedIconColor: t3,
          shape: const Border(),
          collapsedShape: const Border(),
          title: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration:
                    const BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Text(country,
                  style: const TextStyle(
                      fontSize: fsBody,
                      fontWeight: FontWeight.w600,
                      color: t1)),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(left: 19, top: 2),
            child: Text(
              '${byTrip.length} 个行程 · ${locs.length} 个城市 · '
              '${fmtNum(locs.fold<int>(0, (s, l) => s + l.photoCount))} 张',
              style: const TextStyle(fontSize: fsCaption, color: t3),
            ),
          ),
      children: [
        for (final e in byTrip.entries) _tripTile(e),
      ],
    );
  }

  /// 行程分组（国家展开后的一层）。
  Widget _tripTile(MapEntry<String, List<TripLocation>> e) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.only(right: 8),
      childrenPadding: const EdgeInsets.only(left: 8),
      iconColor: t3,
      collapsedIconColor: t3,
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(
        e.value.first.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            fontSize: fsBody, fontWeight: FontWeight.w600, color: t1),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          '${e.value.length} 个城市 · '
          '${fmtNum(e.value.fold<int>(0, (s, l) => s + l.photoCount))} 张',
          style: const TextStyle(fontSize: fsCaption, color: t3),
        ),
      ),
      children: [
        for (final l in e.value) _cityRow(l),
      ],
    );
  }

  Widget _cityRow(TripLocation l) {
    return GestureDetector(
      onTap: () =>
          Navigator.of(context).pushNamed('/trip/map', arguments: l.tripId),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration:
                  const BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cityOf(l.place, lat: l.lat, lng: l.lng),
                      style: const TextStyle(
                          fontSize: fsBody,
                          fontWeight: FontWeight.w600,
                          color: t1)),
                  const SizedBox(height: 2),
                  Text(l.name,
                      style:
                          const TextStyle(fontSize: fsCaption, color: t3)),
                ],
              ),
            ),
            Text('${fmtNum(l.photoCount)} 张 ›',
                style: const TextStyle(fontSize: fsBody, color: t3)),
          ],
        ),
      ),
    );
  }
}

String _cityName(TripLocation l) {
  final place = l.place;
  if (place == null || place.trim().isEmpty) return l.name;
  final parts = place.split(RegExp(r'[· ,，]'));
  final first = parts.first.trim();
  if (first.isEmpty) return l.name;
  // 标签前加省份：「四川省 · 德阳市」，一眼看出在哪个省
  final prov = ProvinceIndex.provinceOf(l.lat, l.lng);
  if (prov != null && prov.isNotEmpty && !first.startsWith(prov)) {
    return '$prov · $first';
  }
  return first;
}

class _Stat extends StatelessWidget {
  const _Stat({required this.n, required this.label});

  final int n;
  final String label;

  @override
  Widget build(BuildContext context) {
    // 间距交给外层的 gapBlock，组件本身不带边距
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(fmtNum(n),
            style: const TextStyle(
                fontSize: fsTitle, fontWeight: FontWeight.w600, color: t1)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: fsCaption, color: t3)),
      ],
    );
  }
}

