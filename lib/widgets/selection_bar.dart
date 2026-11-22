import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 多选工具条上的一个动作。
class SelectionAction {
  final String label;
  final VoidCallback onTap;
  final bool isDanger;

  const SelectionAction(this.label, this.onTap, {this.isDanger = false});
}

/// 通用的多选底部工具条。
///
/// 地图页和精选页原来的 `_SelectBar` 除了按钮列表完全一样（同样的高度、
/// 同样的圆角、同样的「已选 N 张」），这里抽出一份，两边只传动作列表。
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.count,
    required this.actions,
    required this.onCancel,
    this.onAll,
  });

  final int count;
  final List<SelectionAction> actions;
  final VoidCallback onCancel;

  /// 传 null 则不显示「全选」。
  final VoidCallback? onAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        color: panel,
        border: Border(top: BorderSide(color: line)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Text('已选 $count 张',
                style: const TextStyle(fontSize: fsBody, color: t2)),
            const Spacer(),
            if (onAll != null) ...[
              _btn('全选', onAll!),
              const SizedBox(width: 8),
            ],
            for (final a in actions) ...[
              _btn(a.label, a.onTap, isDanger: a.isDanger),
              const SizedBox(width: 8),
            ],
            _btn('取消', onCancel),
          ],
        ),
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap, {bool isDanger = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDanger ? danger.withValues(alpha: .14) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: isDanger ? danger.withValues(alpha: .5) : line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: fsCaption,
            fontWeight: FontWeight.w600,
            color: isDanger ? danger : t2,
          ),
        ),
      ),
    );
  }
}
