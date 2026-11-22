import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../app_state.dart';
import '../../core/country_index.dart';
import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../widgets/photo_thumb.dart';

/// 一年的旅行统计（纯本地聚合，不发任何请求）。
class YearStats {
  final int year;
  final int trips;
  final int photos;
  final List<String> tripNames;
  final List<String> countryNames;
  final List<String> cityNames;

  /// 精选照片（最多 [maxFeatured] 张），用于年度页底部小网格。
  final List<String> featuredUris;

  const YearStats({
    required this.year,
    required this.trips,
    required this.photos,
    required this.tripNames,
    required this.countryNames,
    required this.cityNames,
    required this.featuredUris,
  });

  int get cities => cityNames.length;
  int get countries => countryNames.length;
  bool get isEmpty => photos == 0;

  /// 精选最多放 6 张（3 列 × 2 行）。
  /// 再多就把「总结」变成「相册」了，长图会失控、重点也会散。
  static const int maxFeatured = 6;

  /// 聚合某一年。
  static Future<YearStats> compute(Database db, int year) async {
    final prefix = '$year-';

    // ① 行程（按开始日期落在该年）
    final tripRows = await db.query(
      'trips',
      columns: ['id', 'name'],
      where: 'deleted_at IS NULL AND start_date LIKE ?',
      whereArgs: ['$prefix%'],
      orderBy: 'start_date ASC',
    );
    final tripNames = <String>[];
    final tripIds = <String>{};
    for (final r in tripRows) {
      final id = r['id'];
      final name = r['name'];
      if (id is String) tripIds.add(id);
      if (name is String && name.isNotEmpty) tripNames.add(name);
    }

    // ② 照片（按拍摄时间落在该年）
    final rows = await db.query(
      'photos',
      columns: [
        'id', 'uri', 'place', 'lat', 'lng', 'taken_at',
        'is_cover', 'is_featured', 'note',
      ],
      where: 'deleted_at IS NULL AND taken_at LIKE ?',
      whereArgs: ['$prefix%'],
      orderBy: 'taken_at ASC',
    );

    final cities = <String>{};
    final countries = <String>{};
    final featured = <String>[];

    for (final r in rows) {
      final place = (r['place'] as String?) ?? '';
      final lat = (r['lat'] as num?)?.toDouble();
      final lng = (r['lng'] as num?)?.toDouble();

      if (place.isNotEmpty) {
        final c = cityOf(place, lat: lat, lng: lng);
        if (c != '未标注' && c.isNotEmpty) cities.add(c);
      }
      final country = CountryIndex.byPlace(place) ??
          (lat != null && lng != null ? CountryIndex.countryOf(lat, lng) : null);
      if (country != null && country.isNotEmpty) countries.add(country);

      // 精选口径：设过封面 / 标过精选 / 写着手记，三者任一
      final uri = r['uri'] as String?;
      final isFeat = (r['is_cover'] as int? ?? 0) == 1 ||
          (r['is_featured'] as int? ?? 0) == 1 ||
          ((r['note'] as String?) ?? '').trim().isNotEmpty;
      if (isFeat && uri != null && uri.isNotEmpty) featured.add(uri);
    }

    final countryList = countries.toList()..sort();
    final cityList = cities.toList()..sort();

    return YearStats(
      year: year,
      trips: tripIds.length,
      photos: rows.length,
      tripNames: tripNames,
      countryNames: countryList,
      cityNames: cityList,
      featuredUris: featured.take(maxFeatured).toList(),
    );
  }
}

/// 全屏年度总结页：四个可展开板块 + 精选小网格，支持长图保存。
class YearSummaryPage extends StatefulWidget {
  const YearSummaryPage({super.key, required this.stats});

  final YearStats stats;

  @override
  State<YearSummaryPage> createState() => _YearSummaryPageState();
}

class _YearSummaryPageState extends State<YearSummaryPage> {
  final _shotKey = GlobalKey();
  bool _saving = false;

  /// 用户当前展开了哪些板块（默认全收起）。保存长图时按当前状态截，
  /// 不擅自改动用户看到的内容。
  final Set<String> _open = <String>{};

