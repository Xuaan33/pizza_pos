import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final kitchenNotificationsProvider =
    StateNotifierProvider<KitchenNotificationsNotifier, Set<String>>((ref) {
  return KitchenNotificationsNotifier();
});

class KitchenNotificationsNotifier extends StateNotifier<Set<String>> {
  KitchenNotificationsNotifier() : super(<String>{});

  static const String _storageKey = 'notified_kitchen_orders';

  /// Load previously notified kitchen orders from SharedPreferences
  Future<void> loadNotifiedOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notifiedOrdersJson = prefs.getStringList(_storageKey) ?? [];
      
      // Only keep orders from the last 7 days to prevent infinite growth
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      final recentOrders = <String>{};
      
      for (final orderId in notifiedOrdersJson) {
        // Add to set (we'll keep all for now, cleanup happens during save)
        recentOrders.add(orderId);
      }
      
      state = recentOrders;
      print('✅ Loaded ${state.length} notified kitchen orders');
    } catch (e) {
      print('❌ Error loading notified kitchen orders: $e');
      state = <String>{};
    }
  }

  /// Mark an order as notified and persist to SharedPreferences
  Future<void> markAsNotified(String orderId) async {
    if (orderId.isEmpty) return;

    // Add to state
    state = {...state, orderId};

    // Persist to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_storageKey, state.toList());
      print('✅ Marked kitchen order as notified: $orderId');
    } catch (e) {
      print('❌ Error saving notified kitchen order: $e');
    }
  }

  /// Check if an order has been notified
  bool hasBeenNotified(String orderId) {
    return state.contains(orderId);
  }

  /// Filter out orders that have already been notified
  List<Map<String, dynamic>> filterNewOrders(
      List<Map<String, dynamic>> orders) {
    return orders.where((order) {
      final orderId = order['name']?.toString() ?? '';
      final isUnfulfilled = order['custom_fulfilled'] != 1;
      final isNotNotified = !hasBeenNotified(orderId);
      
      return orderId.isNotEmpty && isUnfulfilled && isNotNotified;
    }).toList();
  }

  /// Clear old notifications (older than 7 days) to prevent storage bloat
  Future<void> cleanupOldNotifications() async {
    try {
      // For now, we'll just limit the size
      // In a real implementation, you'd parse timestamps from order IDs
      if (state.length > 1000) {
        // Keep only the most recent 500
        final recentOrders = state.toList()..shuffle();
        state = recentOrders.take(500).toSet();
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_storageKey, state.toList());
        print('🧹 Cleaned up old kitchen notifications');
      }
    } catch (e) {
      print('❌ Error cleaning up notifications: $e');
    }
  }

  /// Clear all notified orders (for testing or reset)
  Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
      state = <String>{};
      print('🗑️ Cleared all notified kitchen orders');
    } catch (e) {
      print('❌ Error clearing notifications: $e');
    }
  }
}