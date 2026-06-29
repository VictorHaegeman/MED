import 'package:flutter/material.dart';

import '../theme.dart';
import 'home_screen.dart';
import 'impact_screen.dart';
import 'map_screen.dart';
import 'network_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  // Un navigateur dédié par onglet — les sous-écrans (ResultsScreen,
  // DetailScreen, MapScreen en mode route) sont poussés dans ce navigateur,
  // ce qui conserve la bottom nav bar visible.
  final List<GlobalKey<NavigatorState>> _navKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  final List<Widget> _roots = const [
    HomeScreen(),
    MapScreen(),
    ImpactScreen(),
    NetworkScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          final nav = _navKeys[_index].currentState;
          if (nav != null && nav.canPop()) nav.pop();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            for (int i = 0; i < _roots.length; i++)
              Offstage(
                offstage: _index != i,
                child: _TabNavigator(
                  navigatorKey: _navKeys[i],
                  child: _roots[i],
                ),
              ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.search_rounded),
              label: 'Recherche',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map_rounded),
              label: 'Carte',
            ),
            NavigationDestination(
              icon: Icon(Icons.eco_outlined),
              selectedIcon: Icon(Icons.eco_rounded),
              label: 'Impact',
            ),
            NavigationDestination(
              icon: Icon(Icons.hub_outlined),
              selectedIcon: Icon(Icons.hub_rounded),
              label: 'Réseau',
            ),
          ],
        ),
      ),
    );
  }
}

class _TabNavigator extends StatelessWidget {
  const _TabNavigator({required this.navigatorKey, required this.child});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onGenerateRoute: (settings) => MaterialPageRoute(
        builder: (_) => child,
        settings: settings,
      ),
    );
  }
}
