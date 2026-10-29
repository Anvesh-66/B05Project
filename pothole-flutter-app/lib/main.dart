import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app_state.dart';
import 'auth_controller.dart';
import 'scan_controller.dart';
import 'screens/login_screen.dart';
import 'screens/shell.dart';
import 'services/alert_notifier.dart';
import 'services/api_client.dart';
import 'services/location.dart';
import 'services/session_store.dart';
import 'services/firebase_notification_service.dart';
import 'services/pothole_alert_service.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase (only if google-services.json is configured)
  try {
    await Firebase.initializeApp();
    print('Firebase initialized successfully');
  } catch (e) {
    print('Firebase initialization skipped (not configured): $e');
  }

  // Initialize notification service
  try {
    final notificationService = FirebaseNotificationService();
    await notificationService.initialize();
    await notificationService.createNotificationChannels();
    print('Notification service initialized');
  } catch (e) {
    print('Notification service initialization error: $e');
  }

  // Initialize background work manager
  try {
    final alertService = PotholeAlertService();
    await alertService.initialize();
    print('Background alert service initialized');
  } catch (e) {
    print('Background alert service initialization error: $e');
  }

  runApp(const PotholeApp());
}

class PotholeApp extends StatefulWidget {
  /// The optional arguments exist so tests can run without a server or device.
  const PotholeApp({super.key, this.api, this.store, this.locate, this.watch, this.notifier, this.picker});

  final ApiClient? api;
  final SessionStore? store;
  final LocationProvider? locate;
  final LocationStream? watch;
  final AlertNotifier? notifier;
  final PhotoPicker? picker;

  @override
  State<PotholeApp> createState() => _PotholeAppState();
}

class _PotholeAppState extends State<PotholeApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final ApiClient _api = widget.api ?? ApiClient();
  late final SessionStore _store = widget.store ?? SecureSessionStore();
  late final AuthController _auth = AuthController(api: _api, store: _store);
  late final AppState _state = AppState(
    api: _api,
    store: _store,
    notifier: widget.notifier ?? LocalAlertNotifier(),
    locate: widget.locate,
    watch: widget.watch,
  );
  late final ScanController _scan = ScanController(
    api: _api,
    locate: _state.locate,
    picker: widget.picker,
    onSubmitted: (report) {
      // The user is standing next to the pothole they just reported; no need to warn them.
      _state.acknowledge(report.id);
      _state.refresh();
    },
  );

  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuthChanged);
    _state.loadSettings();
    _auth.restore();
  }

  void _onAuthChanged() {
    final signedIn = _auth.user != null;
    if (signedIn == _signedIn) return;
    _signedIn = signedIn;
    if (signedIn) {
      _state.start();
    } else {
      // Just signed out: drop that user's data and any screens opened on top of the tabs.
      _scan.clear();
      _state.stop();
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _auth.dispose();
    _scan.dispose();
    _state.dispose();
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_auth, _state]),
      builder: (context, _) {
        final dark = _state.darkMode;
        return MaterialApp(
          title: 'RoadGuard AI',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          navigatorKey: _navigatorKey,
          // Status-bar icons that contrast with the theme, on every screen.
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
            child: child!,
          ),
          home: _auth.restoring
              ? const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 3)))
              : _auth.user == null
                  ? LoginScreen(auth: _auth)
                  : Shell(auth: _auth, state: _state, scan: _scan),
        );
      },
    );
  }
}
