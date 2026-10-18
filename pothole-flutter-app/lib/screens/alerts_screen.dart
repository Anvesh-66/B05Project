import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/pothole.dart';
import '../services/location.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'shell.dart';

/// Unresolved potholes around the user, most severe first, within a chosen distance.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key, required this.state, required this.nav});

  final AppState state;
  final AppNavigator nav;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final nearby = state.nearby;
    final high = nearby.where((p) => p.severity == Severity.high).toList();
    final radius = formatDistance(state.radiusM.toDouble());

    return RefreshIndicator(
      onRefresh: () async {
        await state.updateLocation();
        await state.refreshNearby();
      },
      child: ListView(
        padding: screenPadding,
        children: [
          TabHeader(
            title: 'Nearby Alerts',
            actions: [
              HeaderButton(
                icon: Icons.my_location_rounded,
                tooltip: 'Refresh location',
                onTap: state.isLocating ? null : state.updateLocation,
              ),
            ],
          ),
          ChoiceChips<int>(
            options: alertRadii,
            selected: state.radiusM,
            label: (r) => formatDistance(r.toDouble()),
            onSelected: state.setRadius,
          ),
          const SizedBox(height: Gap.md),
          AppCard(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Medium & High only', style: context.text.titleSmall),
                      Text('Hide low severity potholes', style: context.text.bodySmall),
                    ],
                  ),
                ),
                Switch(value: state.majorOnly, onChanged: state.setMajorOnly),
              ],
            ),
          ),
          if (state.location == null) ...[
            const SizedBox(height: Gap.md),
            _LocationNeeded(state: state),
          ],
          if (high.isNotEmpty) ...[
            const SizedBox(height: Gap.md),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: c.highSoft, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 28, color: c.high),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${high.length} high severity pothole${high.length == 1 ? '' : 's'} ahead',
                          style: TextStyle(color: c.high, fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Nearest is ${formatDistance(high.first.distanceM ?? 0)} away · drive carefully',
                          style: TextStyle(color: c.high, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          SectionHeader(
            '${nearby.length} within $radius',
            trailing: Text(state.location == null ? 'No location' : 'Your GPS', style: context.text.labelSmall),
          ),
          if (nearby.isEmpty)
            EmptyCard(
              state.location == null
                  ? 'Alerts need your location.'
                  : 'No unresolved potholes in this radius. Drive safe!',
            )
          else
            for (final p in nearby)
              PotholeTile(
                pothole: p,
                onTap: () => nav.openPothole(p),
                trailing: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatDistance(p.distanceM ?? 0), style: context.text.titleSmall),
                    const SizedBox(height: 3),
                    SeverityBadge(p.severity),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// Explains why there is no location and offers the fix that fits.
class _LocationNeeded extends StatelessWidget {
  const _LocationNeeded({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final problem = state.locationProblem;
    final canFixInSettings = problem == LocationProblem.serviceOff || problem == LocationProblem.deniedForever;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_off_outlined, size: 20, color: context.colors.high),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  state.isLocating
                      ? 'Finding your location...'
                      : (problem == null ? 'Your location is not known yet.' : LocationException(problem).message),
                  style: context.text.bodyMedium,
                ),
              ),
            ],
          ),
          if (!state.isLocating)
            Wrap(
              spacing: 4,
              children: [
                TextButton(onPressed: state.updateLocation, child: const Text('Try again')),
                if (canFixInSettings)
                  TextButton(onPressed: () => openSettingsFor(problem!), child: const Text('Open settings')),
              ],
            ),
        ],
      ),
    );
  }
}
