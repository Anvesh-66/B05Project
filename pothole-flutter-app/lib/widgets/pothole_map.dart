import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/pothole.dart';
import '../services/location.dart';
import '../theme.dart';

/// Map tiles are fetched from the internet. Tests turn this off so they need no network.
bool mapTilesEnabled = true;

const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _packageName = 'com.example.pothole_detector';

/// The OpenStreetMap base layer shared by every map in the app.
List<Widget> baseMapLayers() => [
      if (mapTilesEnabled) TileLayer(urlTemplate: _tileUrl, userAgentPackageName: _packageName),
      const _Attribution(),
    ];

/// The credit OpenStreetMap asks for, small enough to fit the narrowest map.
class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        color: Colors.white.withValues(alpha: 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        child: const Text('© OpenStreetMap', style: TextStyle(fontSize: 10, color: Colors.black87)),
      ),
    );
  }
}

/// A map with one dot per pothole, coloured by severity, and the user's own position.
class PotholeMap extends StatelessWidget {
  const PotholeMap({
    super.key,
    required this.center,
    this.zoom = 15,
    this.potholes = const [],
    this.selectedId,
    this.onSelect,
    this.userLocation,
    this.controller,
    this.interactive = true,
  });

  final Coordinates center;
  final double zoom;
  final List<Pothole> potholes;
  final int? selectedId;
  final ValueChanged<Pothole>? onSelect;
  final Coordinates? userLocation;
  final MapController? controller;

  /// False for a small preview that should scroll with the page instead of panning.
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final here = userLocation;
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: LatLng(center.latitude, center.longitude),
        initialZoom: zoom,
        interactionOptions: InteractionOptions(
          flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none,
        ),
      ),
      children: [
        ...baseMapLayers(),
        MarkerLayer(
          markers: [
            if (here != null)
              Marker(
                point: LatLng(here.latitude, here.longitude),
                width: 22,
                height: 22,
                child: Container(
                  decoration: BoxDecoration(
                    color: c.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [BoxShadow(color: c.primary.withValues(alpha: 0.45), blurRadius: 8)],
                  ),
                ),
              ),
            // The selected pothole is drawn last so it sits on top of its neighbours.
            for (final p in [...potholes]..sort((a, b) => (a.id == selectedId ? 1 : 0) - (b.id == selectedId ? 1 : 0)))
              if (p.hasLocation)
                Marker(
                  point: LatLng(p.latitude!, p.longitude!),
                  width: p.id == selectedId ? 44 : 34,
                  height: p.id == selectedId ? 44 : 34,
                  alignment: Alignment.topCenter,
                  child: GestureDetector(
                    onTap: onSelect == null ? null : () => onSelect!(p),
                    child: Icon(
                      Icons.location_on,
                      size: p.id == selectedId ? 44 : 34,
                      color: c.of(p.severity).color,
                      shadows: const [Shadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 1))],
                    ),
                  ),
                ),
          ],
        ),
      ],
    );
  }
}
