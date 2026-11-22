import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 统一页面骨架 + 头部（技术方案 §6.2 红线：页面层禁止自建头部布局）。
///
/// 头部固定 54px：可选的返回按钮 + 标题/副标题 + 右侧操作按钮。
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.titleSize = fsTitle,
    this.onBack,
    this.onTitleTap,
    this.actions = const [],
    required this.body,
    this.bottomNavigationBar,
  });

  final String title;
  final String? subtitle;

  /// 标题字号。默认 fsTitle(15)；没有副标题的页面可以放大，避免头部显空。
  final double titleSize;
  final VoidCallback? onBack;

  /// 标题区域点击（地图页用于切换行程）。
  final VoidCallback? onTitleTap;
  final List<Widget> actions;
  final Widget body;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          // 头部让出系统状态栏（安全区），背景仍铺满到状态栏下方。
          Container(
            color: panel,
            child: SafeArea(
              bottom: false,
              child: _Header(
                  title: title,
                  subtitle: subtitle,
                  titleSize: titleSize,
                  onBack: onBack,
                  onTitleTap: onTitleTap,
                  actions: actions),
            ),
          ),
          Expanded(child: body),
        ],
      ),
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

/// 头部右侧的圆形图标按钮（30×30，圆角边框），统一样式。
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(radiusTag + 1),
        ),
        child: child,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    this.subtitle,
    this.titleSize = fsTitle,
    this.onBack,
    this.onTitleTap,
    required this.actions,
  });

  final String title;
  final String? subtitle;

  /// 标题字号。默认 fsTitle(15)；没有副标题的页面可以放大，避免头部显空。
  final double titleSize;
  final VoidCallback? onBack;
  final VoidCallback? onTitleTap;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: padPage),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: line)),
      ),
      child: Row(
        children: [
          if (onBack != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: HeaderIconButton(
                onTap: onBack!,
                child: const Icon(Icons.chevron_left, size: 18, color: t2),
              ),
            ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTitleTap,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: titleSize,
                              fontWeight: FontWeight.w600,
                              color: t1,
                              height: 1.2),
                        ),
                      ),
                      if (onTitleTap != null)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.expand_more,
                              size: 16, color: t3),
                        ),
                    ],
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: fsSubtitle, color: t3, height: 1.3),
                      ),
                    ),
                ],
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
