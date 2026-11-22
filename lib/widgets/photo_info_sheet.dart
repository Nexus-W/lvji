import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/extensions.dart';
import '../core/place_table.dart';
import '../core/theme.dart';
import '../data/geocoding.dart';
import '../data/models/photo.dart';
import 'app_sheet.dart';
import '../features/map/map_picker_page.dart';
import 'sheet_button.dart';

/// 照片信息编辑弹层（技术方案 §5.4 / §6.2：唯一入口）。
///
/// 两个入口：大图「修改」→ `PhotoInfoSheet(photo)`；
/// 补救页点一张 → `PhotoInfoSheet(photo, focusMap: true)`。
/// 保存后返回更新后的 [Photo]。
class PhotoInfoSheet extends StatefulWidget {
  const PhotoInfoSheet({super.key, required this.photo, this.focusMap = false});

  final Photo photo;
  final bool focusMap;

  static Future<Photo?> show(
    BuildContext context, {
    required Photo photo,
    bool focusMap = false,
  }) {
    return AppSheet.show<Photo>(
      context,
      // 弹层里有地图（180 高）+ 多个输入行，小屏/键盘弹起时会溢出，必须可滚动。
      child: SingleChildScrollView(
        child: PhotoInfoSheet(photo: photo, focusMap: focusMap),
      ),
    );
  }

  @override
  State<PhotoInfoSheet> createState() => _PhotoInfoSheetState();
}

class _PhotoInfoSheetState extends State<PhotoInfoSheet> {
  DateTime? _takenAt;
  late final TextEditingController _placeCtrl;
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    final p = widget.photo;
    _takenAt = p.takenAt != null ? DateTime.tryParse(p.takenAt!) : null;
    _placeCtrl = TextEditingController(text: p.place ?? '');
    _lat = p.lat;
    _lng = p.lng;
  }

  @override
  void dispose() {
    _placeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTakenAt() async {
    final initial = _takenAt ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    setState(() {
      _takenAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  bool _placeEdited = false;
  // 地名是「联网解析出坐标」得到的（而非点地图/原有坐标），才需要反查校验
  bool _geoFromName = false;

  void _onMapTap(double lat, double lng) {
    setState(() {
      _lat = lat;
      _lng = lng;
      // 先给即时反馈（本地最近城市），再联网换精确地址（腾讯位置服务）。
      if (!_placeEdited) _placeCtrl.text = nearestPlace(lat, lng);
    });
    if (_placeEdited) return;
    Geocoding.reverse(lat, lng).then((name) {
      if (!mounted || name == null || name.isEmpty) return;
      if (_placeEdited || _lat != lat || _lng != lng) return;
      setState(() => _placeCtrl.text = name);
    });
  }

  /// 全屏地图选点（不再把地图塞进底部弹层：PlatformView 关闭后容易残留在屏幕上）。
  Future<void> _pickOnMap() async {
    final r = await MapPickerPage.open(context, lat: _lat, lng: _lng);
    if (r == null || !mounted) return;
    _onMapTap(r.$1, r.$2);
  }

  Future<void> _save() async {
    final repo = context.read<AppState>().photoRepo;
    final place = _placeCtrl.text.trim();
    try {
      // 只填了地名、没点地图：用本地地名表自动定位。
      // 地图页 / 足迹页只认坐标（lat/lng），没有坐标的照片在那儿看不到。
      // 地名改了（或原本没坐标）→ 必须重新解析坐标，
      // 否则「改了地址但地图点位不变」（旧坐标被保留）。
      final needGeocode = place.isNotEmpty &&
          (_placeEdited || _lat == null || _lng == null);
      if (needGeocode) {
        // 先本地表（离线可用），查不到再联网做正向地理编码。
        var coords = placeToLatLng(place);
        if (coords.$1 == null || coords.$2 == null) {
          final remote = await Geocoding.forward(place);
          if (remote != null) coords = (remote.$1, remote.$2);
        }
        if (coords.$1 != null && coords.$2 != null) {
          _lat = coords.$1;
          _lng = coords.$2;
          _geoFromName = true;
        } else if (_lat == null || _lng == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('未识别「$place」的坐标，请在地图上点选位置')),
            );
          }
          return; // 不关闭弹层，让用户直接点地图
        }
      }
      await repo.setTakenAt(widget.photo.id, _takenAt);
      // 坐标只在用户真的改过时才写。否则「只改时间」会把已有坐标清空。
      if (widget.photo.lat != _lat || widget.photo.lng != _lng) {
        await repo.setLocation(widget.photo.id, _lat, _lng);
      }
      await repo.setPlace(widget.photo.id, place.isEmpty ? null : place);
      // 只有「地名联网解析出坐标」时才反查校验（避免覆盖用户手动输入的地名，
      // 也避免网络请求拖慢/阻塞保存导致看起来「保存失败」）。
      if (_geoFromName && place.isNotEmpty && _lat != null && _lng != null) {
        unawaited(Geocoding.reverse(_lat!, _lng!).then((real) async {
          if (real == null || real.isEmpty) return;
          if (real.contains(place) || place.contains(real)) return;
          await repo.setPlace(widget.photo.id, real);
        }).catchError((_) {}));
      }
      final updated = await repo.find(widget.photo.id);
      // 改完地点/时间后刷新全局状态（rev +1），地图页/精选页/足迹页会自动重载
      if (mounted) {
        await context.read<AppState>().reload();
      }
      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('照片信息',
              style: TextStyle(
                  fontSize: fsCardTitle,
                  fontWeight: FontWeight.w600,
                  color: t1)),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _row(
                    label: '拍摄时间',
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _pickTakenAt,
                            child: Text(
                              _takenAt == null ? '未设置' : ymdHm(_takenAt!),
                              style: TextStyle(
                                  fontSize: fsBody,
                                  color: _takenAt == null ? t3 : t1),
                            ),
                          ),
                        ),
                        if (_takenAt != null)
                          GestureDetector(
                            onTap: () => setState(() => _takenAt = null),
                            child: const Icon(Icons.close,
                                size: 16, color: t3),
                          ),
                      ],
                    ),
                  ),
                  if (_lat != null && _lng != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 60, bottom: 8),
                      child: Text(
                        '坐标 ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                        style: const TextStyle(fontSize: 10, color: t3),
                      ),
                    ),
                  _row(
                    label: '地点',
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _placeCtrl,
                            onChanged: (_) => _placeEdited = true,
                            style: const TextStyle(color: t1, fontSize: fsBody),
                            decoration: const InputDecoration(
                              hintText: '输入或在地图上点选',
                              hintStyle: TextStyle(color: t3),
                              isDense: true,
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _pickOnMap,
                          child: const Text(
                            '在地图上点选',
                            style: TextStyle(
                                fontSize: fsCaption, color: accent),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
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
                    label: '保存', primary: true, onTap: _save),
              ),
            ],
          ),
        ],
      ),
    );
  }



  Widget _row({required String label, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(label,
                style: const TextStyle(fontSize: fsBody, color: t3)),
          ),
          Expanded(
            child: Container(
              height: 40,
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
