import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Warns the user about a pothole ahead with a notification and a vibration.
abstract class AlertNotifier {
  /// Asks for permission to show notifications. Returns false when the user says no.
  Future<bool> requestPermission();

  /// Shows one alert. [urgent] is for high severity: it vibrates longer.
  Future<void> show({required String title, required String body, required bool urgent});
}

class LocalAlertNotifier implements AlertNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  // A new alert replaces the last one instead of piling up in the notification shade.
  static const _notificationId = 1;

  Future<void> _init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    try {
      await _init();
      final android =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> show({required String title, required String body, required bool urgent}) async {
    // Felt even when the notification itself is silenced or blocked.
    HapticFeedback.heavyImpact();
    try {
      await _init();
      // Off/on pairs in milliseconds, starting with the delay before the first buzz.
      final pattern = urgent ? [0, 400, 150, 400, 150, 400] : [0, 300, 150, 300];
      await _plugin.show(
        id: _notificationId,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            // The vibration pattern belongs to the channel, so each pattern needs its own.
            urgent ? 'pothole_alerts_high' : 'pothole_alerts',
            urgent ? 'High severity pothole alerts' : 'Pothole alerts',
            channelDescription: 'Warnings about potholes near you',
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.navigation,
            enableVibration: true,
            vibrationPattern: Int64List.fromList(pattern),
            ticker: title,
          ),
        ),
      );
    } catch (_) {
      // An alert that cannot be shown must not break the screen that triggered it.
    }
  }
}
