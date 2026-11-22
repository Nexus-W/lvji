import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 统一确认弹窗（技术方案 §6.2 红线：页面层禁止裸写 `showDialog`）。
/// 用于删除等破坏性操作，文案须说清后果（附录 B）。
class ConfirmDialog {
  const ConfirmDialog._();

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String desc,
    String okText = '确定',
    String cancelText = '取消',
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _ConfirmDialog(
        title: title,
        desc: desc,
        okText: okText,
        cancelText: cancelText,
      ),
    );
    return ok ?? false;
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.desc,
    required this.okText,
    required this.cancelText,
  });

  final String title;
  final String desc;
  final String okText;
  final String cancelText;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 270),
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
        decoration: BoxDecoration(
          color: panel2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: t1)),
            const SizedBox(height: 8),
            Text(desc,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 11, color: t3, height: 1.7)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _btn(cancelText, onTap: () => Navigator.of(context).pop(false)),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _btn(okText,
                      isDanger: true, onTap: () => Navigator.of(context).pop(true)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn(String label, {VoidCallback? onTap, bool isDanger = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDanger ? danger.withValues(alpha: .14) : Colors.transparent,
          borderRadius: BorderRadius.circular(radiusBtn),
          border: Border.all(
              color: isDanger ? danger.withValues(alpha: .5) : line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: fsBody,
            fontWeight: isDanger ? FontWeight.w600 : FontWeight.w400,
            color: isDanger ? danger : t2,
          ),
        ),
      ),
    );
  }
}
