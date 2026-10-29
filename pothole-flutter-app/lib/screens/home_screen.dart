import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/pothole.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'shell.dart';

/// Where the user is, what is close by, and the way into everything else.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.state, required this.nav});

  final AppState state;
  final AppNavigator nav;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final nearby = state.nearby;
    final highNearby = nearby.where((p) => p.severity == Severity.high).length;
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');

    return RefreshIndicator(
      onRefresh: state.refresh,
      child: ListView(
        padding: screenPadding,
        children: [
          TabHeader(
            overline: greeting,
            title: 'Road Safety',
            actions: [
              HeaderButton(
                icon: Icons.notifications_none_rounded,
                tooltip: 'Alerts',
                showDot: highNearby > 0,
                onTap: () => nav.openTab(AppTab.alerts),
              ),
              HeaderButton(icon: Icons.settings_outlined, tooltip: 'Settings', onTap: nav.openSettings),
            ],
          ),
          _Hero(state: state, highNearby: highNearby, onViewAlerts: () => nav.openTab(AppTab.alerts)),
          const SizedBox(height: Gap.md),
          AppCard(
            onTap: () => nav.openTab(AppTab.scan),
            child: Row(
              children: [
                const IconTile(icon: Icons.photo_camera_outlined, size: 52, filled: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Detect potholes', style: context.text.titleSmall?.copyWith(fontSize: 15)),
                      Text('Take or upload a road photo · AI detection', style: context.text.bodySmall),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.muted),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),
          EqualRow(children: [
            StatCard(value: '${state.dashboard.total}', label: 'Reported'),
            StatCard(
              value: '${state.potholes.where((p) => p.severity == Severity.high && !p.isResolved).length}',
              label: 'High risk',
              color: c.high,
            ),
            StatCard(value: '${state.dashboard.resolved}', label: 'Resolved', color: c.low),
          ]),
          if (state.loadError != null) ...[
            const SizedBox(height: Gap.md),
            MessageBanner.error(state.loadError!, onRetry: state.refresh),
          ],
          SectionHeader('Closest to you', action: 'See all', onAction: () => nav.openTab(AppTab.alerts)),
          if (nearby.isEmpty)
            EmptyCard(state.location == null ? 'Turn on location to see potholes near you' : 'No unresolved potholes nearby')
          else
            for (final p in nearby.take(2))
              PotholeTile(
                pothole: p,
                onTap: () => nav.openPothole(p),
                trailing: _DistanceLabel(pothole: p),
              ),
          SectionHeader('Recent reports', action: 'View all', onAction: nav.openReports),
          if (state.potholes.isEmpty)
            EmptyCard(state.isLoading ? 'Loading reports...' : 'No reports yet. Be the first to report a pothole.')
          else
            for (final p in state.potholes.take(3)) PotholeTile(pothole: p, onTap: () => nav.openPothole(p)),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.state, required this.highNearby, required this.onViewAlerts});

  final AppState state;
  final int highNearby;
  final VoidCallback onViewAlerts;

  @override
  Widget build(BuildContext context) {
    final here = state.location;
    final count = state.nearby.length;
    final where = here == null
        ? (state.isLocating ? 'Finding your location...' : 'Location unavailable')
        : '${here.latitude.toStringAsFixed(4)}, ${here.longitude.toStringAsFixed(4)}';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF016ED3), Color(0xFF0A4FA3)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 16, color: Colors.white70),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  where,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (here != null) ...[
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: Color(0xFF4ADE80), shape: BoxShape.circle),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$count pothole${count == 1 ? '' : 's'} nearby',
            style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.4),
          ),
          const SizedBox(height: 2),
          Text(
            '$highNearby high severity within ${formatDistance(state.radiusM.toDouble())} · unresolved',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onViewAlerts,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFF016ED3)),
                    SizedBox(width: 6),
                    Text(
                      'View alerts',
                      style: TextStyle(color: Color(0xFF016ED3), fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Distance in bold over the severity word, for the right side of a nearby tile.
class _DistanceLabel extends StatelessWidget {
  const _DistanceLabel({required this.pothole});

  final Pothole pothole;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(formatDistance(pothole.distanceM ?? 0), style: context.text.titleSmall),
        Text(pothole.severity.label, style: context.text.bodySmall),
      ],
    );
  }
}
