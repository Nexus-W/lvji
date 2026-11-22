import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/extensions.dart';
import '../core/theme.dart';
import '../data/models/trip.dart';
import 'app_sheet.dart';
import 'confirm_dialog.dart';
import 'sheet_button.dart';

/// 行程 ⋯ 菜单（分享 / 改名 / 改起止日期 / 删除），返回动作 key。
/// 抽成公共组件，地图页、精选页共用，避免各写一套。
Future<String?> showTripMenu(BuildContext context) {
  return AppSheet.show<String>(context, child: const _TripMenuSheet());
}

/// 改名弹层。
Future<void> showRenameTripSheet(BuildContext context, Trip trip) async {
  final name = await AppSheet.show<String>(
    context,
    child: _RenameSheet(initial: trip.name),
  );
  if (name == null || name.trim().isEmpty || !context.mounted) return;
  final appState = context.read<AppState>();
  await appState.tripRepo.rename(trip.id, name.trim());
  await appState.reload();
}

/// 改起止日期弹层（保留原 day id，多余天删除、缺的天补齐）。
Future<void> showTripDatesSheet(BuildContext context, Trip trip) async {
  final data = await AppSheet.show<_DatesData>(
    context,
    child: _DatesSheet(
      start: DateTime.parse(trip.startDate),
      end: DateTime.parse(trip.endDate),
    ),
  );
  if (data == null || !context.mounted) return;
  final appState = context.read<AppState>();
  await appState.tripRepo.updateDates(trip.id, data.start, data.end);
  await appState.reload();
}

/// 删除行程（物理删，含确认弹窗）。返回是否已删除。
Future<bool> confirmDeleteTrip(BuildContext context, Trip trip) async {
  final ok = await ConfirmDialog.show(
    context,
    title: '删除这个行程？',
    desc: '行程内的照片索引会一并删除\n原图仍在系统相册',
    okText: '删除',
  );
  if (!ok || !context.mounted) return false;
  final appState = context.read<AppState>();
  await appState.tripRepo.delete(trip.id);
  await appState.reload();
  return true;
}

class _TripMenuSheet extends StatelessWidget {
  const _TripMenuSheet();

  @override
  Widget build(BuildContext context) {
    Widget item(String key, String label, IconData icon, {Color? color}) {
      return GestureDetector(
        onTap: () => Navigator.of(context).pop(key),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color ?? t2),
              const SizedBox(width: 12),
              Text(label,
                  style: TextStyle(
                      fontSize: fsCardTitle,
                      fontWeight: FontWeight.w600,
                      color: color ?? t1)),
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
          item('share', '分享精选九宫格', Icons.grid_view_outlined),
          item('rename', '改名', Icons.edit_outlined),
          item('dates', '改起止日期', Icons.date_range_outlined),
          item('delete', '删除行程', Icons.delete_outline, color: danger),
        ],
      ),
    );
  }
}

class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.initial});

  final String initial;

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
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
          const Text('改名',
              style: TextStyle(
                  fontSize: fsCardTitle,
                  fontWeight: FontWeight.w600,
                  color: t1)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            style: const TextStyle(color: t1, fontSize: fsBody),
            decoration: InputDecoration(
              filled: true,
              fillColor: panel,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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

class _DatesData {
  const _DatesData({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

class _DatesSheet extends StatefulWidget {
  const _DatesSheet({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  @override
  State<_DatesSheet> createState() => _DatesSheetState();
}

class _DatesSheetState extends State<_DatesSheet> {
  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    _start = widget.start;
    _end = widget.end;
  }

  /// 一次选完起止，避免两次弹窗和先后颠倒。
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

  @override
  Widget build(BuildContext context) {
    Widget row(String label, DateTime value, VoidCallback onTap,
        {DateTime? end}) {
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
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: panel,
                    borderRadius: BorderRadius.circular(radiusTag + 1),
                    border: Border.all(color: line),
                  ),
                  child: Row(
                    children: [
                      Text(
                          end == null
                              ? ymd(value)
                              : '${ymd(value)}  —  ${ymd(end)}',
                          style: const TextStyle(color: t1, fontSize: fsBody)),
                      const Spacer(),
                      const Icon(Icons.calendar_today_outlined,
                          size: 15, color: t3),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('改起止日期',
              style: TextStyle(
                  fontSize: fsCardTitle,
                  fontWeight: FontWeight.w600,
                  color: t1)),
          const SizedBox(height: 14),
          row('日期', _start, _pickRange, end: _end),
          const SizedBox(height: 6),
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
                    onTap: () {
                      if (_end.isBefore(_start)) return;
                      Navigator.of(context)
                          .pop(_DatesData(start: _start, end: _end));
                    }),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


