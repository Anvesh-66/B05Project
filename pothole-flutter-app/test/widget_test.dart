import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pothole_detector/app_state.dart';
import 'package:pothole_detector/auth_controller.dart';
import 'package:pothole_detector/main.dart';
import 'package:pothole_detector/models/pothole.dart';
import 'package:pothole_detector/scan_controller.dart';
import 'package:pothole_detector/services/api_client.dart';
import 'package:pothole_detector/services/location.dart';
import 'package:pothole_detector/services/session_store.dart';
import 'package:pothole_detector/theme.dart';
import 'package:pothole_detector/widgets/pothole_map.dart';

import 'support.dart';

AppState _state(FakeBackend backend, FakeNotifier notifier, {LocationProvider locate = atPune, SessionStore? store}) {
  return AppState(
    api: backend.api(),
    store: store ?? MemorySessionStore(),
    notifier: notifier,
    locate: locate,
    watch: noMovement,
  );
}

void main() {
  // Map tiles come from the internet; tests draw the maps without them.
  setUp(() => mapTilesEnabled = false);

  group('ApiClient', () {
    test('login returns the session and later requests carry the token', () async {
      final backend = FakeBackend();
      final api = backend.api(signedIn: false);

      final session = await api.login(email: 'asha@example.com', password: 'correct horse');
      api.token = session.token;
      final potholes = await api.potholes();

      expect(session.user.name, 'Asha');
      expect(potholes.first.code, 'PH-0048');
      expect(potholes.first.severity, Severity.high);
      expect(backend.requests.last.headers['Authorization'], 'Bearer tok');
    });

    test('wrong password surfaces the server message without signing out', () async {
      var signedOut = false;
      final api = FakeBackend().api(signedIn: false)..onUnauthorized = () => signedOut = true;

      await expectLater(
        api.login(email: 'asha@example.com', password: 'nope'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Incorrect email or password.')),
      );
      expect(signedOut, isFalse);
    });

    test('an expired token triggers sign-out', () async {
      var signedOut = false;
      final api = FakeBackend().api()
        ..token = 'stale'
        ..onUnauthorized = () => signedOut = true;

      await expectLater(api.potholes(), throwsA(isA<ApiException>()));
      expect(signedOut, isTrue);
    });

    test('detect sends the photo with its location and returns a draft', () async {
      final backend = FakeBackend();
      final draft = await backend.api().detect(png, 'a.png', latitude: 17.385, longitude: 78.4867);

      final sent = backend.where('POST', '/detect').single as http.MultipartRequest;
      expect(sent.fields, {'latitude': '17.385', 'longitude': '78.4867'});
      expect(sent.files.single.filename, 'a.png');
      expect(draft!.submitted, isFalse);
      expect(draft.severity, Severity.medium);
      expect(draft.detections.first.depthIndex, 0.21);
      expect(draft.detections.last.hasWater, isTrue);
      expect(draft.averageConfidence, closeTo(0.75, 1e-9));
    });

    test('detect returns null when no pothole was found', () async {
      expect(await FakeBackend(detectFinds: false).api().detect(png, 'a.png'), isNull);
    });

    test('nearby asks for the point, radius and severity filter', () async {
      final backend = FakeBackend();
      final found = await backend.api().nearby(latitude: 18.52, longitude: 73.85, radiusM: 2000, majorOnly: true);

      expect(backend.requests.last.url.queryParameters,
          {'lat': '18.52', 'lng': '73.85', 'radius': '2000', 'major_only': 'true'});
      expect(found.first.distanceM, 140);
    });

    test('dashboard figures are parsed', () async {
      final data = await FakeBackend().api().dashboard();
      expect((data.total, data.unresolved, data.resolved, data.verified), (14, 10, 4, 11));
      expect(data.countOf(Severity.medium), 6);
      expect(data.week, hasLength(7));
      expect(data.hotspots.first, (area: 'Shivajinagar', count: 4));
    });

    test('reports an unreachable server clearly, without naming an address', () async {
      final api = ApiClient(
        baseUrl: 'http://server',
        client: MockClient((_) async => throw http.ClientException('Connection refused')),
      );
      await expectLater(
        api.login(email: 'a@b.co', password: 'x'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', startsWith('Cannot reach the server.'))),
      );
    });
  });

  group('AuthController', () {
    test('login stores the session, restore reuses it, logout clears it', () async {
      final backend = FakeBackend();
      final store = MemorySessionStore();
      final auth = AuthController(api: backend.api(signedIn: false), store: store);

      await auth.login(email: 'asha@example.com', password: 'correct horse');
      expect(auth.user!.email, 'asha@example.com');
      expect(store.session!.token, 'tok');

      final restored = AuthController(api: backend.api(signedIn: false), store: store);
      await restored.restore();
      expect(restored.user!.name, 'Asha');
      expect(restored.api.token, 'tok');

      await auth.logout();
      expect(auth.user, isNull);
      expect(store.session, isNull);
    });

    test('a failed login keeps the user signed out and reports why', () async {
      final auth = AuthController(api: FakeBackend().api(signedIn: false), store: MemorySessionStore());
      await auth.login(email: 'asha@example.com', password: 'nope');
      expect(auth.user, isNull);
      expect(auth.error, 'Incorrect email or password.');
    });
  });

  group('reporting a photo', () {
    ScanController scan(FakeBackend backend, {LocationProvider locate = noLocation, List<int>? submitted}) {
      return ScanController(
        api: backend.api(),
        locate: locate,
        picker: (_) async => photo(),
        onSubmitted: (report) => submitted?.add(report.id),
      );
    }

    test('nothing is sent until the user asks for detection, and nothing is public until they submit', () async {
      final backend = FakeBackend();
      final submitted = <int>[];
      final controller = scan(backend, submitted: submitted);

      expect(await controller.pickPhoto(fromCamera: false), isTrue);
      expect(controller.stage, ScanStage.review);
      expect(backend.requests, isEmpty);

      await controller.analyze();
      expect(controller.stage, ScanStage.result);
      expect(controller.result!.submitted, isFalse);
      expect(backend.where('POST', '/reports/7/submit'), isEmpty);
      expect(submitted, isEmpty);

      await controller.submit();
      expect(controller.stage, ScanStage.submitted);
      expect(controller.result!.submitted, isTrue);
      expect(submitted, [7]);
    });

    test('a gallery photo carries the location the user chose, or none', () async {
      final backend = FakeBackend();
      final controller = scan(backend);

      await controller.pickPhoto(fromCamera: false);
      expect(controller.draft!.canAnalyze, isTrue);
      controller.setDraftLocation((latitude: 17.385, longitude: 78.4867));
      await controller.analyze();

      final sent = backend.where('POST', '/detect').single as http.MultipartRequest;
      expect(sent.fields, {'latitude': '17.385', 'longitude': '78.4867'});
    });

    test('a camera photo cannot be analysed until the phone gives a location', () async {
      final backend = FakeBackend();
      var allowed = false;
      final controller = scan(
        backend,
        locate: () async =>
            allowed ? (latitude: 12.5, longitude: 77.5) : throw const LocationException(LocationProblem.serviceOff),
      );

      await controller.pickPhoto(fromCamera: true);
      expect(controller.draft!.canAnalyze, isFalse);
      expect(controller.draft!.locationProblem, LocationProblem.serviceOff);
      await controller.analyze();
      expect(backend.requests, isEmpty);

      // A camera photo's location comes only from the phone, never chosen by hand.
      controller.setDraftLocation((latitude: 1, longitude: 1));
      expect(controller.draft!.location, isNull);

      allowed = true;
      await controller.locateDraft();
      await controller.analyze();
      final sent = backend.where('POST', '/detect').single as http.MultipartRequest;
      expect(sent.fields, {'latitude': '12.5', 'longitude': '77.5'});
    });

    test('a failed analysis keeps the photo so it can be sent again', () async {
      final backend = FakeBackend(detectStatus: 503);
      final controller = scan(backend);

      await controller.pickPhoto(fromCamera: false);
      await controller.analyze();
      expect(controller.error, 'Model is down.');
      expect(controller.stage, ScanStage.review);
      expect(controller.draft, isNotNull);

      backend.detectStatus = 200;
      await controller.analyze();
      expect(controller.stage, ScanStage.result);
      expect(controller.error, isNull);
    });

    test('a photo with no pothole ends the flow without a report', () async {
      final controller = scan(FakeBackend(detectFinds: false));
      await controller.pickPhoto(fromCamera: false);
      await controller.analyze();
      expect(controller.stage, ScanStage.clear);
      expect(controller.result, isNull);
    });

    test('retaking or leaving discards the unsubmitted analysis on the server', () async {
      final backend = FakeBackend();
      final controller = scan(backend);

      await controller.pickPhoto(fromCamera: false);
      await controller.analyze();
      await controller.pickPhoto(fromCamera: false);
      expect(controller.stage, ScanStage.review);
      expect(backend.where('DELETE', '/reports/7'), hasLength(1));

      await controller.analyze();
      controller.clear();
      expect(controller.draft, isNull);
      expect(backend.where('DELETE', '/reports/7'), hasLength(2));
    });

    test('a submitted report is never deleted afterwards', () async {
      final backend = FakeBackend();
      final controller = scan(backend);
      await controller.pickPhoto(fromCamera: false);
      await controller.analyze();
      await controller.submit();
      controller.clear();
      expect(backend.where('DELETE', '/reports/7'), isEmpty);
    });

    test('cancelling the picker changes nothing', () async {
      final controller = ScanController(api: FakeBackend().api(), locate: noLocation, picker: (_) async => null);
      expect(await controller.pickPhoto(fromCamera: true), isFalse);
      expect(controller.draft, isNull);
    });
  });

  group('nearby alerts', () {
    test('a pothole coming into range alerts once, with vibration strength by severity', () async {
      final backend = FakeBackend(nearby: [potholeJson(distance: 120)]);
      final notifier = FakeNotifier();
      final state = _state(backend, notifier);

      await state.start();
      await state.refreshNearby();
      expect(notifier.permissionRequests, 1);
      expect(notifier.shown.single, (
        title: 'High severity pothole 120 m away',
        body: 'FC Road · drive carefully',
        urgent: true,
      ));

      // Still in range on the next check: no second alert.
      await state.refreshNearby();
      expect(notifier.shown, hasLength(1));

      // It leaves range and later comes back: that is a new warning.
      backend.nearby = [];
      await state.refreshNearby();
      backend.nearby = [potholeJson(distance: 300)];
      await state.refreshNearby();
      expect(notifier.shown, hasLength(2));
    });

    test('several new potholes become one alert, led by the most severe', () async {
      final backend = FakeBackend(nearby: [
        potholeJson(id: 1, severity: 'MED', distance: 90),
        potholeJson(id: 2, severity: 'LOW', distance: 40),
      ]);
      final notifier = FakeNotifier();
      final state = _state(backend, notifier);
      await state.start();
      await state.refreshNearby();

      expect(notifier.shown.single.title, '2 potholes nearby');
      expect(notifier.shown.single.body, 'Nearest medium severity is 90 m away · drive carefully');
      expect(notifier.shown.single.urgent, isFalse);
    });

    test('alerts can be switched off, and a pothole the user just reported stays quiet', () async {
      final backend = FakeBackend(nearby: [potholeJson(id: 7, distance: 5)]);
      final notifier = FakeNotifier();
      final state = _state(backend, notifier);
      state.acknowledge(7);
      await state.start();
      await state.refreshNearby();
      expect(notifier.shown, isEmpty);

      await state.setAlertsEnabled(false);
      backend.nearby = [potholeJson(id: 9, distance: 50)];
      await state.refreshNearby();
      expect(notifier.shown, isEmpty);
      expect(state.nearby.single.id, 9);
    });

    test('without a location nothing is searched and nothing alerts', () async {
      final backend = FakeBackend();
      final notifier = FakeNotifier();
      final state = _state(backend, notifier, locate: noLocation);
      await state.start();
      await state.refreshNearby();

      expect(state.locationProblem, LocationProblem.denied);
      expect(backend.where('GET', '/potholes/nearby'), isEmpty);
      expect(notifier.shown, isEmpty);
    });

    test('moving, or changing the radius or filter, searches again', () async {
      final backend = FakeBackend();
      final positions = StreamController<Coordinates>();
      final state = AppState(
        api: backend.api(),
        store: MemorySessionStore(),
        notifier: FakeNotifier(),
        locate: atPune,
        watch: () => positions.stream,
      );
      await state.start();
      await pumpEventQueue();
      final before = backend.where('GET', '/potholes/nearby').length;

      positions.add((latitude: 18.6, longitude: 73.9));
      await pumpEventQueue();
      state.setRadius(5000);
      state.setMajorOnly(true);
      await pumpEventQueue();

      final searches = backend.where('GET', '/potholes/nearby').toList();
      expect(searches.length, before + 3);
      expect(searches.last.url.queryParameters, {'lat': '18.6', 'lng': '73.9', 'radius': '5000', 'major_only': 'true'});
      await positions.close();
    });

    test('preferences are saved and restored', () async {
      final store = MemorySessionStore();
      final state = _state(FakeBackend(), FakeNotifier(), store: store);
      state.setRadius(2000);
      state.setMajorOnly(true);
      state.setDarkMode(true);
      await state.setAlertsEnabled(false);

      final restored = _state(FakeBackend(), FakeNotifier(), store: store);
      await restored.loadSettings();
      expect((restored.radiusM, restored.majorOnly, restored.darkMode, restored.alertsEnabled),
          (2000, true, true, false));
    });
  });

  group('the app', () {
    Future<FakeBackend> signIn(WidgetTester tester, {FakeBackend? backend, FakeNotifier? notifier}) async {
      final server = backend ?? FakeBackend();
      await tester.pumpWidget(PotholeApp(
        api: server.api(signedIn: false),
        store: MemorySessionStore(),
        locate: atPune,
        watch: noMovement,
        notifier: notifier ?? FakeNotifier(),
        picker: (_) async => photo(),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'asha@example.com');
      await tester.enterText(find.byType(TextFormField).last, 'correct horse');
      await tester.tap(find.text('Log In'));
      await tester.pumpAndSettle();
      return server;
    }

    testWidgets('signing in shows live data on every tab', (tester) async {
      final notifier = FakeNotifier();
      await signIn(tester, notifier: notifier);

      // Home
      expect(find.text('Road Safety'), findsOneWidget);
      expect(find.text('2 potholes nearby'), findsOneWidget);
      expect(find.text('1 high severity within 1.0 km · unresolved'), findsOneWidget);
      expect(find.text('FC Road'), findsWidgets);
      expect(notifier.shown.single.title, '2 potholes nearby');

      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();
      expect(find.text('Pothole Map'), findsOneWidget);
      // Three of the four reports have coordinates.
      expect(find.text('3 geo-tagged potholes'), findsOneWidget);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('2 geo-tagged potholes'), findsOneWidget);

      await tester.tap(find.text('Alerts'));
      await tester.pumpAndSettle();
      expect(find.text('Nearby Alerts'), findsOneWidget);
      expect(find.text('1 high severity pothole ahead'), findsOneWidget);
      expect(find.text('Nearest is 140 m away · drive carefully'), findsOneWidget);
      expect(find.text('2 within 1.0 km'), findsOneWidget);

      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();
      expect(find.text('Severity distribution'), findsOneWidget);
      expect(find.text('29%'), findsOneWidget); // 4 of 14 resolved
      expect(find.text('79%'), findsOneWidget); // 11 of 14 verified
      await tester.scrollUntilVisible(find.text('Kothrud'), 200);
      expect(find.text('Shivajinagar'), findsOneWidget);
    });

    testWidgets('reports can be searched and filtered, and open a detail page', (tester) async {
      await signIn(tester);
      await tester.scrollUntilVisible(find.text('View all'), 200);
      await tester.tap(find.text('View all'));
      await tester.pumpAndSettle();
      expect(find.text('All Reports'), findsOneWidget);
      expect(find.text('No location attached'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'baner');
      await tester.pumpAndSettle();
      expect(find.text('Baner Road'), findsOneWidget);
      expect(find.text('FC Road'), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Resolved').first);
      await tester.pumpAndSettle();
      expect(find.text('Baner Road'), findsOneWidget);
      expect(find.text('JM Road'), findsNothing);

      await tester.tap(find.text('Baner Road'));
      await tester.pumpAndSettle();
      expect(find.text('PH-0045'), findsOneWidget);
      expect(find.text('Marked repaired'), findsOneWidget);
      expect(find.text('Awaiting verification'), findsNothing);
      await tester.scrollUntilVisible(find.text('Open in Google Maps'), 200);
    });

    testWidgets('a photo goes through review, detection, result and submit', (tester) async {
      final backend = await signIn(tester);
      await tester.tap(find.byTooltip('Scan road'));
      await tester.pumpAndSettle();
      expect(find.text('Scan Road'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('Take a road photo'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('Review Photo'), findsOneWidget);
      expect(find.text("This phone's location"), findsOneWidget);
      expect(backend.where('POST', '/detect'), isEmpty);

      backend.holdDetect = Completer<void>();
      await tester.tap(find.text('Detect potholes'));
      await tester.pump();
      expect(find.text('Analyzing'), findsOneWidget);
      expect(find.text('Running AI detection'), findsOneWidget);
      backend.holdDetect!.complete();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      expect(find.text('Detection Result'), findsOneWidget);
      expect(find.text('Overall severity'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Avg conf.'), 200);
      expect(find.text('75%'), findsOneWidget); // average confidence
      await tester.scrollUntilVisible(find.text('Water in pothole, depth not measured'), 200);
      expect(find.text('Depth index 0.21'), findsOneWidget);
      expect(backend.where('POST', '/reports/7/submit'), isEmpty);

      await tester.scrollUntilVisible(find.text('Submit report'), 300);
      await tester.tap(find.text('Submit report'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('Report submitted'), findsOneWidget);
      expect(find.text('PH-0007'), findsOneWidget);
      expect(backend.where('POST', '/reports/7/submit'), hasLength(1));

      await tester.tap(find.text('Back to home'));
      await tester.pumpAndSettle();
      expect(find.text('Road Safety'), findsOneWidget);
      expect(backend.where('DELETE', '/reports/7'), isEmpty);
    });

    testWidgets('a camera photo without a location cannot be sent', (tester) async {
      final backend = FakeBackend();
      await tester.pumpWidget(PotholeApp(
        api: backend.api(signedIn: false),
        store: MemorySessionStore(),
        locate: noLocation,
        watch: noMovement,
        notifier: FakeNotifier(),
        picker: (_) async => photo(),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'asha@example.com');
      await tester.enterText(find.byType(TextFormField).last, 'correct horse');
      await tester.tap(find.text('Log In'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Scan road'));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.text('Take a road photo'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(find.text('Location permission was not granted.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      final detect = tester.widget<FilledButton>(
        find.ancestor(of: find.text('Detect potholes'), matching: find.bySubtype<FilledButton>()),
      );
      expect(detect.onPressed, isNull);
      await tester.scrollUntilVisible(find.text('Retake'), 200);
    });

    testWidgets('settings hold preferences and the account, and nothing about a server', (tester) async {
      await signIn(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Nearby pothole alerts'), findsOneWidget);
      expect(find.text('Alert radius'), findsOneWidget);
      expect(find.text('Device GPS active'), findsOneWidget);
      expect(find.text('asha@example.com'), findsOneWidget);
      expect(find.textContaining('Server'), findsNothing);
      expect(find.textContaining('server'), findsNothing);
      expect(find.textContaining('Backend'), findsNothing);
      expect(find.textContaining('URL'), findsNothing);

      // Dark mode repaints the whole app.
      final light = Theme.of(tester.element(find.text('Dark mode'))).brightness;
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      expect(light, Brightness.light);
      expect(Theme.of(tester.element(find.text('Dark mode'))).brightness, Brightness.dark);

      await tester.scrollUntilVisible(find.text('Log out'), 200);
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('the sign-in screen has no server setting', (tester) async {
      await tester.pumpWidget(PotholeApp(
        api: FakeBackend().api(signedIn: false),
        store: MemorySessionStore(),
        locate: atPune,
        watch: noMovement,
        notifier: FakeNotifier(),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.textContaining('Server'), findsNothing);
      expect(find.textContaining('server'), findsNothing);
    });

    testWidgets('every screen fits a small phone without overflowing', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await signIn(tester);

      for (final tab in ['Map', 'Alerts', 'Dashboard', 'Home']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('Scan road'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('From gallery'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('Add location'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Detect potholes'), 200);
      await tester.tap(find.text('Detect potholes'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('Detection Result'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Log out'), 200);
    });
  });

  group('formatting', () {
    test('distances and ages read naturally', () {
      expect(formatDistance(140.4), '140 m');
      expect(formatDistance(1000), '1.0 km');
      expect(formatDistance(2340), '2.3 km');
      final now = DateTime(2026, 10, 14, 12);
      expect(timeAgo(now.subtract(const Duration(seconds: 20)), now: now), 'just now');
      expect(timeAgo(now.subtract(const Duration(minutes: 12)), now: now), '12 min ago');
      expect(timeAgo(now.subtract(const Duration(hours: 3)), now: now), '3 h ago');
      expect(timeAgo(now.subtract(const Duration(days: 5)), now: now), '5 d ago');
      expect(formatDateTime(DateTime(2026, 10, 4, 9, 5)), '04 Oct, 09:05');
    });

    test('a pothole is named by road, then area, then a fallback', () {
      Pothole p({String? address, String? area, double? latitude}) => Pothole(
            id: 3,
            severity: Severity.low,
            confidence: 0.5,
            detectionCount: 1,
            status: 'in_review',
            createdAt: DateTime(2026),
            address: address,
            area: area,
            latitude: latitude,
            longitude: latitude,
          );
      expect(p(address: 'FC Road', area: 'Shivajinagar').title, 'FC Road');
      expect(p(area: 'Shivajinagar').title, 'Shivajinagar');
      expect(p(latitude: 18.5).title, 'Reported pothole');
      expect(p().title, 'No location attached');
      expect((p().code, p().isVerified, p().isResolved, p().statusLabel), ('PH-0003', true, false, 'Unresolved'));
    });
  });
}
