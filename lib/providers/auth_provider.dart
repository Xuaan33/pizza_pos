import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiok_pos_android_app/models/auth_state.dart';
import 'package:shiok_pos_android_app/service/auth_service.dart';

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState.initial()) {
    loadSession();
  }

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final lastLogin = prefs.getString('last_login');
    final sid = prefs.getString('sid');
    final apiKey = prefs.getString('api_key');
    final apiSecret = prefs.getString('api_secret');
    final username = prefs.getString('username');
    final email = prefs.getString('email');
    final fullName = prefs.getString('full_name');
    final posProfile = prefs.getString('pos_profile');
    final branch = prefs.getString('branch');

    // Add session expiration (e.g., 7 days)
    if (lastLogin != null) {
      final lastLoginDate = DateTime.parse(lastLogin);
      if (DateTime.now().difference(lastLoginDate) > Duration(days: 7)) {
        await logout();
        return;
      }
    }

    if (sid != null &&
        apiKey != null &&
        apiSecret != null &&
        username != null &&
        posProfile != null &&
        branch != null) {
      state = AuthState.authenticated(
        sid: sid,
        apiKey: apiKey,
        apiSecret: apiSecret,
        username: username,
        email: email ?? '',
        fullName: fullName ?? username,
        posProfile: posProfile,
        branch: branch,
      );
    } else {
      state = const AuthState.unauthenticated();
    }
  }

  Future<void> login(String username, String password) async {
    try {
      final response = await AuthService().login(username, password);

      if (response['success'] == true) {
        final message = response['message'];
        final prefs = await SharedPreferences.getInstance();

        await prefs.setString('sid', message['sid']);
        await prefs.setString('api_key', message['api_key']);
        await prefs.setString('api_secret', message['api_secret']);
        await prefs.setString('username', message['username']);
        await prefs.setString('email', message['email'] ?? '');
        await prefs.setString(
            'full_name', message['full_name'] ?? message['username']);
        await prefs.setString('pos_profile', message['pos_profile']);
        await prefs.setString('branch', message['branch']);

        state = AuthState.authenticated(
          sid: message['sid'],
          apiKey: message['api_key'],
          apiSecret: message['api_secret'],
          username: message['username'],
          email: message['email'] ?? '',
          fullName: message['full_name'] ?? message['username'],
          posProfile: message['pos_profile'],
          branch: message['branch'],
        );
      } else {
        state = const AuthState.unauthenticated();
        throw Exception(response['message'] ?? 'Login failed');
      }
    } catch (e) {
      state = const AuthState.unauthenticated();
      rethrow;
    }
  }

  Future<void> logout() async {
     state = const AuthState.unauthenticated();
    // Then clear all stored preferences
    await AuthService.logout();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});