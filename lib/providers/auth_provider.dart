import 'dart:convert';

import 'package:flutter/material.dart';
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
    final paymentMethodsJson = prefs.getString('payment_methods');
    final taxesJson = prefs.getString('taxes');
    final hasOpening = prefs.getBool('has_opening') ?? false;
    final tier = prefs.getString('tier');
    final printKitchenOrder = prefs.getInt('print_kitchen_order');
    final openingDateString = prefs.getString('opening_date');

    // Parse opening date if it exists
    DateTime? openingDate;
    if (openingDateString != null) {
      try {
        openingDate = DateTime.parse(openingDateString);
      } catch (e) {
        debugPrint('Error parsing opening date: $e');
      }
    }

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
        paymentMethods: paymentMethodsJson != null
            ? List<Map<String, dynamic>>.from(jsonDecode(paymentMethodsJson))
            : [],
        taxes: taxesJson != null
            ? List<Map<String, dynamic>>.from(jsonDecode(taxesJson))
            : [],
        hasOpening: hasOpening,
        tier: tier ?? '',
        printKitchenOrder: printKitchenOrder ?? 1,
        openingDate: openingDate, // Use the parsed opening date
      );
    } else {
      state = const AuthState.unauthenticated();
    }
  }

  Future<void> login(String username, String password) async {
    try {
      final response = await AuthService().login(username, password);

      if (response['success'] == true) {
        final prefs = await SharedPreferences.getInstance();

        await prefs.setString('sid', response['sid']);
        await prefs.setString('api_key', response['api_key']);
        await prefs.setString('api_secret', response['api_secret']);
        await prefs.setString('username', response['username']);
        await prefs.setString('email', response['email']);
        await prefs.setString('full_name', response['full_name']);
        await prefs.setString('pos_profile', response['pos_profile']);
        await prefs.setString('branch', response['branch']);
        await prefs.setString(
            'payment_methods', jsonEncode(response['mode_of_payment']));
        await prefs.setString('taxes', jsonEncode(response['taxes']));
        await prefs.setBool('has_opening', response['has_opening']);
        await prefs.setString('tier',
            response['tier'] ?? 'tier2'); // Default to tier2 if not provided
        await prefs.setString('last_login', DateTime.now().toIso8601String());

        DateTime? openingDate;

        // First, check if opening date is provided in the login response
        if (response['opening_date'] != null) {
          try {
            openingDate = DateTime.parse(response['opening_date']);
            await prefs.setString('opening_date', response['opening_date']);
          } catch (e) {
            debugPrint('Error parsing opening date from response: $e');
          }
        }

        // If not in response but hasOpening is true, try to load from prefs
        if (openingDate == null && response['has_opening'] == true) {
          final existingOpeningDate = prefs.getString('opening_date');
          if (existingOpeningDate != null) {
            try {
              openingDate = DateTime.parse(existingOpeningDate);
            } catch (e) {
              debugPrint('Error parsing existing opening date: $e');
            }
          }
        }

        // If still no date but hasOpening is true, use current date as fallback
        if (openingDate == null && response['has_opening'] == true) {
          openingDate = DateTime.now();
          await prefs.setString('opening_date', openingDate.toIso8601String());
        }

        state = AuthState.authenticated(
          sid: response['sid'],
          apiKey: response['api_key'],
          apiSecret: response['api_secret'],
          username: response['username'],
          email: response['email'],
          fullName: response['full_name'],
          posProfile: response['pos_profile'],
          branch: response['branch'],
          paymentMethods:
              List<Map<String, dynamic>>.from(response['mode_of_payment']),
          taxes: List<Map<String, dynamic>>.from(response['taxes']),
          hasOpening: response['has_opening'],
          tier: response['tier'] ?? 'tier2', // Default to tier2 if not provided
          printKitchenOrder: response['print_kitchen_order'] ?? 1,
          openingDate: openingDate, // Add the opening date here
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

  Future<void> updateOpeningStatus(bool hasOpening,
      {DateTime? openingDate}) async {
    state.maybeWhen(
      authenticated: (sid,
          apiKey,
          apiSecret,
          username,
          email,
          fullName,
          posProfile,
          branch,
          paymentMethods,
          taxes,
          _,
          tier,
          printKitchenOrder,
          oldOpeningDate) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('has_opening', hasOpening);

        final newOpeningDate = openingDate ?? oldOpeningDate;
        if (hasOpening && newOpeningDate != null) {
          await prefs.setString(
              'opening_date', newOpeningDate.toIso8601String());
        } else if (!hasOpening) {
          await prefs.remove('opening_date');
        }

        // Update state with the new opening date
        state = AuthState.authenticated(
          sid: sid,
          apiKey: apiKey,
          apiSecret: apiSecret,
          username: username,
          email: email,
          fullName: fullName,
          posProfile: posProfile,
          branch: branch,
          paymentMethods: paymentMethods,
          taxes: taxes,
          hasOpening: hasOpening,
          tier: tier,
          printKitchenOrder: printKitchenOrder,
          openingDate: hasOpening ? newOpeningDate : null,
        );
      },
      orElse: () {},
    );
  }

  Future<void> markOpeningCreated({DateTime? openingDate}) async {
    await updateOpeningStatus(true, openingDate: openingDate ?? DateTime.now());
  }

  Future<void> markOpeningClosed() async {
    await updateOpeningStatus(false);
  }

// Add method to get opening date
  Future<DateTime?> getOpeningDate() async {
    final prefs = await SharedPreferences.getInstance();
    final openingDateString = prefs.getString('opening_date');
    if (openingDateString != null) {
      return DateTime.parse(openingDateString);
    }
    return null;
  }

  Future<void> logout() async {
    state = const AuthState.unauthenticated();
    await AuthService.logout();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
