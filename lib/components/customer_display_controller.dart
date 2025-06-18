import 'package:flutter/services.dart';

// customer_display_controller.dart
class CustomerDisplayController {
  static const _channel = MethodChannel('dual_screen');

  static Future<void> showCustomerScreen() async {
    try {
      await _channel.invokeMethod('showCustomerScreen');
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
    required double total,
  }) async {
    try {
      await _channel.invokeMethod('updateOrderDisplay', {
        'items': items,
        'subtotal': subtotal,
        'tax': tax,
        'total': total,
      });
    } catch (e) {
      print('Error updating order display: $e');
    }
  }

  static void showDefaultDisplay() {
    MethodChannel('dual_screen').invokeMethod('showDefaultDisplay');
  }
}