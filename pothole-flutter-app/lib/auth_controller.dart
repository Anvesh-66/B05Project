import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/report.dart';
import 'services/api_client.dart';
import 'services/session_store.dart';

class AuthController extends ChangeNotifier {
  AuthController({required this.api, required this.store}) {
    api.onUnauthorized = logout;
  }

  final ApiClient api;
  final SessionStore store;

  AppUser? user;

  /// True until the saved session has been checked at startup.
  bool restoring = true;
  bool busy = false;
  String? error;

  Future<void> restore() async {
    try {
      final session = await store.read();
      if (session != null) {
        api.token = session.token;
        user = session.user;
        // Save token to SharedPreferences for background tasks
        await _saveTokenForBackground(session.token);
      }
    } catch (_) {
      // Unreadable storage is treated as signed out.
    }
    restoring = false;
    notifyListeners();
  }

  Future<void> login({required String email, required String password}) {
    return _signIn(() => api.login(email: email, password: password));
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) {
    return _signIn(() => api.register(name: name, email: email, password: password));
  }

  Future<void> _signIn(Future<AuthSession> Function() request) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final session = await request();
      api.token = session.token;
      user = session.user;
      await store.write(session);
      // Save token to SharedPreferences for background tasks
      await _saveTokenForBackground(session.token);
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Unexpected error: $e';
    }
    busy = false;
    notifyListeners();
  }

  /// Save auth token to SharedPreferences for background tasks to access
  Future<void> _saveTokenForBackground(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
      await prefs.setString('api_base_url', api.baseUrl);
    } catch (e) {
      print('Error saving token for background: $e');
    }
  }

  void clearError() {
    if (error == null) return;
    error = null;
    notifyListeners();
  }

  Future<void> logout() async {
    if (user == null) return;
    api.token = null;
    user = null;
    notifyListeners();
    try {
      await store.clear();
      // Clear token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
      await prefs.remove('api_base_url');
    } catch (_) {
      // The in-memory session is already gone; nothing more to do.
    }
  }
}
