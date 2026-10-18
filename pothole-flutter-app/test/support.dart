import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pothole_detector/services/alert_notifier.dart';
import 'package:pothole_detector/services/api_client.dart';
import 'package:pothole_detector/services/location.dart';

const user = {'id': 1, 'name': 'Asha', 'email': 'asha@example.com', 'role': 'user'};

const Coordinates pune = (latitude: 18.5204, longitude: 73.8567);

Future<Coordinates> atPune() async => pune;
Future<Coordinates> noLocation() async => throw const LocationException(LocationProblem.denied);
Stream<Coordinates> noMovement() => const Stream.empty();

/// A 1x1 transparent PNG, so photo previews have something real to decode.
final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

XFile photo() => XFile.fromData(png, name: 'road.png');

Map<String, dynamic> potholeJson({
  int id = 48,
  String severity = 'HIGH',
  String status = 'pending',
  String? address = 'FC Road',
  String? area = 'Shivajinagar',
  double? latitude = 18.5212,
  double? longitude = 73.8551,
  double? distance,
  bool mine = false,
}) =>
    {
      'id': id,
      'severity': severity,
      'confidence': 0.94,
      'detection_count': 2,
      'status': status,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'area': area,
      'created_at': DateTime.now().toUtc().subtract(const Duration(hours: 2)).toIso8601String(),
      'resolved_at': null,
      'mine': mine,
      'distance_m': ?distance,
    };

Map<String, dynamic> reportJson({int id = 7, bool submitted = false, bool located = true}) => {
      'id': id,
      'status': 'pending',
      'risk': 'MED',
      'detection_count': 2,
      'severe_count': 1,
      'confidence': 0.9,
      'latitude': located ? 18.5204 : null,
      'longitude': located ? 73.8567 : null,
      'address': located ? 'FC Road' : null,
      'area': located ? 'Shivajinagar' : null,
      'submitted': submitted,
      'created_at': '2026-10-04T10:00:00Z',
      'resolved_at': null,
      'reporter_name': 'Asha',
      'reporter_email': 'asha@example.com',
      'detections': [
        {'class_name': 'pothole', 'confidence': 0.9, 'severity': 'Severe', 'depth_index': 0.21, 'has_water': false},
        {'class_name': 'pothole', 'confidence': 0.6, 'severity': 'Not Severe', 'depth_index': null, 'has_water': true},
      ],
    };

final dashboardJson = {
  'total': 14,
  'unresolved': 10,
  'resolved': 4,
  'verified': 11,
  'high': 5,
  'medium': 6,
  'low': 3,
  'week': [
    for (var i = 6; i >= 0; i--)
      {
        'date': DateTime.now().toUtc().subtract(Duration(days: i)).toIso8601String().substring(0, 10),
        'count': [0, 2, 1, 0, 3, 1, 2][6 - i],
      },
  ],
  'hotspots': [
    {'area': 'Shivajinagar', 'count': 4},
    {'area': 'Kothrud', 'count': 2},
  ],
};

/// A stand-in backend. Everything it is asked is recorded in [requests].
class FakeBackend {
  FakeBackend({this.detectFinds = true, this.detectStatus = 200, List<Map<String, dynamic>>? potholes, this.nearby})
      : potholes = potholes ??
            [
              potholeJson(),
              potholeJson(id: 47, severity: 'MED', address: 'JM Road', latitude: 18.5186, longitude: 73.8592),
              potholeJson(id: 45, severity: 'LOW', status: 'resolved', address: 'Baner Road', area: 'Baner'),
              potholeJson(id: 44, severity: 'HIGH', address: null, area: null, latitude: null, longitude: null),
            ];

  /// Whether /detect finds a pothole, and the status it answers with.
  bool detectFinds;
  int detectStatus;
  List<Map<String, dynamic>> potholes;

  /// What /potholes/nearby returns; defaults to the located, unresolved [potholes].
  List<Map<String, dynamic>>? nearby;

  /// When set, /detect waits for this before answering, so "analyzing" can be observed.
  Completer<void>? holdDetect;

  final requests = <http.BaseRequest>[];

  Iterable<http.BaseRequest> where(String method, String path) =>
      requests.where((r) => r.method == method && r.url.path == path);

  late final client = MockClient.streaming((request, _) async {
    requests.add(request);
    http.StreamedResponse reply(Object? body, [int status = 200]) => http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode(body))),
          status,
          headers: {'content-type': 'application/json'},
        );

    final path = request.url.path;
    if (path == '/auth/login' || path == '/auth/register') {
      final body = jsonDecode((request as http.Request).body) as Map<String, dynamic>;
      if (body['password'] != 'correct horse') return reply({'detail': 'Incorrect email or password.'}, 401);
      return reply({'access_token': 'tok', 'user': user});
    }
    if (request.headers['Authorization'] != 'Bearer tok') {
      return reply({'detail': 'Not signed in, or the session has expired.'}, 401);
    }
    if (request.method == 'POST' && path == '/detect') {
      await holdDetect?.future;
      if (detectStatus != 200) return reply({'detail': 'Model is down.'}, detectStatus);
      final located = (request as http.MultipartRequest).fields.containsKey('latitude');
      return reply({'report': detectFinds ? reportJson(located: located) : null});
    }
    if (request.method == 'POST' && path == '/reports/7/submit') return reply(reportJson(submitted: true));
    if (request.method == 'DELETE' && path == '/reports/7') return http.StreamedResponse(const Stream.empty(), 204);
    if (path == '/potholes') return reply(potholes);
    if (path == '/potholes/nearby') {
      return reply(nearby ??
          [
            for (final (index, p) in potholes.indexed)
              if (p['latitude'] != null && p['status'] != 'resolved') {...p, 'distance_m': 140.0 + index * 260},
          ]);
    }
    if (path == '/dashboard') return reply(dashboardJson);
    return reply({'detail': 'Not found'}, 404);
  });

  ApiClient api({bool signedIn = true}) =>
      ApiClient(baseUrl: 'http://server', client: client)..token = signedIn ? 'tok' : null;
}

/// Records alerts instead of buzzing a phone.
class FakeNotifier implements AlertNotifier {
  final shown = <({String title, String body, bool urgent})>[];
  int permissionRequests = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> show({required String title, required String body, required bool urgent}) async {
    shown.add((title: title, body: body, urgent: urgent));
  }
}
