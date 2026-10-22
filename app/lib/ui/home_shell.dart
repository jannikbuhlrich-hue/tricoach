import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'screens/calendar_screen.dart';
import 'screens/log_screen.dart';
import 'screens/progress_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/today_screen.dart';
import 'widgets.dart';

/// Navigation: unten auf dem Handy, links auf Tablet/PC.
/// Tabs wie im Plan: Heute · Kalender · Eintragen · Fortschritt · Einstellungen
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  AppState? _app;

  static const _pages = [TodayScreen(), CalendarScreen(), SizedBox.shrink(), ProgressScreen(), SettingsScreen()];

  static const _dest = [
    (Icons.today_outlined, Icons.today_rounded, 'Heute'),
    (Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'Kalender'),
    (Icons.add_circle_outline_rounded, Icons.add_circle_rounded, 'Eintragen'),
    (Icons.insights_outlined, Icons.insights_rounded, 'Fortschritt'),
    (Icons.settings_outlined, Icons.settings_rounded, 'Einstellungen'),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    if (_app != app) {
      _app?.removeListener(_onApp);
      _app = app..addListener(_onApp);
    }
  }

  @override
  void dispose() {
    _app?.removeListener(_onApp);
    super.dispose();
  }

  /// Meldungen aus dem App-Zustand (z. B. „2 neue Einheiten von deiner Uhr“) anzeigen
  void _onApp() {
    final m = _app?.message;
    if (m != null && mounted) {
      _app!.message = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showMsg(context, m);
      });
    }
  }

  void _select(int i) {
    if (i == 2) {
      openLog(context);
      return;
    }
    setState(() => index = i);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final body = IndexedStack(index: index, children: _pages);
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: _select,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('TriCoach', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Theme.of(context).colorScheme.primary)),
            ),
            destinations: [for (final d in _dest) NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3))],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 980), child: body))),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: _select,
        destinations: [for (final d in _dest) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3)],
      ),
    );
  }
}
