import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final kitchenNotificationsProvider =
    StateNotifierProvider<KitchenNotificationsNotifier, KitchenNotificationState>((ref) {
  return KitchenNotificationsNotifier();
});

/// State that tracks both notified orders and orders pending payment
class KitchenNotificationState {
  final Set<String> notifiedOrders;
  final Set<String> pendingPaymentOrders; // Orders in checkout but not yet paid
  
  const KitchenNotificationState({
    this.notifiedOrders = const {},
    this.pendingPaymentOrders = const {},
  });
  
  KitchenNotificationState copyWith({
    Set<String>? notifiedOrders,
    Set<String>? pendingPaymentOrders,
  }) {
    return KitchenNotificationState(
      notifiedOrders: notifiedOrders ?? this.notifiedOrders,
      pendingPaymentOrders: pendingPaymentOrders ?? this.pendingPaymentOrders,
    );
  }
}

class KitchenNotificationsNotifier extends StateNotifier<KitchenNotificationState> {
  KitchenNotificationsNotifier() : super(const KitchenNotificationState());

  static const String _notifiedKey = 'notified_kitchen_orders';
  static const String _pendingKey = 'pending_payment_orders';

  /// Load previously notified and pending orders from SharedPreferences
  Future<void> loadNotifiedOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load notified orders
      final notifiedOrdersJson = prefs.getStringList(_notifiedKey) ?? [];
      final notifiedOrders = notifiedOrdersJson.toSet();
      
      // Load pending payment orders
      final pendingOrdersJson = prefs.getStringList(_pendingKey) ?? [];
      final pendingOrders = pendingOrdersJson.toSet();
      
      state = KitchenNotificationState(
        notifiedOrders: notifiedOrders,
        pendingPaymentOrders: pendingOrders,
      );
      
      print('✅ Loaded ${state.notifiedOrders.length} notified orders');
      print('✅ Loaded ${state.pendingPaymentOrders.length} pending payment orders');
    } catch (e) {
      print('❌ Error loading notification state: $e');
      state = const KitchenNotificationState();
    }
  }

  /// Mark an order as pending payment (in checkout screen, not yet paid)
  /// This prevents notifications from showing for this order until payment is complete
  Future<void> markAsPendingPayment(String orderId) async {
    if (orderId.isEmpty) return;

    try {
      // Add to pending payment set
      final updatedPending = {...state.pendingPaymentOrders, orderId};
      state = state.copyWith(pendingPaymentOrders: updatedPending);
      
      // Persist to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_pendingKey, updatedPending.toList());
      
      print('⏳ Marked order as pending payment: $orderId');
    } catch (e) {
      print('❌ Error marking order as pending payment: $e');
    }
  }

  /// Mark an order as notified AND remove from pending payment
  /// This should be called after successful payment
  Future<void> markAsNotifiedAndPaid(String orderId) async {
    if (orderId.isEmpty) return;

    try {
      // Add to notified, remove from pending
      final updatedNotified = {...state.notifiedOrders, orderId};
      final updatedPending = {...state.pendingPaymentOrders}..remove(orderId);
      
      state = state.copyWith(
        notifiedOrders: updatedNotified,
        pendingPaymentOrders: updatedPending,
      );

      // Persist both to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_notifiedKey, updatedNotified.toList());
      await prefs.setStringList(_pendingKey, updatedPending.toList());
      
      print('✅ Order marked as notified and paid: $orderId');
    } catch (e) {
      print('❌ Error marking order as notified: $e');
    }
  }

  /// Remove an order from pending payment (e.g., if user cancels checkout)
  Future<void> removeFromPendingPayment(String orderId) async {
    if (orderId.isEmpty) return;

    try {
      final updatedPending = {...state.pendingPaymentOrders}..remove(orderId);
      state = state.copyWith(pendingPaymentOrders: updatedPending);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_pendingKey, updatedPending.toList());
      
      print('🔄 Removed order from pending payment: $orderId');
    } catch (e) {
      print('❌ Error removing from pending payment: $e');
    }
  }

  /// LEGACY METHOD - kept for backward compatibility
  /// Use markAsNotifiedAndPaid() instead for new code
  Future<void> markAsNotified(String orderId) async {
    if (orderId.isEmpty) return;

    // Add to state
    final updatedNotified = {...state.notifiedOrders, orderId};
    state = state.copyWith(notifiedOrders: updatedNotified);

    // Persist to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_notifiedKey, updatedNotified.toList());
      print('✅ Marked kitchen order as notified: $orderId');
    } catch (e) {
      print('❌ Error saving notified kitchen order: $e');
    }
  }

  /// Check if an order has been notified
  bool hasBeenNotified(String orderId) {
    return state.notifiedOrders.contains(orderId);
  }

  /// Check if an order is pending payment (in checkout, not yet paid)
  bool isPendingPayment(String orderId) {
    return state.pendingPaymentOrders.contains(orderId);
  }

  /// Filter out orders that have already been notified OR are pending payment
  /// This prevents duplicate notifications and premature notifications
  List<Map<String, dynamic>> filterNewOrders(
      List<Map<String, dynamic>> orders) {
    return orders.where((order) {
      final orderId = order['name']?.toString() ?? '';
      final isUnfulfilled = order['custom_fulfilled'] != 1;
      final isNotNotified = !hasBeenNotified(orderId);
      final isNotPending = !isPendingPayment(orderId); // NEW: Don't notify pending orders
      
      return orderId.isNotEmpty && isUnfulfilled && isNotNotified && isNotPending;
    }).toList();
  }

  /// Clean up old notifications (older than 7 days) to prevent storage bloat
  Future<void> cleanupOldNotifications() async {
    try {
      if (state.notifiedOrders.length > 1000) {
        final recentOrders = state.notifiedOrders.toList()..shuffle();
        final updatedNotified = recentOrders.take(500).toSet();
        
        state = state.copyWith(notifiedOrders: updatedNotified);
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_notifiedKey, updatedNotified.toList());
        print('🧹 Cleaned up old kitchen notifications');
      }
      
      // Also clean up pending orders that might be stale (> 100 orders is unusual)
      if (state.pendingPaymentOrders.length > 100) {
        print('⚠️ Warning: ${state.pendingPaymentOrders.length} orders still pending payment');
        print('⚠️ Pending orders: ${state.pendingPaymentOrders.toList()}');
      }
    } catch (e) {
      print('❌ Error cleaning up notifications: $e');
    }
  }

  /// Clear all notified orders and pending payments (for testing or reset)
  Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_notifiedKey);
      await prefs.remove(_pendingKey);
      state = const KitchenNotificationState();
      print('🗑️ Cleared all notification state');
    } catch (e) {
      print('❌ Error clearing notifications: $e');
    }
  }
}