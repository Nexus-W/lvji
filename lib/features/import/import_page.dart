import 'dart:async';

import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/extensions.dart';
import 'package:flutter/services.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/theme.dart';
import '../../data/models/day.dart';
import '../../data/models/import_item.dart';
import '../../data/models/trip.dart';
import '../../data/repository.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_sheet.dart';
import 'photo_processor.dart';
import '../../widgets/sheet_button.dart';
import '../../widgets/pill_button.dart';

/// 原生 EXIF 通道（`luji/exif`）：负责用 setRequireOriginal 取回未被净化的原图。
const _exifChannel = MethodChannel('luji/exif');

/// 导入页（技术方案 §5.1）。选照片 → 读 EXIF/哈希 → 分组预览 → 落库。
class ImportPage extends StatefulWidget {
  const ImportPage({super.key, this.tripId});

  /// 指定目标行程；null 则默认最近一次行程。
  final String? tripId;

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  Trip? _target;
  /// (临时路径, lat, lng, 原始文件名)
  /// 原始文件名必须带着：导入时会把内容写到 `systemTemp/pm_<id>.img`，
  /// 文件名里没有日期，`timeFromFileName` 就永远解析不到时间
  /// （微信保存的 `pic_20261028142142_0` 就是这么丢的）。
  final List<(String, double?, double?, String)> _picked = [];
  bool _processing = false;
  int _done = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _initTarget();
  }

  Future<void> _initTarget() async {
    final appState = context.read<AppState>();
    Trip? target;
    if (widget.tripId != null) {
      target = await appState.tripRepo.find(widget.tripId!);
    }
    target ??= appState.trips.isNotEmpty ? appState.trips.first : null;
    if (mounted) setState(() => _target = target);
  }

  Future<void> _pickImages() async {
    // 注意：ACCESS_MEDIA_LOCATION 由原生在启动时请求（MainActivity 里），
    // 不能用 permission_handler 的 mediaLibrary —— 它在 Android 上没有映射，
    // request() 会直接返回 granted 造成假象。

    // 用相册选择器（photo_manager 读 MediaStore）：
    // Android 14+ 的 Photo Picker 会剥掉 EXIF 的 GPS，而 MediaStore 里的
    // 经纬度是系统自己维护的，跨机型一致。相机拍的照片 MediaStore 通常为空，
    // 这时会自动回退到 EXIF（见 _processOne）。
    if (!mounted) return;
    final assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: const AssetPickerConfig(
        maxAssets: 200,
        requestType: RequestType.image,
      ),
    );
    if (assets == null || assets.isEmpty) return;
    final picked = <(String, double?, double?, String)>[];
    for (final a in assets) {
      // 走 MediaStore.setRequireOriginal 拿原始字节：
      // Android 11+ 的 FUSE 层会把 EXIF 的 GPS 清成 0/1（文件长度不变），
      // 只有声明 ACCESS_MEDIA_LOCATION 并用 setRequireOriginal 才能拿到真值。
      Uint8List? bytes;
      // 原生可能直接返回坐标（MediaStore 列 / MediaMetadataRetriever），
      // 也可能返回原图字节；两者都拿不到再退回插件。
      num? nativeLat;
      num? nativeLng;
      final id = int.tryParse(a.id);
      if (id != null) {
        try {
          final res =
              await _exifChannel.invokeMethod<dynamic>('readOriginal', {'id': id});
          if (res is Map) {
            final b = res['bytes'];
            if (b is Uint8List) bytes = b;
            final la = res['lat'];
            final ln = res['lng'];
            if (la is num && ln is num) {
              nativeLat = la;
              nativeLng = ln;
              // ignore: avoid_print
              print('[位置] 原生取自 ${res['source']}: $la,$ln');
            }
          } else if (res is Uint8List) {
            bytes = res;
          }
        } catch (e) {
          // ignore: avoid_print
          print('[位置] readOriginal 失败: $e（将回退到插件字节，GPS 可能为 0）');
          bytes = null;
        }
      }
      // 回退：插件自带字节（可能是净化过的，但至少能导入）
      bytes ??= await a.originBytes;
      if (bytes == null || bytes.isEmpty) continue;
      final tmp = File('${Directory.systemTemp.path}/pm_${a.id}.img');
      await tmp.writeAsBytes(bytes);
      picked.add((
        tmp.path,
        (nativeLat ?? a.latitude)?.toDouble(),
        (nativeLng ?? a.longitude)?.toDouble(),
        a.title ?? '', // 原始文件名，用于时间兜底
      ));
    }
    if (picked.isEmpty) return;
    if (!mounted) return;
    setState(() => _picked.addAll(picked));
  }


  void _removeAt(int i) => setState(() => _picked.removeAt(i));

  void _clear() => setState(() => _picked.clear());

  Future<void> _chooseTarget() async {
    final appState = context.read<AppState>();
    final trip = await AppSheet.show<Trip>(
      context,
      child: _TargetSheet(trips: appState.trips, current: _target),
    );
    if (trip != null) setState(() => _target = trip);
  }

  Future<void> _import() async {
    // 必须最先判重入：处理 20 张要几十秒，用户连点两下会并发跑两条流水线
    // （同一个 imports/<hash> 被写两次、inserted 计数错、还多 pop 一次）。
    if (_processing) return;
    if (_picked.isEmpty || _target == null) return;
    setState(() => _processing = true);
    final appState = context.read<AppState>();
    final target = _target!;

    final docs = await getApplicationDocumentsDirectory();
    final importDir = Directory(p.join(docs.path, 'imports'));
    await importDir.create(recursive: true);

    setState(() {
      _processing = true;
      _done = 0;
      _total = _picked.length;
    });

    final picked = List<(String, double?, double?, String)>.from(_picked);
    final result = await processPhotos(
      picked,
      importDir.path,
      onProgress: (done, total) {
        if (mounted) {
          setState(() {
            _done = done;
            _total = total;
          });
        }
      },
    );
    if (!mounted) return;
    setState(() => _processing = false);

    final items = result.items;
    if (items.isEmpty) {
      _toast('没有可导入的照片');
      return;
    }

    // 查重 + 分组预览
    final existing =
        await appState.photoRepo.existingHashes(target.id, items.map((i) => i.hash).toList());
    final days = await appState.tripRepo.listDays(target.id);
    final groups = _buildPreviewGroups(items, days, existing);
    if (!mounted) return;

    final confirmed = await AppSheet.show<bool>(
      context,
      child: _PreviewSheet(groups: groups, total: items.length),
    );
    if (confirmed != true) return;

    // 落库
    final importResult = await appState.photoRepo.importBatch(target.id, items);
    // 导入完成后后台把「城市」升级成「区级地址」（限速，不阻塞界面）
    unawaited(appState.photoRepo.upgradePlacesToDistrict());
    final missing = items
        .where((i) => (i.lat == null || i.lng == null) && !existing.contains(i.hash))
        .length;
    // 时间不在本行程日期范围内的张数：这些会落进「未归入行程日期」分组，
    // 必须明确告知，否则用户以为没导入成功（日志里 dayId=null 就是这种）。
    final outOfRange = items
        .where((i) =>
            i.takenAt != null &&
            !existing.contains(i.hash) &&
            i.takenAt!.isBefore(DateTime.parse(target.startDate)) ||
            (i.takenAt != null &&
                !existing.contains(i.hash) &&
                i.takenAt!.isAfter(DateTime.parse(target.endDate).add(const Duration(days: 1)))))
        .length;
    await appState.reload();
    if (!mounted) return;

    // 不再单独跳「导入结果页」：直接 toast 汇总 + 回到行程页，
    // 少一次跳转，用户立刻看到照片。
    final parts = <String>[];
    if (importResult.inserted > 0) parts.add('已导入 ${importResult.inserted} 张');
    if (importResult.skipped > 0) parts.add('${importResult.skipped} 张已存在');
    if (importResult.failed > 0) parts.add('${importResult.failed} 张读取失败');
    if (missing > 0) parts.add('其中 $missing 张没有位置信息');
    if (outOfRange > 0) {
      parts.add('$outOfRange 张时间不在行程内，已放在「未归入行程日期」');
    }

    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(parts.isEmpty ? '没有可导入的照片' : parts.join(' · ')),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  List<_PreviewGroup> _buildPreviewGroups(
      List<ImportItem> items, List<Day> days, Set<String> existing) {
    final byDay = <String, List<ImportItem>>{};
    final unknown = <ImportItem>[];
    for (final item in items) {
      final dayId = pickDayId(item.takenAt, days);
      if (dayId == null) {
        unknown.add(item);
      } else {
        byDay.putIfAbsent(dayId, () => []).add(item);
      }
    }
    final groups = <_PreviewGroup>[];
    for (final d in days) {
      final list = byDay[d.id] ?? [];
      if (list.isEmpty) continue;
      groups.add(_PreviewGroup(
        label: dayLabel(d.date),
        place: d.place,
        count: list.length,
        existing: list.where((i) => existing.contains(i.hash)).length,
      ));
    }
    if (unknown.isNotEmpty) {
      groups.add(_PreviewGroup(
        label: '时间未知',
        place: '',
        count: unknown.length,
        existing: unknown.where((i) => existing.contains(i.hash)).length,
      ));
    }
    return groups;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: '选择素材',
      subtitle: '选好之后再开始导入',
      actions: [
        HeaderIconButton(
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(Icons.close, color: t2, size: 18),
        ),
      ],
      body: Stack(
        children: [
          Column(
            children: [
              _seg(),
              _srcBar(),
              Expanded(child: _grid()),
            ],
          ),
          if (_processing) _ProcessingOverlay(done: _done, total: _total),
        ],
      ),
      bottomNavigationBar: _foot(),
    );
  }

  /// 原型 .seg：两个大按钮切换来源。
  Widget _seg() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(child: _segBtn('手机相册', true, _pickImages)),
          const SizedBox(width: 8),
          Expanded(
              child: _segBtn(
                  '文件夹', false, () => _toast('文件夹选择待接入'))),
        ],
      ),
    );
  }

  Widget _segBtn(String label, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? accent.withValues(alpha: .08) : panel2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: on ? accent.withValues(alpha: .45) : Colors.transparent),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: fsBody,
                color: on ? accent : t2,
                fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
  }

  Widget _srcBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text('已选 ${_picked.length} 张',
              style: const TextStyle(fontSize: fsBody, color: t2)),
          const Spacer(),
          if (_picked.isNotEmpty)
            TextButton(
              onPressed: _clear,
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('清空',
                  style: TextStyle(fontSize: fsBody, color: t3)),
            ),
          TextButton(
            onPressed: _pickImages,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('选择照片',
                style: TextStyle(fontSize: fsBody, color: accent)),
          ),
        ],
      ),
    );
  }

  Widget _grid() {
    if (_picked.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_photo_alternate_outlined, color: t3, size: 44),
            const SizedBox(height: 12),
            const Text('从手机相册选择照片',
                style: TextStyle(color: t3, fontSize: fsBody)),
            const SizedBox(height: 16),
            PillButton(label: '选择照片', onTap: _pickImages),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: _picked.length,
      itemBuilder: (_, i) {
        final path = _picked[i].$1;
        return GestureDetector(
          onTap: () => _removeAt(i),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.file(File(path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        color: panel2,
                        alignment: Alignment.center,
                        child: const Icon(Icons.image_outlined,
                            color: t3, size: 18))),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: accent),
                  ),
                  child: const Icon(Icons.check,
                      color: Color(0xFF04170F), size: 11),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _foot() {
    final canImport = _picked.isNotEmpty && _target != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      decoration: const BoxDecoration(
        color: panel,
        border: Border(top: BorderSide(color: line)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 第一行：导入到 XX + 更改（原型 .tgtbar）
            Row(
              children: [
                const Text('导入到',
                    style: TextStyle(fontSize: 9, color: t3)),
                const SizedBox(width: 5),
                Flexible(
                  child: GestureDetector(
                    onTap: _chooseTarget,
                    child: Text(
                      _target?.name ?? '无行程',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: fsBody,
                          fontWeight: FontWeight.w600,
                          color: t1),
                    ),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _chooseTarget,
                  child: const Text('更改',
                      style: TextStyle(fontSize: fsBody, color: accent)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 第二行：取消 + 导入 N 项
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(radiusBtn),
                        border: Border.all(color: line),
                      ),
                      child: const Text('取消',
                          style: TextStyle(fontSize: fsBody, color: t2)),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: GestureDetector(
                    onTap: canImport ? _import : null,
                    child: Container(
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(radiusBtn),
                      ),
                      child: Opacity(
                        opacity: canImport ? 1 : .45,
                        child: Text(
                          '导入 ${_picked.length} 项',
                          style: const TextStyle(
                              fontSize: fsBody,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF04170F)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


class _PreviewGroup {
  const _PreviewGroup({
    required this.label,
    required this.place,
    required this.count,
    required this.existing,
  });

  final String label;
  final String place;
  final int count;
  final int existing;
}

class _ProcessingOverlay extends StatelessWidget {
  const _ProcessingOverlay({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF030609).withValues(alpha: .82),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(color: accent, strokeWidth: 3),
            ),
            const SizedBox(height: 18),
            const Text('正在读取素材',
                style: TextStyle(
                    fontSize: fsTitle, fontWeight: FontWeight.w600, color: t1)),
            const SizedBox(height: 8),
            Text(
              '正在读取 $done / $total',
              style: const TextStyle(color: t3, fontSize: fsBody),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSheet extends StatelessWidget {
  const _PreviewSheet({required this.groups, required this.total});

  final List<_PreviewGroup> groups;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('导入预览',
              style: TextStyle(
                  fontSize: fsCardTitle, fontWeight: FontWeight.w600, color: t1)),
          const SizedBox(height: 14),
          ...groups.map(_groupRow),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: line)),
            ),
            child: const Text(
              '缺少拍摄时间的会单独列出，导入后在行程里补',
              style: TextStyle(fontSize: 10, color: t3, height: 1.7),
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: SheetButton(
                    label: '取消',
                    primary: false,
                    onTap: () => Navigator.of(context).pop(false)),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: SheetButton(
                    label: '确认导入 $total 项',
                    primary: true,
                    onTap: () => Navigator.of(context).pop(true)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _groupRow(_PreviewGroup g) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(g.label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: fsBody,
                          fontWeight: FontWeight.w500,
                          color: t1)),
                ),
                if (g.place.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(g.place,
                        style: const TextStyle(fontSize: fsCaption, color: t3)),
                  ),
              ],
            ),
          ),
          Text(
            '${g.count} 张',
            style: TextStyle(
              fontSize: fsCaption,
              color: g.existing > 0 ? accent : t3,
            ),
          ),
          if (g.existing > 0)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('其中 ${g.existing} 张已存在',
                  style: const TextStyle(fontSize: fsCaption, color: t3)),
            ),
        ],
      ),
    );
  }
}



class _TargetSheet extends StatelessWidget {
  const _TargetSheet({required this.trips, required this.current});

  final List<Trip> trips;
  final Trip? current;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('导入到', style: TextStyle(fontSize: fsBody, color: t3)),
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
                                color: t.id == current?.id ? accent : t1)),
                      ),
                      if (t.id == current?.id)
                        const Icon(Icons.check, size: 18, color: accent),
                    ],
                  ),
                ),
              )),
          if (trips.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('还没有行程，先去行程列表新建一个',
                  style: TextStyle(color: t3, fontSize: fsBody)),
            ),
        ],
      ),
    );
  }
}


