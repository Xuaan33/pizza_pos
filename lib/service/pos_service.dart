import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class PosService {
  // Remove hardcoded baseUrl and get it dynamically
  Future<String> _getBaseUrl() async {
    return 'https://mejaa.joydivisionpadel.com';
  }

  // Helper method for common request handling
  Future<Map<String, dynamic>> makeRequest({
    required String endpoint,
    Map<String, dynamic>? body,
    String method = 'GET',
    Duration timeout = const Duration(seconds: 45),
  }) async {
    try {
      final token = await AuthService.getAuthToken();
      if (token == null) throw Exception('Not authenticated');

      final baseUrl = await _getBaseUrl();
      final uri = Uri.parse('$baseUrl/api/method/$endpoint');
      final headers = {
        'Authorization': token,
        if (method != 'GET') 'Content-Type': 'application/json',
      };

      if (body != null) print('Request Body: ${jsonEncode(body)}');

      final response = await (method == 'GET'
              ? http.get(uri, headers: headers)
              : http.post(uri, headers: headers, body: jsonEncode(body)))
          .timeout(timeout);

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
    return makeRequest(
      endpoint: 'shiok_pos.api.get_floor_and_tables?branch=$branch',
    );
  }

  Future<Map<String, dynamic>> getAvailableItems(String posProfile) async {
    return makeRequest(
      endpoint: 'shiok_pos.api.get_available_items?pos_profile=$posProfile',
    );
  }

  Future<Map<String, dynamic>> getAllItems(String posProfile) async {
    return makeRequest(
      endpoint: 'shiok_pos.api.get_items?pos_profile=$posProfile',
    );
  }

  Future<Map<String, dynamic>> getItems(String posProfile) async {
    return makeRequest(
      endpoint:
          'shiok_pos.api.get_items?pos_profile=$posProfile&is_pos_item=1&disabled=0',
    );
  }

  Future<Map<String, dynamic>> getItemGroups() async {
    return makeRequest(
      endpoint: 'shiok_pos.api.get_item_groups',
    );
  }

  Future<Map<String, dynamic>> getPaymentMethods(String posProfile) async {
    return makeRequest(
      endpoint: 'shiok_pos.api.get_mode_of_payment_img?pos_profile=$posProfile',
    );
  }

  Future<Map<String, dynamic>> getTodayInfo() async {
    return makeRequest(
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
    return makeRequest(
      endpoint: 'shiok_pos.api.get_stock_qty?$queryString',
    );
  }

  Future<Map<String, dynamic>> getStockBalanceSummary({
    required String posProfile,
    required int isPosItem,
    int? disable,
    String? date,
  }) async {
    final params = {
      'pos_profile': posProfile,
      'is_pos_item': isPosItem.toString(),
      if (disable != null) 'disable': disable.toString(),
      if (date != null) 'date': date,
    };

    final queryString = Uri(queryParameters: params).query;
    return makeRequest(
      endpoint: 'shiok_pos.api.get_stock_balance_summary?$queryString',
    );
  }

  Future<Map<String, dynamic>> getOrders({
    required String posProfile,
    String? search,
    String? status,
    String? customer,
    String? postingDate,
    String? fromDate,
    String? toDate,
    String? customTable,
    String? customOrderChannel,
    int pageLength = 20,
    int start = 0,
  }) async {
    try {
      final token = await AuthService.getAuthToken();
      if (token == null) throw Exception('Not authenticated');

      final baseUrl = await _getBaseUrl();
      final requestBody = {
        'pos_profile': posProfile,
        if (search != null) 'search': search,
        if (status != null) 'status': status,
        if (customer != null) 'customer': customer,
        // Use date range if provided, otherwise use single posting date
        if (fromDate != null) 'from_date': fromDate,
        if (toDate != null) 'to_date': toDate,
        if (fromDate == null && toDate == null && postingDate != null)
          'from_date': postingDate,
        if (fromDate == null && toDate == null && postingDate != null)
          'to_date': postingDate,
        if (customTable != null) 'custom_table': customTable,
        if (customOrderChannel != null)
          'custom_order_channel': customOrderChannel,
        'page_length': pageLength,
        'start': start,
      };

      print(
          'Sending request to get orders with body: ${jsonEncode(requestBody)}');
      print('Using token: $token');
      print('Using base URL: $baseUrl');

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/method/shiok_pos.api.get_pos_invoice_list'),
            headers: {
              'Authorization': token,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(requestBody),
          )
          .timeout(Duration(seconds: 45));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load orders: ${response.statusCode}');
      }
    } on SessionTimeoutException {
      rethrow;
    } catch (e) {
      print('Error in getOrders: $e');
      throw Exception('Network error: $e');
    }
  }

  Future<Map<String, dynamic>> getPayLaterOrders({
    required String posProfile,
  }) async {
    return getOrders(
      posProfile: posProfile,
      status: 'Draft',
      pageLength: 1000, // Large number to get all draft orders
    );
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
    String? custom_user_voucher,
    String? remarks,
  }) async {
    return makeRequest(
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
        if (discountAmount != null) 'discount_amount': discountAmount,
        if (custom_user_voucher != null)
          'custom_user_voucher': custom_user_voucher,
        if (remarks != null) 'remarks': remarks,
      },
    );
  }

  Future<Map<String, dynamic>> checkoutOrder({
    required String invoiceName,
    required List<Map<String, dynamic>> payments,
  }) async {
    // Extract pos_invoice_number from payments if it exists
    String? posInvoiceNumber;
    for (final payment in payments) {
      if (payment['pos_response'] != null) {
        posInvoiceNumber =
            payment['pos_response']['pos_invoice_number']?.toString();
        if (posInvoiceNumber != null) break;
      }
    }

    return makeRequest(
      endpoint: 'shiok_pos.api.checkout',
      method: 'POST',
      body: {
        'name': invoiceName,
        'payments': payments.map((payment) {
          // Create a new payment object without the pos_response
          final newPayment = {
            'mode_of_payment': payment['mode_of_payment'],
            'amount': payment['amount'],
          };

          // Include reference_no if it exists
          if (payment['reference_no'] != null) {
            newPayment['reference_no'] = payment['reference_no'];
          }

          return newPayment;
        }).toList(),
        if (posInvoiceNumber != null) 'fiuu_invoice_number': posInvoiceNumber,
      },
    );
  }

  Future<Map<String, dynamic>> createOpeningVoucher({
    required String posProfile,
    required List<Map<String, dynamic>> balanceDetails,
  }) async {
    return makeRequest(
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
    return makeRequest(
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
    return makeRequest(
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

      final baseUrl = await _getBaseUrl();
      final uri = Uri.parse(
          '$baseUrl/api/method/shiok_pos.api.delete_order?name=$orderName');
      final headers = {
        'Authorization': token,
      };

      print('API Request: DELETE $uri');

      final response = await http
          .delete(uri, headers: headers)
          .timeout(const Duration(seconds: 45));

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

      final baseUrl = await _getBaseUrl();
      final uri = Uri.parse(
          '$baseUrl/api/method/shiok_pos.api.print_receipt?name=$orderName');
      final headers = {
        'Authorization': token,
      };

      print('API Request: GET $uri');

      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 45));

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

  // In pos_service.dart
  Future<List<Uint8List>> printKitchenOrder({
    required String orderName,
  }) async {
    try {
      final token = await AuthService.getAuthToken();
      if (token == null) throw Exception('Not authenticated');

      final baseUrl = await _getBaseUrl();
      final params = {
        'name': orderName,
        'only_additional_items': '1',
        'multi_pages': '1',
      };

      final queryString = Uri(queryParameters: params).query;
      final uri = Uri.parse(
          '$baseUrl/api/method/shiok_pos.api.print_kitchen_order?$queryString');

      final headers = {
        'Authorization': token,
      };

      print('🖨️ API Request: GET $uri');

      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 45)); // Increased timeout

      print('🖨️ API Response Status: ${response.statusCode}');
      print('🖨️ API Response Body Length: ${response.body.length} characters');

      // Log first 500 characters and last 500 characters to see if response is complete
      if (response.body.length > 1000) {
        print('🖨️ Response start: ${response.body.substring(0, 500)}...');
        print(
            '🖨️ Response end: ...${response.body.substring(response.body.length - 500)}');
      } else {
        print('🖨️ Full Response: ${response.body}');
      }

      if (response.statusCode == 200) {
        // Parse JSON with better error handling
        dynamic responseData;
        try {
          responseData = jsonDecode(response.body);
        } catch (e) {
          print('❌ JSON Parse Error: $e');
          print('❌ Response body that failed to parse: ${response.body}');
          throw Exception('Failed to parse API response as JSON');
        }

        if (responseData is! Map) {
          throw Exception('API response is not a JSON object');
        }

        if (responseData['success'] == true) {
          // Check if message exists and is a list
          if (!responseData.containsKey('message')) {
            throw Exception('API response missing "message" field');
          }

          final message = responseData['message'];
          if (message is! List) {
            throw Exception('"message" field is not an array');
          }

          final int pageCount = responseData['length'] ?? message.length;
          final List<Uint8List> imagePages = [];

          print(
              '📄 API reports $pageCount pages, found ${message.length} items in message array');

          // Process each page
          for (int i = 0; i < message.length; i++) {
            final imageData = message[i];

            if (imageData is String) {
              try {
                // Validate base64 string
                if (imageData.isEmpty) {
                  print('⚠️ Page ${i + 1} has empty base64 string');
                  continue;
                }

                // Check if base64 string looks complete (ends with = or ==)
                if (!imageData.endsWith('=') && !imageData.endsWith('==')) {
                  print(
                      '⚠️ Page ${i + 1} base64 string may be truncated: ${imageData.length} chars');
                }

                final Uint8List imageBytes = base64.decode(imageData);

                if (imageBytes.isEmpty) {
                  print('⚠️ Page ${i + 1} decoded to empty bytes');
                  continue;
                }

                imagePages.add(imageBytes);
                print(
                    '✅ Successfully decoded page ${i + 1} (${imageBytes.length} bytes)');
              } catch (e) {
                print('❌ Error decoding page ${i + 1}: $e');
                print(
                    '❌ Problematic base64 (first 100 chars): ${imageData.substring(0, min(100, imageData.length))}');
                // Continue with other pages instead of failing completely
                continue;
              }
            } else {
              print(
                  '⚠️ Page ${i + 1} is not a string, type: ${imageData.runtimeType}');
            }
          }

          if (imagePages.isEmpty) {
            throw Exception('No valid image pages could be decoded');
          }

          print(
              '🎉 Successfully processed ${imagePages.length} kitchen order pages');
          return imagePages;
        } else {
          final errorMessage = responseData['message'] ?? 'Unknown error';
          throw Exception('API returned error: $errorMessage');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('🚨 Kitchen order API error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> printReceiptAndKitchenOrder({
    required String orderName,
    required bool shouldPrintKitchenOrder,
    String? onlyAdditionalItems,
  }) async {
    try {
      final receiptBytes = await printReceipt(orderName);
      Map<String, dynamic> result = {'receipt': receiptBytes};

      if (shouldPrintKitchenOrder) {
        try {
          final kitchenOrderPages = await printKitchenOrder(
            orderName: orderName,
          );
          result['kitchen_order'] = kitchenOrderPages;
        } catch (e) {
          print('Failed to print kitchen order: $e');
          // Continue with just the receipt if kitchen order printing fails
        }
      }

      return result;
    } catch (e) {
      print('Failed to print receipt: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> validateVoucher(String voucherCode) async {
    return makeRequest(
      endpoint: 'shiok_pos.api.validate_user_voucher',
      method: 'POST',
      body: {
        'user_voucher': voucherCode,
      },
    );
  }

  Future<Map<String, dynamic>> getAppliedUserVouchers({
    required String posProfile,
    String? fromDate,
    String? toDate,
    int limit = 10,
  }) async {
    final params = {
      'pos_profile': posProfile,
      if (fromDate != null) 'from_date': fromDate,
      if (toDate != null) 'to_date': toDate,
      'limit': limit.toString(),
    };

    final queryString = Uri(queryParameters: params).query;
    return makeRequest(
      endpoint: 'shiok_pos.api.get_applied_user_vouchers?$queryString',
    );
  }

  Future<Map<String, dynamic>> cancelOrder(String orderName) async {
    return makeRequest(
      endpoint: 'shiok_pos.api.cancel_order',
      method: 'POST',
      body: {
        'name': orderName,
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

// Variant Group Methods
  Future<Map<String, dynamic>> getVariantGroups() async {
    return makeRequest(
      endpoint: 'shiok_pos.api.get_variant_groups',
    );
  }

  Future<Map<String, dynamic>> getVariantGroup(String variantGroup) async {
    return makeRequest(
      endpoint: 'shiok_pos.api.get_variant_group?variant_group=$variantGroup',
    );
  }

  // Update createVariantGroup method
  Future<Map<String, dynamic>> createVariantGroup({
    required String title,
    required List<Map<String, dynamic>> variantInfoTable,
    required int required,
    required int optionRequiredNo,
    required int maximumSelection,
    required int allowMultipleSelection,
  }) async {
    return await makeRequest(
      endpoint: 'shiok_pos.api.create_variant_group',
      method: 'POST',
      body: {
        "title": title,
        "variant_info_table": variantInfoTable,
        "required": required,
        "option_required_no": optionRequiredNo,
        "maximum_selection": maximumSelection,
        "allow_multiple_selection": allowMultipleSelection,
      },
    );
  }

// Update updateVariantGroup method
  Future<Map<String, dynamic>> updateVariantGroup({
    required String name,
    required List<Map<String, dynamic>> variantInfoTable,
    required int required,
    required int optionRequiredNo,
    required int maximumSelection,
    required int allowMultipleSelection,
  }) async {
    return await makeRequest(
      endpoint: 'shiok_pos.api.update_variant_group',
      method: 'POST',
      body: {
        "name": name,
        "variant_info_table": variantInfoTable,
        "required": required,
        "option_required_no": optionRequiredNo,
        "maximum_selection": maximumSelection,
        "allow_multiple_selection": allowMultipleSelection, // Add this field
      },
    );
  }

// Item Methods
  Future<Map<String, dynamic>> getItem(String itemCode) async {
    return makeRequest(
      endpoint: 'shiok_pos.api.get_item?item_code=$itemCode',
    );
  }

  Future<Map<String, dynamic>> createItem({
    required String itemCode,
    required String itemName,
    required String itemGroup,
    required List<Map<String, dynamic>> variantGroupTable,
    String? description,
    String? imageUrl,
    int isPosItem = 1, // Default to 1 for Finished Goods
    int disabled = 0,
  }) async {
    return makeRequest(
      endpoint: 'shiok_pos.api.create_item',
      method: 'POST',
      body: {
        'item_code': itemCode,
        'item_name': itemName,
        'item_group': itemGroup,
        'variant_group_table': variantGroupTable,
        if (description != null) 'description': description,
        if (imageUrl != null) 'image_url': imageUrl,
        'is_pos_item': isPosItem,
        'disabled': disabled,
      },
    );
  }

  Future<Map<String, dynamic>> updateItem({
    required String itemCode,
    String? itemName,
    String? itemGroup,
    List<Map<String, dynamic>>? variantGroupTable,
    int? disabled,
    String? description,
    String? imageUrl,
    int? isPosItem,
  }) async {
    return makeRequest(
      endpoint: 'shiok_pos.api.update_item',
      method: 'POST',
      body: {
        'item_code': itemCode,
        if (itemName != null) 'item_name': itemName,
        if (itemGroup != null) 'item_group': itemGroup,
        if (variantGroupTable != null) 'variant_group_table': variantGroupTable,
        if (disabled != null) 'disabled': disabled,
        if (description != null) 'description': description,
        if (imageUrl != null) 'image_url': imageUrl,
        if (isPosItem != null) 'is_pos_item': isPosItem,
      },
    );
  }

// Item Group Methods (some may already exist)
  Future<Map<String, dynamic>> getItemGroup(String itemGroup) async {
    return makeRequest(
      endpoint: 'shiok_pos.api.get_item_group?item_group=$itemGroup',
    );
  }

  Future<Map<String, dynamic>> createItemGroup({
    required String itemGroupName,
    String? parentItemGroup,
    int isGroup = 0,
  }) async {
    return makeRequest(
      endpoint: 'shiok_pos.api.create_item_group',
      method: 'POST',
      body: {
        'item_group_name': itemGroupName,
        if (parentItemGroup != null) 'parent_item_group': parentItemGroup,
        'is_group': isGroup,
      },
    );
  }

  Future<Map<String, dynamic>> updateItemGroup({
    required String name,
    required String itemGroupName,
    required String? parentItemGroup,
    int? isGroup,
    required int disabled,
  }) async {
    return makeRequest(
      endpoint: 'shiok_pos.api.update_item_group',
      method: 'POST',
      body: {
        'name': name,
        'item_group_name': itemGroupName,
        if (parentItemGroup != null)
          'parent_item_group': parentItemGroup
        else
          'parent_item_group': 'All Item Groups',
        if (isGroup != null) 'is_group': isGroup,
        'disabled': disabled
      },
    );
  }

// Item Group Methods
  Future<Map<String, dynamic>> disableItemGroup({
    required String itemGroup,
    required int disabled,
  }) async {
    return makeRequest(
      endpoint: 'shiok_pos.api.disable_item_group',
      method: 'POST',
      body: {
        'item_group': itemGroup,
        'disabled': disabled,
      },
    );
  }

  Future<Map<String, dynamic>> updateItemGroupVariantGroupTable({
    required String itemGroup,
    required List<Map<String, dynamic>> variantGroupTable,
  }) async {
    return makeRequest(
      endpoint: 'shiok_pos.api.update_item_group_variant_group_table',
      method: 'POST',
      body: {
        'item_group': itemGroup,
        'variant_group_table': variantGroupTable,
      },
    );
  }

// Variant Group Methods
  Future<Map<String, dynamic>> disableVariantGroup({
    required String variantGroup,
    required int disabled,
  }) async {
    return makeRequest(
      endpoint: 'shiok_pos.api.disable_variant_group',
      method: 'POST',
      body: {
        'variant_group': variantGroup,
        'disabled': disabled,
      },
    );
  }

  Future<Map<String, dynamic>> stockInItems({
    required String posProfile,
    required List<Map<String, dynamic>> items,
  }) async {
    return makeRequest(
      endpoint: 'shiok_pos.api.stock_in',
      method: 'POST',
      body: {
        'pos_profile': posProfile,
        'items': items,
      },
    );
  }

  Future<Map<String, dynamic>> adjustStock({
    required String posProfile,
    required List<Map<String, dynamic>> items,
  }) async {
    return makeRequest(
      endpoint: 'shiok_pos.api.stock_adjustment',
      method: 'POST',
      body: {
        'pos_profile': posProfile,
        'items': items,
      },
    );
  }

  Future<Map<String, dynamic>> getPaymentMethodDistribution({
    required String posProfile,
    String? fromDate,
    String? toDate,
  }) async {
    final params = {
      'pos_profile': posProfile,
      if (fromDate != null) 'from_date': fromDate,
      if (toDate != null) 'to_date': toDate,
    };

    final queryString = Uri(queryParameters: params).query;
    return makeRequest(
      endpoint: 'shiok_pos.api.get_payment_method_distribution?$queryString',
    );
  }

  Future<Map<String, dynamic>> getEmployees() async {
    return makeRequest(
      endpoint: 'shiok_pos.api.get_employees',
    );
  }

  Future<Map<String, dynamic>> employeeCheckIn({
    required String employee,
    required String branch,
  }) async {
    return makeRequest(
      endpoint: 'shiok_pos.api.employee_check_in',
      method: 'POST',
      body: {
        'employee': employee,
        'branch': branch,
      },
    );
  }

  Future<Map<String, dynamic>> employeeCheckOut({
    required String employee,
    required String branch,
  }) async {
    return makeRequest(
      endpoint: 'shiok_pos.api.employee_check_out',
      method: 'POST',
      body: {
        'employee': employee,
        'branch': branch,
      },
    );
  }

  // Add these methods to the existing PosService class in pos_service.dart

  Future<Map<String, dynamic>> getKitchenStations({
    required String posProfile,
  }) async {
    return makeRequest(
      endpoint: 'shiok_pos.api.get_kitchen_stations?pos_profile=$posProfile',
    );
  }

  Future<Map<String, dynamic>> getKitchenOrders({
    required String posProfile,
    required String kitchenStation,
    required String fromDate,
    required String toDate,
  }) async {
    final params = {
      'pos_profile': posProfile,
      'kitchen_station': kitchenStation,
      'from_date': fromDate,
      'to_date': toDate,
    };

    final queryString = Uri(queryParameters: params).query;
    return makeRequest(
      endpoint: 'shiok_pos.api.get_kitchen_orders?$queryString',
    );
  }

  Future<Map<String, dynamic>> fulfillKitchenItem({
    required String posInvoiceItem,
    required int fulfilled,
  }) async {
    return makeRequest(
      endpoint: 'shiok_pos.api.fulfill_kitchen_item',
      method: 'POST',
      body: {
        'pos_invoice_item': posInvoiceItem,
        'fulfilled': fulfilled,
      },
    );
  }

  Future<Map<String, dynamic>> fulfillKitchenOrder({
    required String posInvoice,
    required String kitchenStation,
    required int fulfilled,
  }) async {
    return makeRequest(
      endpoint: 'shiok_pos.api.fulfill_kitchen_order',
      method: 'POST',
      body: {
        'pos_invoice': posInvoice,
        'kitchen_station': kitchenStation,
        'fulfilled': fulfilled,
      },
    );
  }

  Future<Uint8List> printSelectedKitchenOrder({
    required String posInvoice,
    required List<String> items,
  }) async {
    try {
      final token = await AuthService.getAuthToken();
      if (token == null) throw Exception('Not authenticated');

      final baseUrl = await _getBaseUrl();
      final uri = Uri.parse(
          '$baseUrl/api/method/shiok_pos.api.print_selected_kitchen_order');
      final headers = {
        'Authorization': token,
        'Content-Type': 'application/json',
      };

      final body = {
        'pos_invoice': posInvoice,
        'items': items,
      };

      print('🖨️ API Request: POST $uri');
      print('🖨️ Request Body: ${jsonEncode(body)}');

      final response = await http
          .post(
            uri,
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 45));

      print('🖨️ API Response Status: ${response.statusCode}');
      print(
          '🖨️ API Response Content-Type: ${response.headers['content-type']}');
      print('🖨️ API Response Body Length: ${response.bodyBytes.length} bytes');

      if (response.statusCode == 200) {
        // Check if response is JSON or image
        final contentType =
            response.headers['content-type']?.toLowerCase() ?? '';

        if (contentType.contains('application/json')) {
          // Handle JSON response (error case)
          final responseData = jsonDecode(response.body);
          if (responseData['success'] == true) {
            // If success is true but we got JSON, there might be an image in base64
            if (responseData['message'] is String) {
              try {
                return base64.decode(responseData['message']);
              } catch (e) {
                throw Exception(
                    'Failed to decode base64 image from JSON response');
              }
            } else {
              throw Exception('Unexpected JSON response format');
            }
          } else {
            throw Exception(
                responseData['message'] ?? 'Failed to print kitchen order');
          }
        } else if (contentType.contains('image/') ||
            contentType.contains('application/octet-stream') ||
            _isImageData(response.bodyBytes)) {
          // Direct image response - return the bytes as-is
          return response.bodyBytes;
        } else {
          // Try to detect if it's image data by checking the signature
          if (_isImageData(response.bodyBytes)) {
            return response.bodyBytes;
          } else {
            // Try to parse as JSON in case content-type is wrong
            try {
              final responseData = jsonDecode(response.body);
              throw Exception(
                  responseData['message'] ?? 'Unknown response format');
            } catch (e) {
              throw Exception(
                  'Unknown response format: ${response.body.substring(0, min(100, response.body.length))}');
            }
          }
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('🚨 Print selected kitchen order API error: $e');
      rethrow;
    }
  }

// Helper method to detect image data
  bool _isImageData(Uint8List data) {
    if (data.length < 8) return false;

    // PNG signature
    if (data[0] == 0x89 &&
        data[1] == 0x50 &&
        data[2] == 0x4E &&
        data[3] == 0x47) {
      return true;
    }

    // JPEG signature
    if (data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF) {
      return true;
    }

    return false;
  }
}

class OrderMapper {
  // Update your order mapping logic (wherever you map server responses to order objects)
// Make sure this includes proper discount field extraction:

  static Map<String, dynamic> mapSubmittedOrder(
      Map<String, dynamic> apiResponse) {
    try {
      final order = apiResponse['message'] as Map<String, dynamic>;
      return {
        'orderId': order['name'] as String,
        'status': order['status'] as String,
        'items': (order['items'] as List).map((item) {
          // Extract discount information
          final discountAmount =
              (item['discount_amount'] as num?)?.toDouble() ?? 0.0;
          final discountPercentage =
              (item['discount_percentage'] as num?)?.toDouble() ?? 0.0;

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
            'custom_variant_info': customVariantInfo,
            'discount_amount': discountAmount,
            'discount_percentage': discountPercentage,
          };
        }).toList(),
        'total': (order['rounded_total'] as num).toDouble(),
        'postingDate': DateTime.parse(order['creation'] as String),
        'customerName': order['customer_name'] as String? ?? 'Guest',
        'taxes': order['taxes'],
        'taxBreakdown': _mapTaxes(order['taxes'] as List?),
        'total_taxes_and_charges':
            (order['total_taxes_and_charges'] as num).toDouble(),
        'discount_amount': (order['discount_amount'] as num).toDouble(),
        'net_total': (order['net_total'] as num).toDouble(),
        'custom_table': (order['custom_table']).toString(),
        'base_rounding_adjustment':
            (order['base_rounding_adjustment'] as num).toDouble(),
        'remarks': order['remarks'] as String? ?? 'N/A',
        'user_voucher_code': order['user_voucher_code'] as String?,
      };
    } catch (e) {
      print('Error mapping submitted order: $e');
      throw Exception('Failed to map order data');
    }
  }

  static Map<String, dynamic>? _mapTaxes(List<dynamic>? taxes) {
    if (taxes == null || taxes.isEmpty) return null;

    // Find GST tax (or use first tax if not found)
    final tax = taxes.firstWhere(
      (t) => (t['description'] as String?)?.contains('GST') ?? false,
      orElse: () => taxes.first,
    ) as Map<String, dynamic>;

    return {
      'rate': (tax['rate'] as num).toDouble(),
      'amount': (tax['tax_amount'] as num)
          .toDouble(), // Changed from 'amount' to 'tax_amount'
      'description': tax['description'] as String? ?? 'Tax',
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
        'pos_invoice_number': order['custom_fiuu_invoice_number'],
        'discount_amount': (order['discount_amount'] as num).toDouble(),
        'total_taxes_and_charges':
            (order['total_taxes_and_charges'] as num).toDouble(),
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
