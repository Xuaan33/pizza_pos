// providers/grab_notifications_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GrabNotificationProvider extends StateNotifier<GrabNotificationState> {
  GrabNotificationProvider() : super(GrabNotificationState());

  // Track notified order IDs
  final Set<String> _notifiedOrders = {};
  
  // Load previously notified orders from storage
  Future<void> loadNotifiedOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('notified_grab_orders') ?? [];
      _notifiedOrders.addAll(saved);
      state = state.copyWith(notifiedCount: _notifiedOrders.length);
    } catch (e) {
      print('Error loading notified orders: $e');
    }
  }

  // Save notified orders to storage
  Future<void> _saveNotifiedOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('notified_grab_orders', _notifiedOrders.toList());
    } catch (e) {
      print('Error saving notified orders: $e');
    }
  }

  // Check if order has been notified
  bool isOrderNotified(String orderId) {
    return _notifiedOrders.contains(orderId);
  }

  // Mark order as notified
  Future<void> markAsNotified(String orderId) async {
    _notifiedOrders.add(orderId);
    state = state.copyWith(
      notifiedCount: _notifiedOrders.length,
      lastNotificationTime: DateTime.now(),
    );
    await _saveNotifiedOrders();
  }

  // Clear old notifications (optional: after 24 hours)
  Future<void> clearOldNotifications() async {
    // Could implement time-based cleanup if needed
    // For now, we'll keep them until manual clear or app reset
  }

  // Reset notifications (for testing or logout)
  Future<void> reset() async {
    _notifiedOrders.clear();
    state = GrabNotificationState();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notified_grab_orders');
  }

  // Get new orders from list
  List<Map<String, dynamic>> filterNewOrders(List<Map<String, dynamic>> orders) {
    return orders.where((order) {
      final orderId = order['name']?.toString() ?? '';
      return orderId.isNotEmpty && !isOrderNotified(orderId);
    }).toList();
  }
}

class GrabNotificationState {
  final int notifiedCount;
  final DateTime? lastNotificationTime;
  final bool isNotificationEnabled;

  GrabNotificationState({
    this.notifiedCount = 0,
    this.lastNotificationTime,
    this.isNotificationEnabled = true,
  });

  GrabNotificationState copyWith({
    int? notifiedCount,
    DateTime? lastNotificationTime,
    bool? isNotificationEnabled,
  }) {
    return GrabNotificationState(
      notifiedCount: notifiedCount ?? this.notifiedCount,
      lastNotificationTime: lastNotificationTime ?? this.lastNotificationTime,
      isNotificationEnabled: isNotificationEnabled ?? this.isNotificationEnabled,
    );
  }
}

final grabNotificationsProvider = StateNotifierProvider<GrabNotificationProvider, GrabNotificationState>(
  (ref) => GrabNotificationProvider(),
);