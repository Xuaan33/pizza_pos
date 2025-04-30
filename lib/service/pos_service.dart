// lib/service/pos_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class PosService {
  static const String _baseUrl = 'https://shiokpos.byondwave.com/api/method';

  Future<Map<String, dynamic>> getFloorsAndTables(String branch) async {
    try {
      final token = await AuthService.getAuthToken();
      if (token == null) throw Exception('Not authenticated');

      final response = await http.get(
        Uri.parse(
            '$_baseUrl/shiok_pos.api.get_floor_and_tables?branch=$branch'),
        headers: {'Authorization': token},
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(
            'Failed to load floors and tables: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  Future<Map<String, dynamic>> getAvailableItems() async {
    final token = await AuthService.getAuthToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$_baseUrl/shiok_pos.api.get_available_items'),
      headers: {'Authorization': token},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load available items');
    }
  }

  Future<Map<String, dynamic>> getItemGroups() async {
    final token = await AuthService.getAuthToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$_baseUrl/shiok_pos.api.get_item_groups'),
      headers: {'Authorization': token},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load item groups');
    }
  }

  // Add this method to your existing PosService class
  Future<Map<String, dynamic>> getPaymentMethods(String posProfile) async {
    final token = await AuthService.getAuthToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse(
          '$_baseUrl/shiok_pos.api.get_mode_of_payment_img?pos_profile=$posProfile'),
      headers: {'Authorization': token},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load payment methods');
    }
  }
}
