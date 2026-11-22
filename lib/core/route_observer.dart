import 'package:flutter/material.dart';

/// 全局路由观察者。
///
/// 用途：地图页在「被其它页面盖住」时要把地图组件真正移除 ——
/// Android 的 PlatformView（腾讯地图）z-order 不受 Flutter 控制，
/// 不移除的话会盖在导入页/详情页上面。
final routeObserver = RouteObserver<PageRoute<dynamic>>();
