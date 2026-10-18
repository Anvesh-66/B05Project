import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../app_state.dart';
import '../models/pothole.dart';
import '../services/location.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pothole_map.dart';
import 'shell.dart';

enum _MapFilter {
  all('All'),
  open('Open'),
  high('High'),
  medium('Medium'),
  low('Low');

  const _MapFilter(this.label);

  final String label;

  bool matches(Pothole p) => switch (this) {
        _MapFilter.all => true,
        _MapFilter.open => !p.isResolved,
        _MapFilter.high => p.severity == Severity.high,
        _MapFilter.medium => p.severity == Severity.medium,
        _MapFilter.low => p.severity == Severity.low,
      };
}

/// Every geo-tagged pothole on a map, with a filterable list underneath.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.state, required this.nav, this.initialSelection});

  final AppState state;
  final AppNavigator nav;

  /// A pothole to start centred on, e.g. the one just reported.
  final int? initialSelection;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Shown when neither the user nor any pothole has a position: all of India.
  static const Coordinates _fallbackCenter = (latitude: 20.5937, longitude: 78.9629);

  final _map = MapController();
  _MapFilter _filter = _MapFilter.all;
  late int? _selectedId = widget.initialSelection;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _select(Pothole p) {
    setState(() => _selectedId = p.id);
    _map.move(LatLng(p.latitude!, p.longitude!), 16);
  }

  Future<void> _goToMyLocation() async {
    await widget.state.updateLocation();
    final here = widget.state.location;
    if (!mounted) return;
    if (here == null) {
      final problem = widget.state.locationProblem;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(problem == null ? 'Location unavailable.' : LocationException(problem).message)),
      );
    } else {
      _map.move(LatLng(here.latitude, here.longitude), 15);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = widget.state;
    final located = state.potholes.where((p) => p.hasLocation).toList();
    final shown = located.where(_filter.matches).toList();
    final selected = shown.where((p) => p.id == _selectedId).firstOrNull;
    final here = state.location;

    final Coordinates center;
    final double zoom;
    if (selected != null) {
      (center, zoom) = ((latitude: selected.latitude!, longitude: selected.longitude!), 16);
    } else if (here != null) {
      (center, zoom) = (here, 14);
    } else if (located.isNotEmpty) {
      (center, zoom) = ((latitude: located.first.latitude!, longitude: located.first.longitude!), 13);
    } else {
      (center, zoom) = (_fallbackCenter, 4.5);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
          child: TabHeader(
            title: 'Pothole Map',
            actions: [
              HeaderButton(icon: Icons.my_location_rounded, tooltip: 'My location', onTap: _goToMyLocation),
            ],
          ),
        ),
        SizedBox(
          height: 300,
          child: PotholeMap(
            controller: _map,
            center: center,
            zoom: zoom,
            potholes: shown,
            selectedId: selected?.id,
            onSelect: _select,
            userLocation: here,
          ),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: c.card,
              border: Border(top: BorderSide(color: c.border)),
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
              children: [
                ChoiceChips<_MapFilter>(
                  options: _MapFilter.values,
                  selected: _filter,
                  label: (f) => f.label,
                  onSelected: (f) => setState(() => _filter = f),
                ),
                const SizedBox(height: Gap.md),
                Text(
                  '${shown.length} geo-tagged pothole${shown.length == 1 ? '' : 's'}',
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: Gap.sm),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        located.isEmpty ? 'No geo-tagged potholes yet' : 'Nothing matches this filter',
                        style: TextStyle(color: c.muted, fontSize: 14),
                      ),
                    ),
                  )
                else
                  for (final p in shown)
                    PotholeTile(
                      pothole: p,
                      icon: Icons.location_on_outlined,
                      selected: p.id == selected?.id,
                      subtitle:
                          '${p.latitude!.toStringAsFixed(4)}, ${p.longitude!.toStringAsFixed(4)} · ${p.statusLabel}',
                      onTap: () => _select(p),
                      trailing: HeaderButton(
                        icon: Icons.chevron_right_rounded,
                        tooltip: 'Details',
                        onTap: () => widget.nav.openPothole(p),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
