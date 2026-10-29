import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Top-level function for handling background messages
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Handle background messages here
  print('Background message received: ${message.messageId}');
}

/// Service for managing Firebase Cloud Messaging and local notifications
class FirebaseNotificationService {
  static final FirebaseNotificationService _instance = FirebaseNotificationService._internal();
  factory FirebaseNotificationService() => _instance;
  FirebaseNotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  
  static const String _keyFcmToken = 'fcm_token';
  bool _initialized = false;

  /// Initialize Firebase Cloud Messaging and local notifications
  Future<void> initialize() async {
    if (_initialized) return;

    // Initialize local notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    
    await _localNotifications.initialize(settings: initSettings);

    // Request notification permissions
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted notification permission');
    } else {
      print('User declined or has not accepted notification permission');
    }

    // Get FCM token
    final token = await _fcm.getToken();
    if (token != null) {
      await _saveFcmToken(token);
      print('FCM Token: $token');
    }

    // Listen for token refresh
    _fcm.onTokenRefresh.listen(_saveFcmToken);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Handle notification when app is opened from terminated state
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    _initialized = true;
  }

  /// Handle notification tap
  void _onNotificationTap(NotificationResponse response) {
    print('Notification tapped: ${response.payload}');
    // Navigate to relevant screen based on payload
  }

  /// Handle foreground message
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('Foreground message: ${message.messageId}');
    
    final notification = message.notification;
    if (notification != null) {
      await showLocalNotification(
        title: notification.title ?? 'Pothole Alert',
        body: notification.body ?? 'A pothole was detected nearby',
        payload: message.data.toString(),
        urgent: message.data['urgent'] == 'true',
      );
    }
  }

  /// Handle when app is opened from notification
  void _handleMessageOpenedApp(RemoteMessage message) {
    print('App opened from notification: ${message.messageId}');
    // Handle navigation
  }

  /// Save FCM token to shared preferences
  Future<void> _saveFcmToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFcmToken, token);
  }

  /// Get FCM token
  Future<String?> getFcmToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyFcmToken);
  }

  /// Show local notification with vibration
  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
    bool urgent = false,
  }) async {
    // Vibration pattern
    HapticFeedback.heavyImpact();
    
    final pattern = urgent 
        ? Int64List.fromList([0, 400, 150, 400, 150, 400]) 
        : Int64List.fromList([0, 300, 150, 300]);

    final androidDetails = AndroidNotificationDetails(
      'pothole_background_alerts',
      'Background Pothole Alerts',
      channelDescription: 'Alerts for nearby potholes detected in background',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.navigation,
      enableVibration: true,
      vibrationPattern: pattern,
      ticker: 'Pothole Alert',
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title,
      body: body,
      notificationDetails: notificationDetails,
      payload: payload,
    );
  }

  /// Show severe pothole alert
  Future<void> showSeverePotholeAlert({
    required double distance,
    required int count,
  }) async {
    final distanceText = distance < 1000 
        ? '${distance.toStringAsFixed(0)}m away'
        : '${(distance / 1000).toStringAsFixed(1)}km away';

    await showLocalNotification(
      title: '⚠️ SEVERE Pothole Alert',
      body: '$count severe pothole${count > 1 ? 's' : ''} detected $distanceText',
      urgent: true,
    );
  }

  /// Show nearby pothole alert
  Future<void> showNearbyPotholeAlert({
    required double distance,
    required int count,
    required String severity,
  }) async {
    final distanceText = distance < 1000 
        ? '${distance.toStringAsFixed(0)}m away'
        : '${(distance / 1000).toStringAsFixed(1)}km away';

    await showLocalNotification(
      title: '🚧 Pothole Alert',
      body: '$count $severity pothole${count > 1 ? 's' : ''} $distanceText',
      urgent: severity.toUpperCase() == 'HIGH',
    );
  }

  /// Create notification channels (Android 8.0+)
  Future<void> createNotificationChannels() async {
    const AndroidNotificationChannel severeChannel = AndroidNotificationChannel(
      'pothole_alerts_high',
      'High Severity Pothole Alerts',
      description: 'Critical warnings about severe potholes near you',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    );

    const AndroidNotificationChannel regularChannel = AndroidNotificationChannel(
      'pothole_alerts',
      'Pothole Alerts',
      description: 'Warnings about potholes near you',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );

    const AndroidNotificationChannel backgroundChannel = AndroidNotificationChannel(
      'pothole_background_alerts',
      'Background Pothole Alerts',
      description: 'Alerts for nearby potholes detected in background',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    );

    final android = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (android != null) {
      await android.createNotificationChannel(severeChannel);
      await android.createNotificationChannel(regularChannel);
      await android.createNotificationChannel(backgroundChannel);
    }
  }
}
