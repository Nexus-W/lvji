import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'core/route_observer.dart';
import 'core/theme.dart';
import 'features/footprint/footprint_page.dart';
import 'features/import/import_page.dart';
import 'features/map/trip_map_page.dart';
import 'features/remedy/remedy_page.dart';
import 'features/settings/recycle_bin_page.dart';
import 'features/settings/settings_page.dart';
import 'features/share/share_page.dart';
import 'features/trip_detail/featured_page.dart';
import 'features/trips/trips_page.dart';

/// MaterialApp + 主题 + 路由入口。
class LujiApp extends StatelessWidget {
  const LujiApp({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: appState,
      child: MaterialApp(
        title: '旅迹',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const HomeShell(),
        navigatorObservers: [routeObserver],
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case '/trip/featured':
              return MaterialPageRoute(
                  builder: (_) =>
                      FeaturedPage(tripId: settings.arguments as String));
            case '/trip/map':
              return MaterialPageRoute(
                  builder: (_) =>
                      TripMapPage(tripId: settings.arguments as String));
            case '/trip/remedy':
              return MaterialPageRoute(
                  builder: (_) => RemedyPage(
                      tripId: settings.arguments as String?));
            case '/share':
              return MaterialPageRoute(
                  builder: (_) =>
                      SharePage(tripId: settings.arguments as String));
            case '/settings/recycle':
              return MaterialPageRoute(
                  builder: (_) => const RecycleBinPage());
            case '/settings':
              return MaterialPageRoute(builder: (_) => const SettingsPage());
            case '/import':
              return MaterialPageRoute(
                  builder: (_) =>
                      ImportPage(tripId: settings.arguments as String?));
          }
          return null;
        },
      ),
    );
  }
}

/// 底部导航壳：只有两个 tab（行程 / 足迹），技术方案 §7.4。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: IndexedStack(
        index: _index,
        children: const [
          TripsPage(),
          FootprintPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        backgroundColor: const Color(0xFF0A0E13),
        selectedItemColor: accent,
        unselectedItemColor: t3,
        selectedFontSize: 10,
        unselectedFontSize: 10,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_outlined, size: 20), label: '行程'),
          BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined, size: 20), label: '地图'),
        ],
      ),
    );
  }
}
