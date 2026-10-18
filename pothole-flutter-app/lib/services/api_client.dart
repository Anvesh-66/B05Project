import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/pothole.dart';
import '../models/report.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final AppUser user;
}

/// Client for the FastAPI backend in `pothole-detection-app/`.
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl, Duration? timeout})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? apiBaseUrl,
        timeout = timeout ?? apiTimeout;

  final http.Client _client;

  /// Where the backend lives. Fixed when the app is built (see config.dart).
  final String baseUrl;
  final Duration timeout;

  /// Sent as a bearer token on every request once the user is signed in.
  String? token;

  /// Called when the server rejects [token], so the app can sign the user out.
  void Function()? onUnauthorized;

  Map<String, String> get authHeaders =>
      token == null ? const {} : {'Authorization': 'Bearer $token'};

  Uri reportImageUri(int reportId) => Uri.parse('$baseUrl/reports/$reportId/image');

  Future<AuthSession> login({required String email, required String password}) {
    return _authenticate('/auth/login', {'email': email, 'password': password});
  }

  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
  }) {
    return _authenticate('/auth/register', {'name': name, 'email': email, 'password': password});
  }

  Future<AuthSession> _authenticate(String path, Map<String, String> body) async {
    final request = http.Request('POST', Uri.parse('$baseUrl$path'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body);
    // A 401 here means wrong credentials, not an expired session.
    final json = _decode(await _send(request, signOutOn401: false));
    return _parse(() => AuthSession(
          token: json['access_token'] as String,
          user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
        ));
  }

  /// Sends a photo for analysis. Returns a draft report for the user to review, or
  /// null when the server found no pothole (nothing is kept in that case).
  Future<Report?> detect(
    Uint8List imageBytes,
    String filename, {
    double? latitude,
    double? longitude,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/detect'))
      ..files.add(http.MultipartFile.fromBytes('file', imageBytes, filename: filename));
    if (latitude != null && longitude != null) {
      request.fields['latitude'] = latitude.toString();
      request.fields['longitude'] = longitude.toString();
    }
    final json = _decode(await _send(request));
    return _parse(() {
      final report = json['report'] as Map<String, dynamic>?;
      return report == null ? null : Report.fromJson(report);
    });
  }

  /// Turns the draft [id] into a real report that everyone can see.
  Future<Report> submitDraft(int id) async {
    final json = _decode(await _send(http.Request('POST', Uri.parse('$baseUrl/reports/$id/submit'))));
    return _parse(() => Report.fromJson(json as Map<String, dynamic>));
  }

  /// Throws away the draft [id], for example when the user retakes the photo.
  Future<void> discardDraft(int id) async {
    await _send(http.Request('DELETE', Uri.parse('$baseUrl/reports/$id')));
  }

  /// Every submitted pothole, newest first.
  Future<List<Pothole>> potholes() async {
    final json = _decode(await _send(http.Request('GET', Uri.parse('$baseUrl/potholes'))));
    return _parsePotholes(json);
  }

  /// Unresolved potholes within [radiusM] metres, most severe first, then nearest.
  Future<List<Pothole>> nearby({
    required double latitude,
    required double longitude,
    required int radiusM,
    bool majorOnly = false,
  }) async {
    final uri = Uri.parse('$baseUrl/potholes/nearby').replace(queryParameters: {
      'lat': latitude.toString(),
      'lng': longitude.toString(),
      'radius': radiusM.toString(),
      if (majorOnly) 'major_only': 'true',
    });
    return _parsePotholes(_decode(await _send(http.Request('GET', uri))));
  }

  Future<DashboardData> dashboard() async {
    final json = _decode(await _send(http.Request('GET', Uri.parse('$baseUrl/dashboard'))));
    return _parse(() => DashboardData.fromJson(json as Map<String, dynamic>));
  }

  static List<Pothole> _parsePotholes(dynamic json) => _parse(
      () => (json as List<dynamic>).map((p) => Pothole.fromJson(p as Map<String, dynamic>)).toList());

  Future<http.Response> _send(http.BaseRequest request, {bool signOutOn401 = true}) async {
    request.headers.addAll(authHeaders);

    final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw ApiException('The server did not respond within ${timeout.inSeconds}s.');
    } on SocketException {
      throw ApiException(_unreachableMessage);
    } on http.ClientException {
      throw ApiException(_unreachableMessage);
    }

    if (response.statusCode >= 200 && response.statusCode < 300) return response;
    if (response.statusCode == 401 && signOutOn401) onUnauthorized?.call();
    throw ApiException(_errorDetail(response), statusCode: response.statusCode);
  }

  static const _unreachableMessage =
      'Cannot reach the server. Check your internet connection and try again.';

  static dynamic _decode(http.Response response) {
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw ApiException('Server returned an invalid response.');
    }
  }

  /// Runs [build] over decoded JSON, turning a wrong shape into an [ApiException].
  static T _parse<T>(T Function() build) {
    try {
      return build();
    } on TypeError {
      throw ApiException('Server returned an invalid response.');
    } on NoSuchMethodError {
      throw ApiException('Server returned an invalid response.');
    } on FormatException {
      throw ApiException('Server returned an invalid response.');
    }
  }

  static String _errorDetail(http.Response response) {
    try {
      final detail = (jsonDecode(response.body) as Map<String, dynamic>)['detail'];
      if (detail is String) return detail;
      // Validation errors arrive as a list of {msg: ...} entries.
      if (detail is List && detail.isNotEmpty) return detail.first['msg'].toString();
    } catch (_) {
      // Not the usual error shape; fall through.
    }
    return 'Server error ${response.statusCode}.';
  }

  void close() => _client.close();
}
