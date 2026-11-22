import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 统一底部弹层（技术方案 §6.2 红线：页面层禁止裸写 `showModalBottomSheet` 的壳，
/// 一律走这里，保证所有弹层圆角/背景一致）。
class AppSheet {
  const AppSheet._();

  static Future<T?> show<T>(BuildContext context, {required Widget child}) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: panel2,
      barrierColor: Colors.black54,
      isScrollControlled: true,
      // 禁用手势下拉关闭：底部弹层默认的「下滑关闭」会抢走地图的
      // 单指拖动 / 双指缩放手势（补位置页放大后就再也缩不回来）。
      // 关闭仍可通过点遮罩或「取消」按钮完成。
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      // 输入法弹起时让内容整体上移，避免挡住输入框。
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(top: false, child: child),
      ),
    );
  }
}
