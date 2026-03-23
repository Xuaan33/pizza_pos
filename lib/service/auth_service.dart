import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  Future<Map<String, dynamic>> autoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('username');
      final password =
          prefs.getString('password'); // You'll need to store this securely
      final merchantId = prefs.getString('merchant_id');

      if (username == null || password == null || merchantId == null) {
        return {
          'success': false,
          'message': 'No saved credentials found',
        };
      }

      // Perform login with stored credentials
      return await login(username, password);
    } catch (e) {
      return {
        'success': false,
        'message': 'Auto-login failed: $e',
      };
    }
  }

  // Store password securely (consider using flutter_secure_storage)
  static Future<void> storeCredentials(
      String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', username);
    // For production, use flutter_secure_storage instead
    await prefs.setString('password', password);
    await prefs.setString('merchant_id', '');
  }

  static Future<void> clearStoredCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('username');
    await prefs.remove('password');
  }

  Future<Map<String, dynamic>> login(
      String username, String password) async {
    try {
      // Use the original URL for login
      final response = await http.post(
        Uri.parse(
            'https://mejaa.joydivisionpadel.com/api/method/shiok_pos.api.login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
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
          'base_url': message['url'] ?? 'https://mejaa.joydivisionpadel.com',
          'merchant_id': message['merchant_id'] ?? '',
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

  static Future<String?> getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('api_key');
    final apiSecret = prefs.getString('api_secret');

    if (apiKey != null && apiSecret != null) {
      return 'token $apiKey:$apiSecret';
    }
    return null;
  }

  static Future<String?> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('base_url') ?? 'https://mejaa.joydivisionpadel.com';
  }

  static Future<String?> getMerchantId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('merchant_id');
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sid');
    await prefs.remove('api_key');
    await prefs.remove('api_secret');
    await prefs.remove('username');
    await prefs.remove('email');
    await prefs.remove('full_name');
    await prefs.remove('pos_profile');
    await prefs.remove('branch');
    await prefs.remove('payment_methods');
    await prefs.remove('taxes');
    await prefs.remove('has_opening');
    await prefs.remove('tier');
    await prefs.remove('print_kitchen_order');
    await prefs.remove('item_groups');
    await prefs.remove('last_login');
    await prefs.remove('base_url');
    await prefs.remove('print_merchant_receipt_copy');
    await prefs.remove('enable_fiuu');
    await prefs.remove('cash_drawer_pin_needed');
    await prefs.remove('cash_drawer_pin');
  }
}
