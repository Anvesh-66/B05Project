import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../models/severity.dart';
import 'api_client.dart';
import 'background_location_service.dart';
import 'firebase_notification_service.dart';

/// Background task callback - must be top-level function
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      print('Background task started: $task');
      
      // Check if background tracking is enabled
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('background_tracking_enabled') ?? false;
      
      if (!enabled) {
        print('Background tracking is disabled');
        return Future.value(true);
      }

      // Get saved token and base URL
      final token = prefs.getString('auth_token');
      final baseUrl = prefs.getString('api_base_url') ?? 'http://127.0.0.1:8000';
      
      if (token == null) {
        print('No auth token found');
        return Future.value(true);
      }

      // Get location
      final locationService = BackgroundLocationService();
      Position? position = await locationService.getCurrentLocation();
      
      if (position == null) {
        // Try to get last known location
        position = await locationService.getLastKnownLocation();
      }

      if (position == null) {
        print('Could not get location');
        return Future.value(true);
      }

      print('Location: ${position.latitude}, ${position.longitude}');

      // Check for nearby potholes
      final apiClient = ApiClient(baseUrl: baseUrl);
      apiClient.token = token;

      final potholes = await apiClient.nearby(
        latitude: position.latitude,
        longitude: position.longitude,
        radiusM: 1000, // Check within 1km
        majorOnly: false,
      );

      print('Found ${potholes.length} nearby potholes');

      if (potholes.isNotEmpty) {
        // Get last alerted pothole IDs to avoid duplicate alerts
        final lastAlerted = prefs.getStringList('last_alerted_potholes') ?? [];
        final lastAlertTime = prefs.getInt('last_alert_time') ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;

        // Only alert if it's been more than 15 minutes since last alert
        // or if there are new potholes
        if (now - lastAlertTime > 15 * 60 * 1000 || 
            !potholes.every((p) => lastAlerted.contains(p.id.toString()))) {
          
          // Count severe potholes
          final severePotholes = potholes.where((p) => 
            p.severity == Severity.high
          ).toList();

          // Calculate distance to nearest pothole
          final nearest = potholes.first;
          if (nearest.latitude == null || nearest.longitude == null) {
            print('Pothole has no location');
            return Future.value(true);
          }
          
          final distance = locationService.calculateDistance(
            position.latitude,
            position.longitude,
            nearest.latitude!,
            nearest.longitude!,
          );

          // Send notification
          final notificationService = FirebaseNotificationService();
          
          if (severePotholes.isNotEmpty) {
            await notificationService.showSeverePotholeAlert(
              distance: distance,
              count: severePotholes.length,
            );
          } else {
            await notificationService.showNearbyPotholeAlert(
              distance: distance,
              count: potholes.length,
              severity: nearest.severity.label,
            );
          }

          // Save alerted pothole IDs
          await prefs.setStringList(
            'last_alerted_potholes',
            potholes.map((p) => p.id.toString()).toList(),
          );
          await prefs.setInt('last_alert_time', now);
        }
      }

      apiClient.close();
      return Future.value(true);
    } catch (e) {
      print('Background task error: $e');
      return Future.value(false);
    }
  });
}

/// Service for checking nearby potholes and sending alerts
class PotholeAlertService {
  static const String _taskName = 'pothole_check_task';
  static const String _keyAuthToken = 'auth_token';
  static const String _keyApiBaseUrl = 'api_base_url';

  /// Initialize the background work manager
  Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
  }

  /// Start periodic background checks
  Future<void> startBackgroundChecks({
    required String authToken,
    required String apiBaseUrl,
  }) async {
    // Save credentials for background task
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAuthToken, authToken);
    await prefs.setString(_keyApiBaseUrl, apiBaseUrl);

    // Register periodic task - runs every 15 minutes
    await Workmanager().registerPeriodicTask(
      _taskName,
      _taskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );

    print('Background pothole checks started');
  }

  /// Stop periodic background checks
  Future<void> stopBackgroundChecks() async {
    await Workmanager().cancelByUniqueName(_taskName);
    print('Background pothole checks stopped');
  }

  /// Cancel all background tasks
  Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }

  /// Manually check for nearby potholes (for testing)
  Future<void> checkNow({
    required ApiClient apiClient,
    required Position position,
  }) async {
    try {
      final potholes = await apiClient.nearby(
        latitude: position.latitude,
        longitude: position.longitude,
        radiusM: 1000,
        majorOnly: false,
      );

      if (potholes.isNotEmpty) {
        final locationService = BackgroundLocationService();
        final severePotholes = potholes.where((p) => 
          p.severity == Severity.high
        ).toList();

        final nearest = potholes.first;
        if (nearest.latitude == null || nearest.longitude == null) {
          print('Pothole has no location');
          return;
        }
        
        final distance = locationService.calculateDistance(
          position.latitude,
          position.longitude,
          nearest.latitude!,
          nearest.longitude!,
        );

        final notificationService = FirebaseNotificationService();
        
        if (severePotholes.isNotEmpty) {
          await notificationService.showSeverePotholeAlert(
            distance: distance,
            count: severePotholes.length,
          );
        } else {
          await notificationService.showNearbyPotholeAlert(
            distance: distance,
            count: potholes.length,
            severity: nearest.severity.label,
          );
        }
      }
    } catch (e) {
      print('Error checking nearby potholes: $e');
    }
  }
}
