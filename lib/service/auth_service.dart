import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _baseUrl = 'https://mejaa.joydivisionpadel.com/api/method/shiok_pos.api.login';
  
  Future<Map<String, dynamic>> login(String username, String password) async {
  try {
    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    final responseData = jsonDecode(response.body);
    print("LOGIN: $responseData");

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
        'item_groups': message['item_groups'] ?? []
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

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}