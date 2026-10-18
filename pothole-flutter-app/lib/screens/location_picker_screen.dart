import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/location.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pothole_map.dart';

/// Full-screen map for choosing where a gallery photo was taken. The map moves under
/// a fixed pin; popping returns the [Coordinates] under the pin, or null if cancelled.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, this.initial, required this.locate});

  /// Where the map starts, when the photo already has a location.
  final Coordinates? initial;
  final LocationProvider locate;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  // Shown until the phone's position is known: all of India.
  static const _fallbackCenter = LatLng(20.5937, 78.9629);
  static const _fallbackZoom = 4.5;
  static const _streetZoom = 16.0;

  final _map = MapController();
  late LatLng _center;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _center = initial == null ? _fallbackCenter : LatLng(initial.latitude, initial.longitude);
    // With nothing chosen yet, start at the user's own position if it can be read.
    if (initial == null) WidgetsBinding.instance.addPostFrameCallback((_) => _goToMyLocation(quiet: true));
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _goToMyLocation({bool quiet = false}) async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final here = await widget.locate();
      if (!mounted) return;
      _map.move(LatLng(here.latitude, here.longitude), _streetZoom);
    } on LocationException catch (e) {
      if (mounted && !quiet) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Scaffold(
      appBar: const PageHeader('Choose Location'),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: widget.initial == null ? _fallbackZoom : _streetZoom,
              onPositionChanged: (camera, _) => setState(() => _center = camera.center),
            ),
            children: baseMapLayers(),
          ),
          // The pin's tip, not its middle, marks the chosen point.
          IgnorePointer(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 44),
                child: Icon(Icons.location_on, size: 44, color: context.colors.high),
              ),
            ),
          ),
          Positioned(
            right: Gap.lg,
            top: Gap.lg,
            child: FloatingActionButton.small(
              heroTag: null,
              tooltip: 'Go to my location',
              onPressed: _locating ? null : _goToMyLocation,
              child: _locating
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location_rounded),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, Gap.md, 20, Gap.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Move the map so the pin sits on the pothole.',
                style: text.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                '${_center.latitude.toStringAsFixed(5)}, ${_center.longitude.toStringAsFixed(5)}',
                style: text.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Gap.md),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop<Coordinates>(
                  (latitude: _center.latitude, longitude: _center.longitude),
                ),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Use this location'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
