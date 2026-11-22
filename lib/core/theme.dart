import 'package:flutter/material.dart';

// 颜色严格取自原型 proto.css（原设置）。三色标记语义固定：
// 金 = 行程封面 / 绿 = 已加入精选 / 紫 = 写过备注。
const Color bg = Color(0xFF05080B); // 页面底
const Color panel = Color(0xFF0F141B); // 卡片
const Color panel2 = Color(0xFF141A23); // 次级卡片/输入框
const Color line = Color(0xFF232C39); // 分割线
const Color t1 = Color(0xFFE9EEF6); // 主文字
const Color t2 = Color(0xFF8C97A9); // 次文字
const Color t3 = Color(0xFF5C6675); // 辅助文字
const Color accent = Color(0xFF3DDC97); // 强调（精选、按钮）
const Color gold = Color(0xFFFFB454); // 封面标记（原型 .kc）
const Color violet = Color(0xFFA78BFA); // 备注标记（原型 .kn）
const Color danger = Color(0xFFFF7A8A); // 删除
const Color raised = Color(0xFF23303E); // 抬升面：分段控件滑块 / 选中底

// 字号（原型 proto.css / scenes.css）。
const double fsTitle = 15; // 页面标题 w600
const double fsSubtitle = 9; // 页面副标题 w400
const double fsCardTitle = 14; // 卡片标题 w600
const double fsBody = 14; // 正文 w400
const double fsCaption = 11; // 辅助信息 w400

// ——— 间距：全工程只认这一套 ———
// 任何页面/组件都不要写裸数字，从这里取。
const double padPage = 16; // 页面左右留白（所有顶栏、列表、统计行）
const double gapBlock = 16; // 区块之间的垂直间距（筛选栏→内容、卡片→卡片组）
const double gapCard = 12; // 卡片之间、列表项之间的间距
const double padCard = 12; // 卡片内边距
const double gapInner = 8; // 组件内部（图标与文字、按钮之间）

// ——— 圆角：分三档，不出现直角 ———
const double radiusCard = 15; // 卡片、列表行、输入框容器
const double radiusBtn = 12; // 按钮
const double radiusTag = 8; // 小标签、封面缩略图

/// 全局主题。
ThemeData buildTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      surface: panel,
      error: danger,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: panel,
      foregroundColor: t1,
      elevation: 0,
      centerTitle: false,
    ),
    // 日期选择器：Material 默认标题 28px、圆角 28、底是紫灰调，
    // 和 App 的 14px 正文 / 15 圆角 / 冷蓝黑完全不在一个尺度。
    // 这里一次性统一，4 个入口（建行程、改行程、照片时间、补位置）全部生效。
    datePickerTheme: DatePickerThemeData(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      headerBackgroundColor: panel2,
      headerForegroundColor: t1,
      headerHelpStyle: const TextStyle(fontSize: fsCaption, color: t3),
      headerHeadlineStyle: const TextStyle(
          fontSize: fsTitle, fontWeight: FontWeight.w600, color: t1),
      weekdayStyle: const TextStyle(fontSize: fsCaption, color: t3),
      dayStyle: const TextStyle(fontSize: fsBody, color: t1),
      todayForegroundColor: const WidgetStatePropertyAll(accent),
      todayBorder: const BorderSide(color: accent, width: 1),
      dayOverlayColor: WidgetStatePropertyAll(accent.withValues(alpha: .12)),
      rangeSelectionBackgroundColor: accent.withValues(alpha: .14),
      rangePickerBackgroundColor: panel,
      rangePickerSurfaceTintColor: Colors.transparent,
      rangePickerElevation: 0,
      rangePickerShape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      rangePickerHeaderBackgroundColor: panel2,
      rangePickerHeaderForegroundColor: t1,
      rangePickerHeaderHelpStyle: const TextStyle(fontSize: fsCaption, color: t3),
      rangePickerHeaderHeadlineStyle: const TextStyle(
          fontSize: fsTitle, fontWeight: FontWeight.w600, color: t1),
    ),
    // 弹窗（含日期选择器）统一圆角
    dialogTheme: DialogThemeData(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    // 所有文字按钮默认用强调色
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: const TextStyle(fontSize: fsBody, fontWeight: FontWeight.w500),
      ),
    ),
  );
}
