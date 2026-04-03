import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keys stored in flutter_secure_storage (Android Keystore / iOS Keychain).
/// These are the only values that are cryptographically protected at rest.
class _SecureKeys {
  static const password = 'secure_password';
  static const sid = 'secure_sid';
  static const apiKey = 'secure_api_key';
  static const apiSecret = 'secure_api_secret';
  static const cashDrawerPin = 'secure_cash_drawer_pin';
}

class AuthService {
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<Map<String, dynamic>> autoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('username');
      final merchantId = prefs.getString('merchant_id');
      final password = await getStoredPassword();

      if (username == null || password == null || merchantId == null) {
        return {
          'success': false,
          'message': 'No saved credentials found',
        };
      }

      return await login(username, password, merchantId);
    } catch (e) {
      return {
        'success': false,
        'message': 'Auto-login failed: $e',
      };
    }
  }

  /// Stores the username and merchantId in SharedPreferences (non-sensitive),
  /// and the password exclusively in flutter_secure_storage.
  static Future<void> storeCredentials(
      String username, String password, String merchantId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', username);
    await prefs.setString('merchant_id', merchantId);
    // Password goes to secure storage — never to SharedPreferences
    await _secureStorage.write(key: _SecureKeys.password, value: password);
  }

  static Future<void> clearStoredCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove('username'),
      _secureStorage.delete(key: _SecureKeys.password),
    ]);
  }

  Future<Map<String, dynamic>> login(
      String username, String password, String merchantId) async {
    try {
      final response = await http.post(
        Uri.parse(
            'https://shiokpos.byondwave.com/api/method/shiok_pos_admin.api.v1.login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
          'merchant_id': merchantId,
        }),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        final message = responseData['message'];
        return {
          'success': true,
          'message': message['message'] ?? 'Login successful',
          'sid': message['sid'] ?? '',
          'api_key': message['api_key'] ?? '',
          'api_secret': message['api_secret'] ?? '',
          'username': message['username'] ?? '',
          'email': message['email'] ?? '',
          'full_name': message['full_name'] ?? message['username'] ?? '',
          'pos_profile': message['pos_profile'] ?? '',
          'branch': message['branch'] ?? '',
          'mode_of_payment': message['mode_of_payment'] ?? [],
          'taxes': message['taxes'] ?? [],
          'has_opening': message['has_opening'] ?? false,
          'tier': message['tier'],
          'print_kitchen_order': message['print_kitchen_order'] ?? 1,
          'item_groups': message['item_groups'] ?? [],
          'base_url': message['url'] ?? 'https://asdf.byondwave.com',
          'merchant_id': message['merchant_id'] ?? merchantId,
          'print_merchant_receipt_copy': message['print_merchant_receipt_copy'],
          'enable_fiuu': message['enable_fiuu'],
          'cash_drawer_pin_needed': message['cash_drawer_pin_needed'],
          'cash_drawer_pin': message['cash_drawer_pin'] ?? '',
        };
      } else {
        return {
          'success': false,
          'message': responseData['message']['message'] ??
              responseData['message'] ??
              'Login failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection error: $e',
      };
    }
  }

  /// Returns "token api_key:api_secret" read from secure storage.
  static Future<String?> getAuthToken() async {
    final apiKey = await _secureStorage.read(key: _SecureKeys.apiKey);
    final apiSecret = await _secureStorage.read(key: _SecureKeys.apiSecret);

    if (apiKey != null && apiSecret != null) {
      return 'token $apiKey:$apiSecret';
    }
    return null;
  }

  static Future<String?> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('base_url') ?? 'https://asdf.byondwave.com';
  }

  static Future<String?> getMerchantId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('merchant_id');
  }

  /// Reads the stored password from secure storage (used by auto-login).
  static Future<String?> getStoredPassword() async {
    return _secureStorage.read(key: _SecureKeys.password);
  }

  /// Writes sensitive session tokens to secure storage.
  static Future<void> writeSecureSession({
    required String sid,
    required String apiKey,
    required String apiSecret,
    required String cashDrawerPin,
  }) async {
    await Future.wait([
      _secureStorage.write(key: _SecureKeys.sid, value: sid),
      _secureStorage.write(key: _SecureKeys.apiKey, value: apiKey),
      _secureStorage.write(key: _SecureKeys.apiSecret, value: apiSecret),
      _secureStorage.write(key: _SecureKeys.cashDrawerPin, value: cashDrawerPin),
    ]);
  }

  /// Reads the sensitive session tokens from secure storage.
  static Future<Map<String, String?>> readSecureSession() async {
    final results = await Future.wait([
      _secureStorage.read(key: _SecureKeys.sid),
      _secureStorage.read(key: _SecureKeys.apiKey),
      _secureStorage.read(key: _SecureKeys.apiSecret),
      _secureStorage.read(key: _SecureKeys.cashDrawerPin),
    ]);
    return {
      'sid': results[0],
      'api_key': results[1],
      'api_secret': results[2],
      'cash_drawer_pin': results[3],
    };
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    // Clear non-sensitive data from SharedPreferences
    await Future.wait([
      prefs.remove('username'),
      prefs.remove('email'),
      prefs.remove('full_name'),
      prefs.remove('pos_profile'),
      prefs.remove('branch'),
      prefs.remove('payment_methods'),
      prefs.remove('taxes'),
      prefs.remove('has_opening'),
      prefs.remove('tier'),
      prefs.remove('print_kitchen_order'),
      prefs.remove('item_groups'),
      prefs.remove('last_login'),
      prefs.remove('base_url'),
      prefs.remove('print_merchant_receipt_copy'),
      prefs.remove('enable_fiuu'),
      prefs.remove('cash_drawer_pin_needed'),
      prefs.remove('opening_date'),
      prefs.remove('merchant_id'),
    ]);
    // Clear sensitive data from secure storage
    await Future.wait([
      _secureStorage.delete(key: _SecureKeys.sid),
      _secureStorage.delete(key: _SecureKeys.apiKey),
      _secureStorage.delete(key: _SecureKeys.apiSecret),
      _secureStorage.delete(key: _SecureKeys.cashDrawerPin),
      _secureStorage.delete(key: _SecureKeys.password),
    ]);
  }
}