  Future<void> _saveAsImage() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // 等一帧，让当前布局稳定（不改变用户的展开状态）
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final bytes = await captureLongImage(_shotKey);
      if (bytes == null) throw '截图为空';
      await const MethodChannel('luji/exif').invokeMethod<String>(
        'saveImage',
        {'bytes': bytes, 'name': 'luji-year-${widget.stats.year}'},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存到相册')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stats;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: t2, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title:
            const Text('年度回忆', style: TextStyle(fontSize: fsBody, color: t2)),
        centerTitle: true,
      ),
      // 用 SingleChildScrollView：RepaintBoundary 的高度才等于完整内容高度，
      // toImage 才能截到屏幕外的部分（放在 ListView 里只会截可见区域）。
      body: SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          RepaintBoundary(
            key: _shotKey,
            child: Container(
              color: bg,
              width: double.infinity,
              // 内容少时也撑到接近一屏高（截图不会比屏幕矮太多）；
              // 内容多则自然向下延伸成长图。上下各留余量，不顶边。
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height * 0.78,
              ),
              // 左右 26：数字不再贴着截图边框，纯色背景把两侧填满
              padding: const EdgeInsets.fromLTRB(26, 28, 26, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${s.year} · 旅迹',
                      style: const TextStyle(
                          fontSize: 46,
                          fontWeight: FontWeight.w600,
                          color: t1,
                          height: 1.1)),
                  const SizedBox(height: 4),
                  const Text('这一年，你走过的地方',
                      style: TextStyle(fontSize: fsBody, color: t3)),
                  const SizedBox(height: 22),
                  _block('旅行', '次', s.trips, s.tripNames),
                  _block('国家', '个', s.countries, s.countryNames),
                  _block('城市', '个', s.cities, s.cityNames),
                  _photoBlock(s),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          Center(
            child: TextButton(
              onPressed: _saving ? null : _saveAsImage,
              child: Text(_saving ? '正在保存…' : '收下这份回忆',
                  style: const TextStyle(color: accent, fontSize: fsBody)),
            ),
          ),
          ],
        ),
      ),
    );
  }

  /// 一个「大数字 + 说明」的板块：点整行展开/收起，不放箭头。
  /// 视觉沿用第一版（数字在前、40sp），只是点击区域变成整行。
  Widget _block(String label, String unit, int n, List<String> items) {
    final open = _open.contains(label);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() {
            if (open) {
              _open.remove(label);
            } else {
              _open.add(label);
            }
          }),
          child: Padding(
            // 第一版的节奏：每行之间留白大，视觉更松
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('$n',
                    style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w600,
                        color: t1,
                        height: 1.1)),
                const SizedBox(width: 10),
                Text('$unit$label',
                    style: const TextStyle(fontSize: fsBody, color: t3)),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ConstrainedBox(
              // 展开区最多占 1.2 屏，再长就截断并做渐隐，
              // 避免长图无限拉长、也避免一屏内被标签淹没
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 1.2,
              ),
              child: ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, Colors.white, Colors.transparent],
                  stops: [0.0, 0.86, 1.0],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: items.isEmpty
                ? const Text('没有记录',
                    style: TextStyle(fontSize: fsCaption, color: t3))
                : Wrap(
                    // 无边框、无底板：像正文一样简单写出来，靠间距分隔
                    spacing: 18,
                    runSpacing: 12,
                    children: [
                      for (final t in items.take(12))
                        Text(t,
                            style: const TextStyle(
                                fontSize: fsBody, color: t2)),
                      if (items.length > 12)
                        Text('等 ${items.length} 个',
                            style: const TextStyle(
                                fontSize: fsBody, color: t3)),
                    ],
                  ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 照片板块：数字行点击展开精选小网格（最多 6 张）。
  Widget _photoBlock(YearStats s) {
    final open = _open.contains('照片');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() {
            if (open) {
              _open.remove('照片');
            } else {
              _open.add('照片');
            }
          }),
          child: Padding(
            // 第一版的节奏：每行之间留白大，视觉更松
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(fmtNum(s.photos),
                    style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w600,
                        color: t1,
                        height: 1.1)),
                const SizedBox(width: 10),
                const Text('张照片',
                    style: TextStyle(fontSize: fsBody, color: t3)),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: s.featuredUris.isEmpty
                ? const Text('还没有精选照片',
                    style: TextStyle(fontSize: fsCaption, color: t3))
                : GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                    ),
                    itemCount: s.featuredUris.length,
                    itemBuilder: (_, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: PhotoThumb(
                          uri: s.featuredUris[i], fit: BoxFit.cover),
                    ),
                  ),
          ),
      ],
    );
  }
}

/// 把整页（含展开内容）截成长图 PNG。
/// 把内容区截成 PNG。
///
/// 输出宽度固定为「一屏宽」：pixelRatio = 屏幕物理宽 / 内容逻辑宽，
/// 这样无论内容多长，图都不会比手机屏幕更宽；内容高则自然向下延伸。
Future<Uint8List?> captureLongImage(GlobalKey key) async {
  final ctx = key.currentContext;
  if (ctx == null) return null;
  final boundary = ctx.findRenderObject();
  if (boundary is! RenderRepaintBoundary) return null;

  final media = MediaQuery.of(ctx);
  final screenPhysical = media.size.width * media.devicePixelRatio;
  final contentLogical = boundary.size.width;
  final ratio = contentLogical > 0 ? screenPhysical / contentLogical : 2.5;

  final image = await boundary.toImage(pixelRatio: ratio.clamp(1.0, 4.0));
  final data = await image.toByteData(format: ImageByteFormat.png);
  return data?.buffer.asUint8List();
}

/// 12 月 31 日首次打开时自动弹出年度总结（一年只弹一次）。
Future<void> maybeShowYearSummary(BuildContext context) async {
  final now = DateTime.now();
  if (now.month != 12 || now.day != 31) return;

  final appState = context.read<AppState>();
  final key = 'year_summary_${now.year}';
  try {
    final seen = await appState.tripRepo.metaGet(key);
    if (seen != null) return;
  } catch (_) {
    return;
  }

  final stats = await appState.tripRepo.yearStats(now.year);
  if (!context.mounted || stats.isEmpty) return;
  await appState.tripRepo.metaSet(key, '1');
  if (!context.mounted) return;
  await Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => YearSummaryPage(stats: stats)));
}
