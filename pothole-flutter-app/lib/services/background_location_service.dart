import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing background location tracking for pothole alerts
class BackgroundLocationService {
  static const String _keyBackgroundTrackingEnabled = 'background_tracking_enabled';
  static const String _keyLastKnownLat = 'last_known_latitude';
  static const String _keyLastKnownLng = 'last_known_longitude';

  /// Check if background tracking is enabled by user
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBackgroundTrackingEnabled) ?? false;
  }

  /// Enable background tracking
  Future<void> enable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBackgroundTrackingEnabled, true);
  }

  /// Disable background tracking
  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBackgroundTrackingEnabled, false);
  }

  /// Request background location permission
  Future<bool> requestBackgroundPermission() async {
    // First check if regular location permission is granted
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    // For Android 10+ (API 29+), we need to request background location separately
    if (permission == LocationPermission.always) {
      return true; // Background permission already granted
    }

    if (permission == LocationPermission.whileInUse) {
      // Request background location permission
      // Note: This should show a system dialog asking for "Allow all the time"
      permission = await Geolocator.requestPermission();
      return permission == LocationPermission.always;
    }

    return false;
  }

  /// Check if location services are enabled
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Get current location and save it
  Future<Position?> getCurrentLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || 
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 100, // Update every 100 meters
        ),
      );

      await _saveLastKnownLocation(position.latitude, position.longitude);
      return position;
    } catch (e) {
      return null;
    }
  }

  /// Save last known location to shared preferences
  Future<void> _saveLastKnownLocation(double latitude, double longitude) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyLastKnownLat, latitude);
    await prefs.setDouble(_keyLastKnownLng, longitude);
  }

  /// Get last known location from shared preferences
  Future<Position?> getLastKnownLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_keyLastKnownLat);
    final lng = prefs.getDouble(_keyLastKnownLng);

    if (lat != null && lng != null) {
      return Position(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
    }
    return null;
  }

  /// Calculate distance between two coordinates in meters
  double calculateDistance(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
  }
}
