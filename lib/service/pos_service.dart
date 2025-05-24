import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class PosService {
  static const String _baseUrl = 'https://shiokpos.byondwave.com/api/method';

  // Helper method for common request handling
  Future<Map<String, dynamic>> _makeRequest({
    required String endpoint,
    Map<String, dynamic>? body,
    String method = 'GET',
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final token = await AuthService.getAuthToken();
      if (token == null) throw Exception('Not authenticated');

      final uri = Uri.parse('$_baseUrl/$endpoint');
      final headers = {
        'Authorization': token,
        if (method != 'GET') 'Content-Type': 'application/json',
      };

      //print('API Request: $method $uri');
      if (body != null) print('Request Body: ${jsonEncode(body)}');

      final response = await (method == 'GET'
          ? http.get(uri, headers: headers)
          : http.post(uri, headers: headers, body: jsonEncode(body)))
          .timeout(timeout);

      //print('API Response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Request failed with status ${response.statusCode}');
      }
    } catch (e) {
      print('API Error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getFloorsAndTables(String branch) async {
    return _makeRequest(
      endpoint: 'shiok_pos.api.get_floor_and_tables?branch=$branch',
    );
  }

  Future<Map<String, dynamic>> getAvailableItems() async {
    return _makeRequest(
      endpoint: 'shiok_pos.api.get_available_items',
    );
  }

  Future<Map<String, dynamic>> getItemGroups() async {
    return _makeRequest(
      endpoint: 'shiok_pos.api.get_item_groups',
    );
  }

  Future<Map<String, dynamic>> getPaymentMethods(String posProfile) async {
    return _makeRequest(
      endpoint: 'shiok_pos.api.get_mode_of_payment_img?pos_profile=$posProfile',
    );
  }

  Future<Map<String, dynamic>> getTodayInfo() async {
    return _makeRequest(
      endpoint: 'shiok_pos.api.calculate_today_info',
    );
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

  // Ensure the submitOrder method is properly formatted
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
  return _makeRequest(
    endpoint: 'shiok_pos.api.submit_order',
    method: 'POST',
    body: {
      'pos_profile': posProfile,
      'customer': customer,
      'items': items,
      if (name != null) 'name': name,
      'custom_table': table, // Full table name format
      'custom_order_channel': orderChannel, // "Dine In"
    },
  );
}

  Future<Map<String, dynamic>> checkoutOrder({
    required String invoiceName,
    required List<Map<String, dynamic>> payments,
  }) async {
    return _makeRequest(
      endpoint: 'shiok_pos.api.checkout',
      method: 'POST',
      body: {
        'name': invoiceName,
        'payments': payments,
      },
    );
  }
}

class OrderMapper {
  static Map<String, dynamic> mapSubmittedOrder(Map<String, dynamic> apiResponse) {
    try {
      final order = apiResponse['message'] as Map<String, dynamic>;
      return {
        'orderId': order['name'] as String,
        'status': order['status'] as String,
        'items': (order['items'] as List).map((item) => {
          'name': item['item_name'] as String,
          'price': (item['rate'] as num).toDouble(),
          'quantity': (item['qty'] as num).toDouble(),
          'item_code': item['item_code'] as String?,
        }).toList(),
        'total': (order['rounded_total'] as num).toDouble(),
        'postingDate': DateTime.parse(order['posting_date'] as String),
        'customerName': order['customer_name'] as String? ?? 'Guest',
        'taxBreakdown': _mapTaxes(order['taxes'] as List?),
      };
    } catch (e) {
      print('Error mapping submitted order: $e');
      throw Exception('Failed to map order data');
    }
  }

  static Map<String, dynamic>? _mapTaxes(List<dynamic>? taxes) {
    if (taxes == null || taxes.isEmpty) return null;
    final tax = taxes.first as Map<String, dynamic>;
    return {
      'rate': (tax['rate'] as num).toDouble(),
      'amount': (tax['amount'] as num).toDouble(),
      'description': tax['account_head'] as String? ?? 'Tax',
    };
  }

static Map<String, dynamic> mapPaidOrder(Map<String, dynamic> apiResponse) {
  try {
    final order = apiResponse['message'] as Map<String, dynamic>;
    final payments = order['payments'] as List<dynamic>? ?? [];
    
    return {
      'isPaid': true,
      'paidAmount': (order['paid_amount'] as num).toDouble(),
      'paymentMethod': payments.isNotEmpty 
          ? payments.first['mode_of_payment'] as String? 
          : null,
      'paymentDate': order['posting_date']?.toString(), // Already a string from API
      'invoiceNumber': order['name'] as String,
    };
  } catch (e) {
    print('Error mapping paid order: $e');
    throw Exception('Failed to map payment data');
  }
}
}