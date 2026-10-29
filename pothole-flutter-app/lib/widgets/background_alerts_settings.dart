import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/background_location_service.dart';
import '../services/pothole_alert_service.dart';
import '../services/api_client.dart';
import '../config.dart';

/// Widget for managing background pothole alert settings
class BackgroundAlertsSettings extends StatefulWidget {
  const BackgroundAlertsSettings({
    super.key,
    required this.apiClient,
  });

  final ApiClient apiClient;

  @override
  State<BackgroundAlertsSettings> createState() => _BackgroundAlertsSettingsState();
}

class _BackgroundAlertsSettingsState extends State<BackgroundAlertsSettings> {
  final _locationService = BackgroundLocationService();
  final _alertService = PotholeAlertService();
  
  bool _isEnabled = false;
  bool _isLoading = true;
  bool _hasBackgroundPermission = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    
    final enabled = await _locationService.isEnabled();
    final permission = await _checkBackgroundPermission();
    
    setState(() {
      _isEnabled = enabled;
      _hasBackgroundPermission = permission;
      _isLoading = false;
    });
  }

  Future<bool> _checkBackgroundPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always;
  }

  Future<void> _toggleBackgroundAlerts(bool value) async {
    if (value) {
      // Enabling background alerts
      
      // Check location service
      final serviceEnabled = await _locationService.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError('Location services are disabled. Please enable them in your device settings.');
        return;
      }

      // Request background location permission
      final hasPermission = await _locationService.requestBackgroundPermission();
      if (!hasPermission) {
        _showError(
          'Background location permission is required for pothole alerts when app is closed. '
          'Please grant "Allow all the time" permission in settings.',
        );
        return;
      }

      // Enable tracking
      await _locationService.enable();

      // Start background checks
      final token = widget.apiClient.token;
      if (token != null) {
        await _alertService.startBackgroundChecks(
          authToken: token,
          apiBaseUrl: widget.apiClient.baseUrl,
        );
      }

      setState(() {
        _isEnabled = true;
        _hasBackgroundPermission = true;
      });

      _showSuccess('Background pothole alerts enabled! You will be notified of nearby severe potholes even when the app is closed.');
    } else {
      // Disabling background alerts
      await _locationService.disable();
      await _alertService.stopBackgroundChecks();

      setState(() => _isEnabled = false);

      _showSuccess('Background pothole alerts disabled.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _testNow() async {
    setState(() => _isLoading = true);

    try {
      final position = await _locationService.getCurrentLocation();
      if (position == null) {
        _showError('Could not get your current location.');
        return;
      }

      await _alertService.checkNow(
        apiClient: widget.apiClient,
        position: position,
      );

      _showSuccess('Alert check complete. If there are nearby potholes, you should receive a notification.');
    } catch (e) {
      _showError('Error checking for nearby potholes: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Background Pothole Alerts',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Get notified of nearby severe potholes even when app is closed',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _isEnabled,
                  onChanged: _toggleBackgroundAlerts,
                ),
              ],
            ),
            
            if (_isEnabled) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              
              Row(
                children: [
                  Icon(
                    _hasBackgroundPermission ? Icons.check_circle : Icons.warning,
                    color: _hasBackgroundPermission ? Colors.green : Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _hasBackgroundPermission
                          ? 'Background location permission granted'
                          : 'Background location permission needed',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              const Text(
                'Settings:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              
              Text(
                '• Checks for potholes every 15 minutes',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              Text(
                '• Alerts within 1km radius',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              Text(
                '• Prioritizes severe potholes',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              
              const SizedBox(height: 16),
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _testNow,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Test Alert Now'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
            
            if (!_isEnabled) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Enable to receive alerts about nearby potholes even when the app is not running.',
                        style: TextStyle(fontSize: 13, color: Colors.blue[900]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
