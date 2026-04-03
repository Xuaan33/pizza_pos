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

  Future<void> loadFromSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    final lastLogin = prefs.getString('last_login');
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
    final itemsGroupsJson = prefs.getString('item_groups');
    final baseUrl = prefs.getString('base_url') ?? 'https://asdf.byondwave.com';
    final merchantId = prefs.getString('merchant_id');
    final printMerchantReceiptCopy = prefs.getInt('print_merchant_receipt_copy');
    final enableFiuu = prefs.getInt('enable_fiuu');
    final cashDrawerPinNeeded = prefs.getInt('cash_drawer_pin_needed');

    final secure = await AuthService.readSecureSession();
    final sid = secure['sid'];
    final apiKey = secure['api_key'];
    final apiSecret = secure['api_secret'];
    final cashDrawerPin = secure['cash_drawer_pin'] ?? '';

    // Parse opening date
    DateTime? openingDate;
    if (openingDateString != null) {
      try {
        openingDate = DateTime.parse(openingDateString);
      } catch (e) {
        debugPrint('Error parsing opening date: $e');
      }
    }

    List<dynamic> itemsGroups = [];
    if (itemsGroupsJson != null) {
      try {
        itemsGroups = jsonDecode(itemsGroupsJson);
      } catch (e) {
        debugPrint('Error parsing item groups: $e');
      }
    }

    // 7-day absolute session expiration
    if (lastLogin != null) {
      final lastLoginDate = DateTime.parse(lastLogin);
      if (DateTime.now().difference(lastLoginDate) > const Duration(days: 7)) {
        await logout();
        return;
      }
    }

    if (sid != null &&
        apiKey != null &&
        apiSecret != null &&
        username != null &&
        posProfile != null &&
        branch != null &&
        merchantId != null) {
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
        openingDate: openingDate,
        itemsGroups: itemsGroups,
        baseUrl: baseUrl,
        merchantId: merchantId,
        printMerchantReceiptCopy: printMerchantReceiptCopy ?? 0,
        enableFiuu: enableFiuu ?? 0,
        cashDrawerPinNeeded: cashDrawerPinNeeded ?? 0,
        cashDrawerPin: cashDrawerPin,
      );
    } else {
      state = const AuthState.unauthenticated();
    }
  }

  Future<void> loadSession({bool forceRefresh = false}) async {
    try {
      debugPrint('🔐 loadSession called - forceRefresh: $forceRefresh');

      final prefs = await SharedPreferences.getInstance();
      final lastLogin = prefs.getString('last_login');
      final username = prefs.getString('username');
      final merchantId = prefs.getString('merchant_id');

      final results = await Future.wait([
        AuthService.readSecureSession(),
        AuthService.getStoredPassword(),
      ]);
      final secure = results[0] as Map<String, String?>;
      final sid = secure['sid'];
      final password = results[1] as String?;

      debugPrint(
          '📱 Stored credentials - username: $username, password: ${password != null ? "***" : "null"}, merchantId: $merchantId');
      debugPrint('📱 Session info - sid: $sid, lastLogin: $lastLogin');

      final bool shouldAutoLogin = forceRefresh ||
          sid == null ||
          sid.isEmpty ||
          username == null ||
          _isSessionStale(lastLogin);

      if (shouldAutoLogin &&
          username != null &&
          password != null &&
          merchantId != null) {
        await _performAutoLogin(username, password, merchantId);
      } else {
        await loadFromSharedPreferences();
      }
    } catch (e) {
      debugPrint('Error in loadSession: $e');
      await loadFromSharedPreferences();
    }
  }

  bool _isSessionStale(String? lastLogin) {
    if (lastLogin == null) {
      debugPrint('⏰ Session stale: no last login date');
      return true;
    }
    try {
      final lastLoginDate = DateTime.parse(lastLogin);
      return DateTime.now().difference(lastLoginDate) >
          const Duration(hours: 4);
    } catch (e) {
      return true;
    }
  }

  Future<void> _performAutoLogin(
      String username, String password, String merchantId) async {
    try {
      final response =
          await AuthService().login(username, password, merchantId);

      if (response['success'] == true) {
        await _saveLoginData(response);
        await loadFromSharedPreferences();
      } else {
        debugPrint('Auto-login failed: ${response['message']}');
        await loadFromSharedPreferences();
      }
    } catch (e) {
      debugPrint('Auto-login error: $e');
      await loadFromSharedPreferences();
    }
  }

  Future<void> login(
      String username, String password, String merchantId) async {
    try {
      final response =
          await AuthService().login(username, password, merchantId);

      if (response['success'] == true) {
        await AuthService.storeCredentials(username, password, merchantId);
        await _saveLoginData(response);

        final prefs = await SharedPreferences.getInstance();
        DateTime? openingDate;

        if (response['opening_date'] != null) {
          try {
            openingDate = DateTime.parse(response['opening_date']);
            await prefs.setString('opening_date', response['opening_date']);
          } catch (e) {
            debugPrint('Error parsing opening date from response: $e');
          }
        }

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
          tier: response['tier'] ?? 'tier 1',
          printKitchenOrder: response['print_kitchen_order'] ?? 1,
          openingDate: openingDate,
          itemsGroups: List<dynamic>.from(response['item_groups'] ?? []),
          baseUrl: response['base_url'] ?? 'https://asdf.byondwave.com',
          merchantId: response['merchant_id'] ?? merchantId,
          printMerchantReceiptCopy:
              response['print_merchant_receipt_copy'] ?? 0,
          enableFiuu: response['enable_fiuu'] ?? 0,
          cashDrawerPinNeeded: response['cash_drawer_pin_needed'] ?? 0,
          cashDrawerPin: response['cash_drawer_pin'] ?? '',
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

  Future<void> _saveLoginData(Map<String, dynamic> response) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('username', response['username']);
    await prefs.setString('email', response['email']);
    await prefs.setString('full_name', response['full_name']);
    await prefs.setString('pos_profile', response['pos_profile']);
    await prefs.setString('branch', response['branch']);
    await prefs.setString(
        'payment_methods', jsonEncode(response['mode_of_payment']));
    await prefs.setString('taxes', jsonEncode(response['taxes']));
    await prefs.setBool('has_opening', response['has_opening']);
    await prefs.setInt('print_kitchen_order', response['print_kitchen_order']);
    await prefs.setString('tier', response['tier'] ?? 'tier 1');
    await prefs.setString('last_login', DateTime.now().toIso8601String());
    await prefs.setString(
        'item_groups', jsonEncode(response['item_groups'] ?? []));
    await prefs.setString(
        'base_url', response['base_url'] ?? 'https://asdf.byondwave.com');
    await prefs.setString('merchant_id', response['merchant_id']);
    await prefs.setInt('print_merchant_receipt_copy',
        response['print_merchant_receipt_copy'] ?? 0);
    await prefs.setInt('enable_fiuu', response['enable_fiuu'] ?? 0);
    await prefs.setInt(
        'cash_drawer_pin_needed', response['cash_drawer_pin_needed'] ?? 0);

    await AuthService.writeSecureSession(
      sid: response['sid'],
      apiKey: response['api_key'],
      apiSecret: response['api_secret'],
      cashDrawerPin: response['cash_drawer_pin'] ?? '',
    );
  }

  Future<void> refreshSession() async {
    await loadSession(forceRefresh: true);
  }

  Future<void> updateOpeningStatus(bool hasOpening,
      {DateTime? openingDate}) async {
    state.maybeWhen(
      authenticated: (
        sid,
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
        oldOpeningDate,
        itemsGroups,
        baseUrl,
        merchantId,
        printMerchantReceiptCopy,
        enableFiuu,
        cashDrawerPinNeeded,
        cashDrawerPin,
      ) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('has_opening', hasOpening);

        final newOpeningDate = openingDate ?? oldOpeningDate;
        if (hasOpening && newOpeningDate != null) {
          await prefs.setString(
              'opening_date', newOpeningDate.toIso8601String());
        } else if (!hasOpening) {
          await prefs.remove('opening_date');
        }

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
          itemsGroups: itemsGroups,
          baseUrl: baseUrl,
          merchantId: merchantId,
          printMerchantReceiptCopy: printMerchantReceiptCopy,
          enableFiuu: enableFiuu,
          cashDrawerPinNeeded: cashDrawerPinNeeded,
          cashDrawerPin: cashDrawerPin,
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
    await AuthService.clearStoredCredentials();
    await AuthService.logout();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
