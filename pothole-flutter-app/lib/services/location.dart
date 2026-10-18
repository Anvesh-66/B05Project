import 'dart:async';

import 'package:geolocator/geolocator.dart';

typedef Coordinates = ({double latitude, double longitude});

/// Finds the phone's position, or throws a [LocationException] saying why it could not.
typedef LocationProvider = Future<Coordinates> Function();

/// Reports the phone's position each time it moves a little, for nearby alerts.
typedef LocationStream = Stream<Coordinates> Function();

/// Metres the phone must move before [watchLocation] reports again.
const int _watchDistanceM = 30;

/// The phone's position as it moves. Emits nothing while location is off or not permitted.
Stream<Coordinates> watchLocation() {
  return Geolocator.getPositionStream(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: _watchDistanceM),
  ).map((p) => (latitude: p.latitude, longitude: p.longitude)).handleError((_) {});
}

/// What stopped the phone's position being read, so the screen can offer the right fix.
enum LocationProblem {
  /// Location is switched off in the phone's settings.
  serviceOff,

  /// The user declined the permission prompt; asking again is allowed.
  denied,

  /// The permission is blocked; it can only be changed in the app's settings.
  deniedForever,

  /// Location is on and allowed, but no position came back in time.
  unavailable,
}

class LocationException implements Exception {
  const LocationException(this.problem);

  final LocationProblem problem;

  String get message => switch (problem) {
        LocationProblem.serviceOff => 'Location is turned off on this phone.',
        LocationProblem.denied => 'Location permission was not granted.',
        LocationProblem.deniedForever => 'Location permission is blocked for this app.',
        LocationProblem.unavailable => 'Could not get a location fix. Move somewhere with a clearer view of the sky.',
      };

  @override
  String toString() => message;
}

/// The phone's current position.
Future<Coordinates> currentLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const LocationException(LocationProblem.serviceOff);
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied) throw const LocationException(LocationProblem.denied);
  if (permission == LocationPermission.deniedForever) {
    throw const LocationException(LocationProblem.deniedForever);
  }

  Position? position;
  try {
    position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  } on TimeoutException {
    // A GPS fix can take a while indoors; a recent position is better than none.
    position = await Geolocator.getLastKnownPosition();
  } on LocationServiceDisabledException {
    throw const LocationException(LocationProblem.serviceOff);
  } catch (_) {
    position = await Geolocator.getLastKnownPosition();
  }
  if (position == null) throw const LocationException(LocationProblem.unavailable);
  return (latitude: position.latitude, longitude: position.longitude);
}

/// Opens the settings page where [problem] can be fixed. Does nothing for problems
/// that settings cannot fix.
Future<void> openSettingsFor(LocationProblem problem) async {
  switch (problem) {
    case LocationProblem.serviceOff:
      await Geolocator.openLocationSettings();
    case LocationProblem.deniedForever:
      await Geolocator.openAppSettings();
    case LocationProblem.denied:
    case LocationProblem.unavailable:
      break;
  }
}
