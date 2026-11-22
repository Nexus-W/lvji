import 'package:flutter/services.dart';

/// 本地配置（腾讯位置服务 Key 等）。
///
/// 读取优先级：
/// 1. 编译参数 `--dart-define=TMAP_KEY=xxx`（不落盘，最安全）
/// 2. 历史兼容：根目录 `.env`（当前不再作为 asset 打包，仅兜底）
///
/// 没配置时保持空字符串，所有调用方都应回退到本地地名表，功能不中断。
class AppConfig {
  AppConfig._();

  static String tmapKey = '';

  static Future<void> load() async {
    if (tmapKey.isNotEmpty) return;

    const fromDefine = String.fromEnvironment('TMAP_KEY');
    if (fromDefine.isNotEmpty) {
      tmapKey = fromDefine;
      return;
    }

    try {
      final text = await rootBundle.loadString('.env');
      for (final line in text.split('\n')) {
        final t = line.trim();
        if (t.startsWith('TMAP_KEY=')) {
          tmapKey = t.substring('TMAP_KEY='.length).trim();
          break;
        }
      }
    } catch (_) {
      // 没有 .env（未配置 Key）→ 保持空
    }
  }
}
