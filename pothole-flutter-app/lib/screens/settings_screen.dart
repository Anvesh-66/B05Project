import 'package:flutter/material.dart';

import '../app_state.dart';
import '../auth_controller.dart';
import '../models/pothole.dart';
import '../services/location.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/background_alerts_settings.dart';

/// Alert and display preferences, the signed-in account, and about the project.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.auth, required this.state});

  final AuthController auth;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PageHeader('Settings'),
      body: ListenableBuilder(
        listenable: Listenable.merge([state, auth]),
        builder: (context, _) {
          final c = context.colors;
          final user = auth.user;
          final problem = state.locationProblem;
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('Preferences', style: context.text.titleMedium),
              ),
              _SettingRow(
                icon: Icons.notifications_active_outlined,
                title: 'Nearby pothole alerts',
                detail: 'Notification and vibration when a pothole is close',
                trailing: Switch(value: state.alertsEnabled, onChanged: state.setAlertsEnabled),
              ),
              _SettingRow(
                icon: Icons.radar_rounded,
                title: 'Alert radius',
                detail: 'How close a pothole must be to warn you',
                trailing: DropdownButton<int>(
                  value: state.radiusM,
                  underline: const SizedBox(),
                  borderRadius: BorderRadius.circular(12),
                  items: [
                    for (final r in alertRadii)
                      DropdownMenuItem(value: r, child: Text(formatDistance(r.toDouble()))),
                  ],
                  onChanged: (r) => r == null ? null : state.setRadius(r),
                ),
              ),
              _SettingRow(
                icon: Icons.dark_mode_outlined,
                title: 'Dark mode',
                detail: 'Easier on the eyes at night',
                trailing: Switch(value: state.darkMode, onChanged: state.setDarkMode),
              ),
              _SettingRow(
                icon: Icons.my_location_rounded,
                title: 'Location',
                detail: state.isLocating
                    ? 'Finding your location...'
                    : state.location != null
                        ? 'Device GPS active'
                        : (problem == null ? 'Not available yet' : LocationException(problem).message),
                trailing: TextButton(
                  onPressed: state.isLocating
                      ? null
                      : () async {
                          final fixable =
                              problem == LocationProblem.serviceOff || problem == LocationProblem.deniedForever;
                          if (state.location == null && fixable) await openSettingsFor(problem!);
                          await state.updateLocation();
                        },
                  child: const Text('Update'),
                ),
              ),
              const SectionHeader('Background Alerts'),
              BackgroundAlertsSettings(apiClient: state.api),
              const SectionHeader('Account'),
              if (user != null)
                _SettingRow(
                  icon: Icons.person_outline_rounded,
                  title: user.name,
                  detail: user.email,
                  trailing: TextButton(
                    onPressed: () {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                      auth.logout();
                    },
                    style: TextButton.styleFrom(foregroundColor: c.high),
                    child: const Text('Log out'),
                  ),
                ),
              const SectionHeader('About'),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI-Based Pothole Detection and Geo-Tagged Reporting System',
                      style: context.text.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Project Seminar II · Dept. of Computer Science & Engineering',
                      style: TextStyle(color: c.muted, fontSize: 13, height: 1.5),
                    ),
                    const SizedBox(height: Gap.sm),
                    const _AboutLine(label: 'Team', value: 'Jenika Barai, Shreesh Pawar, Anvesh Mulkalwar, Parth Lonkar'),
                    const _AboutLine(label: 'Guide', value: 'Prof. V. V. Deshpande'),
                    const _AboutLine(label: 'Mentor', value: 'Mr. Manmeet Sehmi'),
                    const SizedBox(height: 6),
                    Text(
                      'YOLOv8 detection · Depth Anything V2 · FastAPI · OpenStreetMap',
                      style: TextStyle(color: c.muted, fontSize: 13, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.icon, required this.title, required this.detail, required this.trailing});

  final IconData icon;
  final String title;
  final String detail;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            IconTile(icon: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(detail, style: context.text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 6),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _AboutLine extends StatelessWidget {
  const _AboutLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: value),
        ],
      ),
      style: const TextStyle(fontSize: 13, height: 1.6),
    );
  }
}
