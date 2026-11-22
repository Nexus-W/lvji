import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../data/models/photo.dart';

/// 最近删除（回收站）。
///
/// 删除照片是软删（只写 `deleted_at`），这里把它们列出来：
/// - 点缩略图 → 恢复
/// - 右上角「清空」→ 物理删除记录 + 私有目录文件
///
/// 启动时 `cleanupRecycle(7)` 会自动清掉超过 7 天的，所以这里不需要额外计时。
class RecycleBinPage extends StatefulWidget {
  const RecycleBinPage({super.key});

  @override
  State<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends State<RecycleBinPage> {
  List<Photo> _photos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await context.read<AppState>().photoRepo.deletedPhotos();
    if (!mounted) return;
    setState(() {
      _photos = list;
      _loading = false;
    });
  }

  Future<void> _restore(Photo p) async {
    await context.read<AppState>().photoRepo.restoreDeleted([p.id]);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已恢复，回到原行程'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _purgeAll() async {
    if (_photos.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: panel,
        title: const Text('清空回收站？', style: TextStyle(color: t1)),
        content: Text(
          '这 ${_photos.length} 张会被彻底删除（原图在系统相册里不受影响）。',
          style: const TextStyle(color: t3, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: t3)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空', style: TextStyle(color: danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<AppState>().photoRepo
        .purgeDeleted(_photos.map((p) => p.id).toList());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        title: const Text('最近删除'),
        actions: [
          if (_photos.isNotEmpty)
            TextButton(
              onPressed: _purgeAll,
              child: const Text('清空', style: TextStyle(color: danger)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: accent))
          : _photos.isEmpty
              ? const Center(
                  child: Text('回收站是空的',
                      style: TextStyle(color: t3, fontSize: fsBody)),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: .78,
                  ),
                  itemCount: _photos.length,
                  itemBuilder: (_, i) {
                    final p = _photos[i];
                    return GestureDetector(
                      onTap: () => _restore(p),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(
                                    File(p.uri),
                                    fit: BoxFit.cover,
                                    cacheWidth: 300,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: panel2,
                                      child: const Icon(Icons.broken_image,
                                          color: t3, size: 20),
                                    ),
                                  ),
                                  // 恢复角标
                                  Positioned(
                                    right: 4,
                                    top: 4,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Icon(Icons.restore,
                                          size: 14, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            shortPlace(p.place),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 9, color: t3),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
