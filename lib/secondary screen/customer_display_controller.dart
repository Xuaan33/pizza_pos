import 'package:flutter/services.dart';
import 'package:shiok_pos_android_app/components/image_url_helper.dart';
import 'package:shiok_pos_android_app/service/auth_service.dart';

class CustomerDisplayController {
  static const _channel = MethodChannel('dual_screen');

  static Future<void> showCustomerScreen() async {
    try {
      final baseUrl = await ImageUrlHelper.getBaseImageUrl();
      await _channel.invokeMethod('showCustomerScreen', {
        'authToken': await AuthService.getAuthToken(),
        'baseUrl': baseUrl,
      });
    } catch (e) {
      print('Error showing customer screen: $e');
    }
  }

  static Future<void> hideCustomerScreen() async {
    try {
      await _channel.invokeMethod('hideCustomerScreen');
    } catch (e) {
      print('Error hiding customer screen: $e');
    }
  }

  static Future<void> updateOrderDisplay({
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double tax,
    required double discount,
    required double rounding,
    required double total,
    required String taxRate,
    List<Map<String, dynamic>>? taxDetails,
  }) async {
    try {
      await _channel.invokeMethod('updateOrderDisplay', {
        'items': items.map((item) {
          return {
            'name': item['name'] ?? 'Unknown',
            'price': (item['price'] is int)
                ? (item['price'] as int).toDouble()
                : item['price'] as double,
            'quantity': (item['quantity'] is int)
                ? item['quantity'] as int
                : (item['quantity'] as double).toInt(),
            'discount_amount': item['discount_amount'] ?? 0.0,
            'custom_serve_later': item['custom_serve_later'] ?? false,
            'custom_item_remarks': item['custom_item_remarks'] ?? '',
            'custom_variant_info': (item['custom_variant_info']),
          };
        }).toList(),
        'subtotal': subtotal,
        'tax': tax,
        'discount': discount,
        'rounding': rounding,
        'total': total,
        'taxRate': taxRate,
        'taxDetails': taxDetails,
      });
    } catch (e) {
      print('Error updating order display: $e');
    }
  }

  // Clear the order display by sending empty data - this will automatically show slideshow
  static Future<void> clearOrderDisplay() async {
    try {
      await _channel.invokeMethod('updateOrderDisplay', {
        'items': <Map<String, dynamic>>[],
        'subtotal': 0.0,
        'tax': 0.0,
        'discount': 0.0,
        'rounding': 0.0,
        'total': 0.0,
      });
    } catch (e) {
      print('Error clearing order display: $e');
    }
  }
}
