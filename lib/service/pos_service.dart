import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shiok_pos_android_app/screens/login_screen.dart';
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
        throw Exception(error['message'] ??
            'Request failed with status ${response.statusCode}');
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

  Future<Map<String, dynamic>> getStockQuantity({
    required String posProfile,
    required String itemCode,
    String? barcode,
    String? date,
  }) async {
    final params = {
      'pos_profile': posProfile,
      'item_code': itemCode,
      if (barcode != null) 'barcode': barcode,
      if (date != null) 'date': date,
    };

    final queryString = Uri(queryParameters: params).query;
    return _makeRequest(
      endpoint: 'shiok_pos.api.get_stock_qty?$queryString',
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
        if (postingDate != null) 'creation': postingDate,
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
    } on SessionTimeoutException {
      rethrow; // Let this propagate up
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
    String? custom_user_voucher, // Add this parameter
  }) async {
    return _makeRequest(
      endpoint: 'shiok_pos.api.submit_order',
      method: 'POST',
      body: {
        if (name != null) 'name': name,
        'pos_profile': posProfile,
        'customer': customer,
        'items': items,
        if (name != null) 'name': name,
        if (table != null) 'custom_table': table,
        if (orderChannel != null) 'custom_order_channel': orderChannel,
        if (couponCode != null) 'coupon_code': couponCode,
        if (custom_user_voucher != null)
          'custom_user_voucher': custom_user_voucher,
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

  Future<Map<String, dynamic>> createOpeningVoucher({
    required String posProfile,
    required List<Map<String, dynamic>> balanceDetails,
  }) async {
    return _makeRequest(
      endpoint: 'shiok_pos.api.create_opening_voucher',
      method: 'POST',
      body: {
        'pos_profile': posProfile,
        'balance_details': balanceDetails,
      },
    );
  }

  // Add to PosService class
  Future<Map<String, dynamic>> requestClosingVoucher({
    required String posProfile,
  }) async {
    return _makeRequest(
      endpoint: 'shiok_pos.api.request_closing_voucher',
      method: 'POST',
      body: {
        'pos_profile': posProfile,
      },
    );
  }

  Future<Map<String, dynamic>> submitClosingVoucher({
    required String name,
    required List<Map<String, dynamic>> paymentReconciliation,
  }) async {
    return _makeRequest(
      endpoint: 'shiok_pos.api.submit_closing_voucher',
      method: 'POST',
      body: {
        'name': name,
        'payment_reconciliation': paymentReconciliation,
      },
    );
  }

  Future<Map<String, dynamic>> deleteOrder(String orderName) async {
    try {
      final token = await AuthService.getAuthToken();
      if (token == null) throw Exception('Not authenticated');

      final uri =
          Uri.parse('$_baseUrl/shiok_pos.api.delete_order?name=$orderName');
      final headers = {
        'Authorization': token,
      };

      print('API Request: DELETE $uri');

      final response = await http
          .delete(uri, headers: headers)
          .timeout(const Duration(seconds: 10));

      print('API Response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ??
            'Request failed with status ${response.statusCode}');
      }
    } catch (e) {
      print('API Error: $e');
      rethrow;
    }
  }

  Future<Uint8List> printReceipt(String orderName) async {
    try {
      final token = await AuthService.getAuthToken();
      if (token == null) throw Exception('Not authenticated');

      final uri =
          Uri.parse('$_baseUrl/shiok_pos.api.print_receipt?name=$orderName');
      final headers = {
        'Authorization': token,
      };

      print('API Request: GET $uri');

      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));

      print('API Response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        return response.bodyBytes; // Return raw image bytes
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ??
            'Request failed with status ${response.statusCode}');
      }
    } catch (e) {
      print('API Error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> validateVoucher(String voucherCode) async {
    return _makeRequest(
      endpoint: 'shiok_pos.api.validate_user_voucher',
      method: 'POST',
      body: {
        'user_voucher': voucherCode,
      },
    );
  }

  Uint8List hexStringToBytes(String hexString) {
    hexString = hexString.replaceAll(' ', '');
    final result = Uint8List(hexString.length ~/ 2);
    for (var i = 0; i < hexString.length; i += 2) {
      final byte = int.parse(hexString.substring(i, i + 2), radix: 16);
      result[i ~/ 2] = byte;
    }
    return result;
  }
}

class OrderMapper {
  static Map<String, dynamic> mapSubmittedOrder(
      Map<String, dynamic> apiResponse) {
    try {
      final order = apiResponse['message'] as Map<String, dynamic>;
      return {
        'orderId': order['name'] as String,
        'status': order['status'] as String,
        'items': (order['items'] as List).map((item) {
          // Parse variant info if exists
          Map<String, dynamic>? options;
          String? optionText;
          dynamic customVariantInfo = item['custom_variant_info'];

          if (customVariantInfo != null) {
            try {
              dynamic parsed = customVariantInfo is String
                  ? jsonDecode(customVariantInfo)
                  : customVariantInfo;

              if (parsed is List && parsed.isNotEmpty && parsed[0] is Map) {
                options = Map<String, dynamic>.from(parsed[0]);
                optionText = options.entries
                    .map((e) => '${e.key}: ${e.value}')
                    .join(', ');
              }
            } catch (e) {
              print('Error parsing variant info: $e');
            }
          }

          return {
            'name': item['item_name'] as String,
            'price': (item['rate'] as num).toDouble(),
            'quantity': (item['qty'] as num).toDouble(),
            'item_code': item['item_code'] as String?,
            'custom_item_remarks': item['custom_item_remarks'] as String?,
            'serve_later': item['custom_serve_later'] == 1,
            'options': options ?? {},
            'option_text': optionText ?? '',
            'custom_variant_info': customVariantInfo, // Preserve original
          };
        }).toList(),
        'total': (order['rounded_total'] as num).toDouble(),
        'postingDate': DateTime.parse(order['creation'] as String),
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

      print('[OrderMapper] Raw order data: ${jsonEncode(order)}');
      print('[OrderMapper] Payments data: ${jsonEncode(payments)}');

      return {
        'isPaid': true,
        'paidAmount': (order['paid_amount'] as num).toDouble(),
        'changeAmount': (order['change_amount'] as num?)?.toDouble() ?? 0.0,
        'paymentMethod': payments.isNotEmpty
            ? payments.first['mode_of_payment'] as String?
            : null,
        'paymentDate': order['creation']?.toString(),
        'invoiceNumber': order['name'] as String,
      };
    } catch (e) {
      print('[OrderMapper] Error mapping paid order: $e');
      throw Exception('Failed to map payment data');
    }
  }
}

class SessionTimeoutException implements Exception {
  final String message;
  SessionTimeoutException(this.message);

  @override
  String toString() => message;
}
