import 'dart:async';

import 'package:flutter/foundation.dart';

import 'models/pothole.dart';
import 'services/alert_notifier.dart';
import 'services/api_client.dart';
import 'services/location.dart';
import 'services/session_store.dart';
import 'theme.dart';

/// Alert distances the user can choose between, in metres.
const List<int> alertRadii = [500, 1000, 2000, 5000];

/// Everything the tabs share: the user's position, every reported pothole, the ones
/// nearby, the dashboard figures and the user's preferences. It also decides when a
/// nearby pothole deserves an alert.
class AppState extends ChangeNotifier {
  AppState({
    required this.api,
    required this.store,
    required this.notifier,
    LocationProvider? locate,
    LocationStream? watch,
  })  : locate = locate ?? currentLocation,
        _watch = watch ?? watchLocation;

  final ApiClient api;
  final SessionStore store;
  final AlertNotifier notifier;

  /// Reads the phone's position once; shared with the scan flow and the map picker.
  final LocationProvider locate;
  final LocationStream _watch;

  // ---- preferences ----
  int radiusM = 1000;
  bool majorOnly = false;
  bool alertsEnabled = true;
  bool darkMode = false;

  // ---- location ----
  Coordinates? location;
  LocationProblem? locationProblem;
  bool isLocating = false;

  // ---- data ----
  List<Pothole> potholes = const [];
  List<Pothole> nearby = const [];
  DashboardData dashboard = DashboardData.empty;
  bool isLoading = false;
  bool hasLoaded = false;
  String? loadError;

  StreamSubscription<Coordinates>? _positions;
  // Potholes the user has already been warned about while they stay in range.
  final _alerted = <int>{};
  bool _active = false;
  int _generation = 0;

  Future<void> loadSettings() async {
    try {
      final radius = int.tryParse(await store.readSetting('radius') ?? '');
      if (radius != null && alertRadii.contains(radius)) radiusM = radius;
      majorOnly = await store.readSetting('major_only') == 'true';
      alertsEnabled = await store.readSetting('alerts') != 'false';
      darkMode = await store.readSetting('dark') == 'true';
    } catch (_) {
      // Unreadable storage leaves the defaults in place.
    }
    notifyListeners();
  }

  void _save(String key, Object value) {
    store.writeSetting(key, value.toString()).catchError((_) {});
  }

  /// Called once the user is signed in: loads the data and starts watching the position.
  Future<void> start() async {
    if (_active) return;
    _active = true;
    if (alertsEnabled) unawaited(notifier.requestPermission());
    unawaited(refresh());
    await updateLocation();
    if (!_active) return;
    _positions?.cancel();
    _positions = _watch().listen(_onPosition);
  }

  /// Called on sign-out: forgets the previous user's view of things.
  void stop() {
    _active = false;
    _generation++;
    _positions?.cancel();
    _positions = null;
    _alerted.clear();
    potholes = const [];
    nearby = const [];
    dashboard = DashboardData.empty;
    location = null;
    locationProblem = null;
    isLocating = false;
    isLoading = false;
    hasLoaded = false;
    loadError = null;
    notifyListeners();
  }

  /// Reloads the pothole list, the dashboard and what is nearby.
  Future<void> refresh() async {
    final generation = _generation;
    isLoading = true;
    loadError = null;
    notifyListeners();

    String? error;
    List<Pothole>? newPotholes;
    DashboardData? newDashboard;
    try {
      newPotholes = await api.potholes();
      newDashboard = await api.dashboard();
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Unexpected error: $e';
    }

    if (generation != _generation) return;
    isLoading = false;
    loadError = error;
    if (newPotholes != null && newDashboard != null) {
      potholes = newPotholes;
      dashboard = newDashboard;
      hasLoaded = true;
    }
    notifyListeners();
    await refreshNearby();
  }

  /// Reads the phone's position now, e.g. from the "my location" buttons.
  Future<void> updateLocation() async {
    if (isLocating) return;
    final generation = _generation;
    isLocating = true;
    notifyListeners();

    Coordinates? found;
    LocationProblem? problem;
    try {
      found = await locate();
    } on LocationException catch (e) {
      problem = e.problem;
    } catch (_) {
      problem = LocationProblem.unavailable;
    }

    if (generation != _generation) return;
    isLocating = false;
    locationProblem = problem;
    if (found != null) location = found;
    notifyListeners();
    if (found != null) await refreshNearby();
  }

  void _onPosition(Coordinates position) {
    location = position;
    locationProblem = null;
    notifyListeners();
    refreshNearby();
  }

  /// Asks the server what is within the alert radius, and alerts about anything new.
  Future<void> refreshNearby() async {
    final here = location;
    if (here == null || !_active) return;
    final generation = _generation;
    List<Pothole> found;
    try {
      found = await api.nearby(
        latitude: here.latitude,
        longitude: here.longitude,
        radiusM: radiusM,
        majorOnly: majorOnly,
      );
    } catch (_) {
      // Keep showing the last known list; the next position update will try again.
      return;
    }
    if (generation != _generation) return;
    nearby = found;
    notifyListeners();
    _alertAbout(found);
  }

  void _alertAbout(List<Pothole> inRange) {
    final ids = {for (final p in inRange) p.id};
    // Once a pothole is out of range it may alert again on the next approach.
    _alerted.removeWhere((id) => !ids.contains(id));
    final fresh = inRange.where((p) => !_alerted.contains(p.id)).toList();
    _alerted.addAll(ids);
    if (!alertsEnabled || fresh.isEmpty) return;

    // The server sends the most severe first, then the nearest.
    final worst = fresh.first;
    final distance = formatDistance(worst.distanceM ?? 0);
    final title = fresh.length == 1
        ? '${worst.severity.label} severity pothole $distance away'
        : '${fresh.length} potholes nearby';
    final body = fresh.length == 1
        ? '${worst.title} · drive carefully'
        : 'Nearest ${worst.severity.label.toLowerCase()} severity is $distance away · drive carefully';
    notifier.show(title: title, body: body, urgent: worst.severity == Severity.high);
  }

  /// Marks a pothole as already known to the user, so it does not alert. Used for one
  /// they have just reported while standing next to it.
  void acknowledge(int id) => _alerted.add(id);

  void setRadius(int metres) {
    if (metres == radiusM) return;
    radiusM = metres;
    _save('radius', metres);
    notifyListeners();
    refreshNearby();
  }

  void setMajorOnly(bool value) {
    if (value == majorOnly) return;
    majorOnly = value;
    _save('major_only', value);
    notifyListeners();
    refreshNearby();
  }

  Future<void> setAlertsEnabled(bool value) async {
    if (value == alertsEnabled) return;
    alertsEnabled = value;
    _save('alerts', value);
    notifyListeners();
    if (value) await notifier.requestPermission();
  }

  void setDarkMode(bool value) {
    if (value == darkMode) return;
    darkMode = value;
    _save('dark', value);
    notifyListeners();
  }

  Pothole? byId(int id) {
    for (final p in potholes) {
      if (p.id == id) return p;
    }
    return null;
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _positions?.cancel();
    super.dispose();
  }

  // A reply from the server can arrive after the app has shut this state down.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}
