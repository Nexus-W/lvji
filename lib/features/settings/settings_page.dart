import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../data/backup.dart';
import '../year/year_summary.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/confirm_dialog.dart';

/// 设置页（技术方案 §1.3：数据占用、清理缓存、关于）。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.showBack = true});

  /// tab 内显示时不带返回按钮。
  final bool showBack;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _photoCount = 0;
  String _sizeText = '计算中…';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final appState = context.read<AppState>();
    final uris = await appState.photoRepo.allUris();
    final docs = await getApplicationDocumentsDirectory();
    final importDir = Directory(p.join(docs.path, 'imports'));
    var size = 0;
    if (await importDir.exists()) {
      await for (final f in importDir.list(recursive: true)) {
        if (f is File) {
          try {
            size += await f.length();
          } catch (_) {}
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _photoCount = uris.length;
      _sizeText = _fmtSize(size);
    });
  }

  Future<void> _cleanCache() async {
    final ok = await ConfirmDialog.show(
      context,
      title: '清理缓存？',
      desc: '删除未被引用的临时文件\n不影响你的照片',
      okText: '清理',
    );
    if (!ok || !mounted) return;
    final appState = context.read<AppState>();
    final uris = await appState.photoRepo.allUris();
    final used = uris.map((u) => p.basename(u)).toSet();
    final docs = await getApplicationDocumentsDirectory();
    final importDir = Directory(p.join(docs.path, 'imports'));
    var cleaned = 0;
    if (await importDir.exists()) {
      await for (final f in importDir.list()) {
        if (f is File && !used.contains(p.basename(f.path))) {
          try {
            await f.delete();
            cleaned++;
          } catch (_) {}
        }
      }
    }
    if (mounted) _toast('已清理 $cleaned 个缓存文件');
    await _load();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: '设置',
      subtitle: '数据占用 · 关于旅迹',
      onBack: widget.showBack ? () => Navigator.of(context).pop() : null,
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _section('存储'),
          _row(Icons.photo_library_outlined, '数据占用',
              '${fmtNum(_photoCount)} 张照片 · $_sizeText'),
          _row(Icons.cleaning_services_outlined, '清理缓存',
              '删除未被引用的临时文件', onTap: _cleanCache),
          _row(Icons.restore_from_trash_outlined, '最近删除',
              '7 天内删除的照片可以恢复',
              onTap: () =>
                  Navigator.of(context).pushNamed('/settings/recycle')),
          _row(Icons.ios_share, '导出数据',
              '打包数据库与照片，换机或误删后可恢复',
              onTap: _exportData),
          _row(Icons.unarchive_outlined, '导入备份',
              '从 .zip 恢复：会用备份内容覆盖当前数据',
              onTap: _importBackup),
          _section('关于'),
          _row(Icons.info_outline, '旅迹', 'V1.0.70 · 本地旅行相册',
              onTap: _showAbout,
              onLongPress: _previewYearSummary,
              showArrow: false),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Text(
              '所有数据只保存在本机',
              textAlign: TextAlign.center,
              style: TextStyle(color: t3, fontSize: fsCaption, height: 1.9),
            ),
          ),
        ],
      ),
    );
  }

  /// 从备份 zip 恢复。会覆盖当前数据，所以先备份、再二次确认、再关库。
  Future<void> _importBackup() async {
    final action = await ConfirmDialog.show(
      context,
      title: '导入备份？',
      desc: '会读取你选择的 .zip，'
          '并用里面的数据**覆盖**当前所有行程与照片。\n\n'
          '恢复完成后需要重启 App 才能看到结果。',
      okText: '选择备份文件',
    );
    if (!action || !mounted) return;

    try {
      final bytes = await const MethodChannel('luji/exif')
          .invokeMethod<Uint8List>('pickBackup');
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('已取消')));
        }
        return;
      }
      if (!mounted) return;

      final ok = await ConfirmDialog.show(
        context,
        title: '确认覆盖？',
        desc: '文件名已选好，大小 ${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB。\n\n'
            '当前数据会被备份内容替换，此操作不可撤销。',
        okText: '开始恢复',
      );
      if (!ok || !mounted) return;

      final appState = context.read<AppState>();
      final docs = await getApplicationDocumentsDirectory();

      // 关库 → 覆盖 → 提示重启
      await appState.closeDb();
      final result = await BackupRestore.restore(
        zipBytes: bytes,
        dbPath: p.join(docs.path, 'luji.db'),
        photosDir: p.join(docs.path, 'imports'),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: panel,
          title: const Text('恢复完成',
              style: TextStyle(color: t1, fontSize: fsCardTitle)),
          content: Text(
            '已还原 ${result.photoFiles} 个照片文件。\n\n'
            '请彻底关闭 App 后重新打开（从最近任务里划掉），\n'
            '否则界面显示的还是旧数据。',
            style: const TextStyle(color: t2, fontSize: fsBody, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了', style: TextStyle(color: accent)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('恢复失败：$e')));
    }
  }

  /// 估算导出体积（数据库 + imports 目录），返回字节数。
  Future<int> _estimateBackupBytes() async {
    final docs = await getApplicationDocumentsDirectory();
    var total = 0;
    final db = File(p.join(docs.path, 'luji.db'));
    if (await db.exists()) total += await db.length();
    final dir = Directory(p.join(docs.path, 'imports'));
    if (await dir.exists()) {
      await for (final f in dir.list(recursive: true, followLinks: false)) {
        if (f is File) total += await f.length();
      }
    }
    return total;
  }

  /// 导出全部数据（数据库 + 照片），调起系统分享。
  Future<void> _exportData() async {
    try {
      // ① 先算体积与耗时，给用户一个明确预期
      final bytes = await _estimateBackupBytes();
      final mb = bytes / 1024 / 1024;
      final seconds = (mb / 8).ceil().clamp(1, 300); // 约 8MB/s
      if (!mounted) return;

      // ② 二次确认：说清体积与耗时，然后**直接让用户选保存位置**
      final ok = await ConfirmDialog.show(
        context,
        title: '导出备份到本地？',
        desc: '内容：数据库 + 所有照片副本\n'
            '大小：约 ${mb.toStringAsFixed(1)} MB\n'
            '耗时：约 $seconds 秒\n\n'
            '下一步会打开系统文件选择器，\n'
            '由你决定存到哪个文件夹。',
        okText: '选择保存位置',
      );
      if (!ok || !mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('正在打包 $mb MB，请稍候…'),
          duration: Duration(seconds: seconds + 3),
        ),
      );
      final docs = await getApplicationDocumentsDirectory();
      final tempDir = await getTemporaryDirectory();

      // 只保存到本地，不再走分享面板
      final saved = await BackupService.exportToChosenFolder(
        dbPath: p.join(docs.path, 'luji.db'),
        photosDir: p.join(docs.path, 'imports'),
        tempDir: tempDir,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(saved ? '备份已保存到你选择的位置' : '已取消保存')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  /// 隐藏入口：长按「旅迹」预览年度总结（不写标记，不影响 12/31 自动弹）。
  Future<void> _previewYearSummary() async {
    final appState = context.read<AppState>();
    final year = DateTime.now().year;
    final stats = await appState.tripRepo.yearStats(year);
    if (!mounted) return;
    if (stats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$year 年还没有照片')));
      return;
    }
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => YearSummaryPage(stats: stats)));
  }

  /// 「关于」：版本号 + 一句话说明。
  Future<void> _showAbout() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: panel,
        title: const Text('旅迹  V1.0.70',
            style: TextStyle(color: t1, fontSize: fsCardTitle)),
        content: const Text(
          '一次只属于你的旅行记录。\n\n'
          '照片、地点、时间都留在本机，不上传云端，也不用注册账号。\n\n'
          '开发者：Aeon',
          style: TextStyle(color: t3, height: 1.9, fontSize: fsBody),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('好', style: TextStyle(color: accent)),
          ),
        ],
      ),
    );
  }

  Widget _section(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Text(label,
          style: const TextStyle(fontSize: fsBody, color: t3)),
    );
  }

  Widget _row(IconData icon, String title, String subtitle,
      {VoidCallback? onTap,
      VoidCallback? onLongPress,
      bool showArrow = true}) {
    // InkWell + 撑满宽度：和「新建」弹层一致，整行都是热区
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: double.infinity,
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: t2),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: fsBody,
                          fontWeight: FontWeight.w500,
                          color: t1)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(fontSize: fsCaption, color: t3)),
                ],
              ),
            ),
            if (onTap != null && showArrow)
              const Icon(Icons.chevron_right, size: 18, color: t3),
          ],
        ),
      ),
    );
  }
}

String _fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
