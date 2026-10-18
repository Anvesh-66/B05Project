import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/report.dart';
import 'api_client.dart';

/// Keeps the signed-in session and the user's preferences between app launches.
abstract class SessionStore {
  Future<AuthSession?> read();
  Future<void> write(AuthSession session);
  Future<void> clear();

  /// A saved preference such as the alert radius, or null when never set.
  /// Preferences outlive signing out.
  Future<String?> readSetting(String key);
  Future<void> writeSetting(String key, String value);
}

class SecureSessionStore implements SessionStore {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'token';
  static const _userKey = 'user';

  @override
  Future<AuthSession?> read() async {
    final token = await _storage.read(key: _tokenKey);
    final user = await _storage.read(key: _userKey);
    if (token == null || user == null) return null;
    return AuthSession(
      token: token,
      user: AppUser.fromJson(jsonDecode(user) as Map<String, dynamic>),
    );
  }

  @override
  Future<void> write(AuthSession session) async {
    await _storage.write(key: _tokenKey, value: session.token);
    await _storage.write(key: _userKey, value: jsonEncode(session.user.toJson()));
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }

  @override
  Future<String?> readSetting(String key) => _storage.read(key: 'setting_$key');

  @override
  Future<void> writeSetting(String key, String value) => _storage.write(key: 'setting_$key', value: value);
}

class MemorySessionStore implements SessionStore {
  AuthSession? session;
  final settings = <String, String>{};

  @override
  Future<AuthSession?> read() async => session;

  @override
  Future<void> write(AuthSession session) async => this.session = session;

  @override
  Future<void> clear() async => session = null;

  @override
  Future<String?> readSetting(String key) async => settings[key];

  @override
  Future<void> writeSetting(String key, String value) async => settings[key] = value;
}
