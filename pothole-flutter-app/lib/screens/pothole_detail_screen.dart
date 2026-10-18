import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../models/pothole.dart';
import '../services/location.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pothole_map.dart';

/// Straight-line distance in metres between two points, by the haversine formula.
double distanceBetween(Coordinates a, Coordinates b) {
  const earthRadiusM = 6371000.0;
  double rad(double degrees) => degrees * math.pi / 180;
  final dLat = rad(b.latitude - a.latitude), dLng = rad(b.longitude - a.longitude);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.latitude)) * math.cos(rad(b.latitude)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadiusM * math.asin(math.sqrt(h));
}

/// One pothole: where it is, how severe, and how far along it is towards being repaired.
class PotholeDetailScreen extends StatelessWidget {
  const PotholeDetailScreen({super.key, required this.pothole, required this.state});

  final Pothole pothole;
  final AppState state;

  Future<void> _openInMaps(BuildContext context) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${pothole.latitude},${pothole.longitude}',
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open a maps app.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PageHeader(pothole.code),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          // Show the latest copy, in case the status changed since the list was loaded.
          final p = state.byId(pothole.id) ?? pothole;
          final here = state.location;
          final position = p.hasLocation ? (latitude: p.latitude!, longitude: p.longitude!) : null;
          final distance = here != null && position != null ? distanceBetween(here, position) : null;

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
            children: [
              if (position != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(cardRadius),
                  child: SizedBox(
                    height: 200,
                    child: PotholeMap(center: position, zoom: 16, potholes: [p], selectedId: p.id, interactive: false),
                  ),
                )
              else
                const EmptyCard('This report has no location attached.'),
              const SizedBox(height: Gap.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [SeverityBadge(p.severity), StatusTag(resolved: p.isResolved)],
              ),
              const SizedBox(height: Gap.sm),
              Text(p.title, style: context.text.titleLarge),
              if (p.area != null && p.area != p.title) Text(p.area!, style: context.text.bodySmall),
              const SizedBox(height: 14),
              AppCard(
                child: KeyValueGrid(entries: [
                  ('Latitude', Text(position == null ? '—' : position.latitude.toStringAsFixed(6))),
                  ('Longitude', Text(position == null ? '—' : position.longitude.toStringAsFixed(6))),
                  ('Distance', Text(distance == null ? '—' : formatDistance(distance))),
                  ('Confidence', Text('${(p.confidence * 100).round()}%')),
                  ('Reported', Text(formatDateTime(p.createdAt))),
                  ('Potholes found', Text('${p.detectionCount}')),
                ]),
              ),
              const SectionHeader('Status'),
              AppCard(
                child: Column(
                  children: [
                    _TimelineStep(
                      title: 'Detected & geo-tagged',
                      detail: formatDateTime(p.createdAt),
                      done: true,
                    ),
                    _TimelineStep(
                      title: 'Verified',
                      detail: p.isVerified ? 'Confirmed by a reviewer' : 'Awaiting verification',
                      done: p.isVerified,
                    ),
                    _TimelineStep(
                      title: 'Resolved',
                      detail: p.isResolved
                          ? 'Marked repaired${p.resolvedAt == null ? '' : ' · ${formatDateTime(p.resolvedAt!)}'}'
                          : 'Not yet repaired',
                      done: p.isResolved,
                      isLast: true,
                    ),
                  ],
                ),
              ),
              if (position != null) ...[
                const SizedBox(height: Gap.lg),
                FilledButton.icon(
                  onPressed: () => _openInMaps(context),
                  icon: const Icon(Icons.open_in_new_rounded, size: 20),
                  label: const Text('Open in Google Maps'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({required this.title, required this.detail, required this.done, this.isLast = false});

  final String title;
  final String detail;
  final bool done;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(color: done ? c.primary : c.border, shape: BoxShape.circle),
              ),
              if (!isLast) Expanded(child: Container(width: 2, color: c.border)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleSmall),
                  Text(detail, style: context.text.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
