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

  Future<Map<String, dynamic>> getTodayInfo() async {
    try {
      final token = await AuthService.getAuthToken();
      if (token == null) throw Exception('Not authenticated');

      final response = await http.get(
        Uri.parse('$_baseUrl/shiok_pos.api.calculate_today_info'),
        headers: {'Authorization': token},
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load today info: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  Future<Map<String, dynamic>> getOrders({
    required String posProfile,
    String? search,
    String? status,
    String? customer,
    String? postingDate,
    String? customTable,
    String? customOrderChannel,
    int pageLength = 20,
    int start = 0,
  }) async {
    try {
      final token = await AuthService.getAuthToken();
      if (token == null) throw Exception('Not authenticated');

      final requestBody = {
        'pos_profile': posProfile,
        if (search != null) 'search': search,
        if (status != null) 'status': status,
        if (customer != null) 'customer': customer,
        if (postingDate != null) 'posting_date': postingDate,
        if (customTable != null) 'custom_table': customTable,
        if (customOrderChannel != null)
          'custom_order_channel': customOrderChannel,
        'page_length': pageLength,
        'start': start,
      };

      print(
          'Sending request to get orders with body: ${jsonEncode(requestBody)}');
      print('Using token: $token');

      final response = await http
          .post(
            Uri.parse('$_baseUrl/shiok_pos.api.get_pos_invoice_list'),
            headers: {
              'Authorization': token,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(requestBody),
          )
          .timeout(Duration(seconds: 10));

      print('Received response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load orders: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in getOrders: $e');
      throw Exception('Network error: $e');
    }
  }

  Future<Map<String, dynamic>> submitOrder({
    required String posProfile,
    required String customer,
    required List<Map<String, dynamic>> items,
    String? name,
    String? couponCode,
    String? applyDiscountOn,
    double? discountAmount,
    String? table,
    String? orderChannel,
  }) async {
    try {
      final token = await AuthService.getAuthToken();
      if (token == null) throw Exception('Not authenticated');

      final response = await http
          .post(
            Uri.parse('$_baseUrl/shiok_pos.api.submit_order'),
            headers: {
              'Authorization': token,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'pos_profile': posProfile,
              'customer': customer,
              'items': items,
              if (name != null) 'name': name,
              if (couponCode != null) 'coupon_code': couponCode,
              if (applyDiscountOn != null) 'apply_discount_on': applyDiscountOn,
              if (discountAmount != null) 'discount_amount': discountAmount,
              if (table != null) 'table': table,
              if (orderChannel != null) 'order_channel': orderChannel,
            }),
          )
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(
            'Failed to submit order: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  Future<Map<String, dynamic>> checkoutOrder({
    required String invoiceName,
    required List<Map<String, dynamic>> payments,
  }) async {
    try {
      final token = await AuthService.getAuthToken();
      if (token == null) throw Exception('Not authenticated');

      final response = await http
          .post(
            Uri.parse('$_baseUrl/shiok_pos.api.checkout'),
            headers: {
              'Authorization': token,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'name': invoiceName,
              'payments': payments,
            }),
          )
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(
            'Failed to checkout: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
}
