import 'package:flutter/material.dart';

import '../app_state.dart';
import '../auth_controller.dart';
import '../models/pothole.dart';
import '../scan_controller.dart';
import '../theme.dart';
import 'alerts_screen.dart';
import 'dashboard_screen.dart';
import 'home_screen.dart';
import 'map_screen.dart';
import 'pothole_detail_screen.dart';
import 'reports_screen.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';

enum AppTab { home, map, scan, alerts, dashboard }

/// How a screen asks to go somewhere else in the app.
abstract class AppNavigator {
  void openTab(AppTab tab);
  void openSettings();
  void openReports();
  void openPothole(Pothole pothole);

  /// Switches to the map with [potholeId] selected.
  void openOnMap(int potholeId);
}

/// The five tabs and the bar that switches between them.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.auth, required this.state, required this.scan});

  final AuthController auth;
  final AppState state;
  final ScanController scan;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> implements AppNavigator {
  AppTab _tab = AppTab.home;
  int? _mapSelection;

  @override
  void openTab(AppTab tab) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => _tab = tab);
  }

  @override
  void openSettings() => _push(SettingsScreen(auth: widget.auth, state: widget.state));

  @override
  void openReports() => _push(ReportsScreen(state: widget.state, nav: this));

  @override
  void openPothole(Pothole pothole) => _push(PotholeDetailScreen(pothole: pothole, state: widget.state));

  @override
  void openOnMap(int potholeId) {
    _mapSelection = potholeId;
    openTab(AppTab.map);
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: widget.state,
          builder: (context, _) => switch (_tab) {
            AppTab.home => HomeScreen(state: widget.state, nav: this),
            AppTab.map => MapScreen(
                // A new selection from elsewhere rebuilds the map centred on it.
                key: ValueKey(_mapSelection),
                state: widget.state,
                nav: this,
                initialSelection: _mapSelection,
              ),
            AppTab.scan => ScanScreen(state: widget.state, scan: widget.scan, nav: this),
            AppTab.alerts => AlertsScreen(state: widget.state, nav: this),
            AppTab.dashboard => DashboardScreen(state: widget.state, nav: this),
          },
        ),
      ),
      bottomNavigationBar: _TabBar(current: _tab, onSelect: openTab),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.current, required this.onSelect});

  final AppTab current;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget tab(AppTab tab, IconData icon, String label) {
      final selected = tab == current;
      final color = selected ? c.primary : c.muted;
      return Expanded(
        child: InkWell(
          onTap: () => onSelect(tab),
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(color: c.card, border: Border(top: BorderSide(color: c.border))),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tab(AppTab.home, Icons.home_outlined, 'Home'),
            tab(AppTab.map, Icons.map_outlined, 'Map'),
            Expanded(
              // The scan button rises out of the bar.
              child: Transform.translate(
                offset: const Offset(0, -20),
                child: Center(
                  // Without this the button's column would stretch the bar to full height.
                  heightFactor: 1,
                  child: Tooltip(
                    message: 'Scan road',
                    // A ring in the bar's colour separates the button from the page behind it.
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: c.card,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: c.primary.withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Material(
                        color: c.primary,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => onSelect(AppTab.scan),
                          child: const SizedBox.square(
                            dimension: 54,
                            child: Icon(Icons.photo_camera_outlined, color: Colors.white, size: 24),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            tab(AppTab.alerts, Icons.notifications_none_rounded, 'Alerts'),
            tab(AppTab.dashboard, Icons.bar_chart_rounded, 'Dashboard'),
          ],
        ),
      ),
    );
  }
}
