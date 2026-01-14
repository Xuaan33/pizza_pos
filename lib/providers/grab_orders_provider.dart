// providers/grab_orders_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GrabOrdersProvider extends StateNotifier<List<Map<String, dynamic>>> {
  GrabOrdersProvider() : super([]);

  // Update orders with new data
  void updateOrders(List<Map<String, dynamic>> newOrders) {
    // Merge new orders with existing, removing duplicates
    final existingOrderIds = state.map((order) => order['name']?.toString() ?? '').toSet();
    
    // Add only new orders that don't exist in current state
    final ordersToAdd = newOrders.where(
      (order) => !existingOrderIds.contains(order['name']?.toString() ?? '')
    ).toList();
    
    if (ordersToAdd.isNotEmpty) {
      state = [...state, ...ordersToAdd];
    }
  }

  // Clear all orders
  void clear() {
    state = [];
  }

  // Get pending orders
  List<Map<String, dynamic>> get pendingOrders {
    return state.where((order) => order['custom_fulfilled'] != 1).toList();
  }

  // Get completed orders
  List<Map<String, dynamic>> get completedOrders {
    return state.where((order) => order['custom_fulfilled'] == 1).toList();
  }

  // Get order by ID
  Map<String, dynamic>? getOrderById(String orderId) {
    return state.firstWhere(
      (order) => order['name']?.toString() == orderId,
      orElse: () => {},
    );
  }
}

final grabOrdersProvider = StateNotifierProvider<GrabOrdersProvider, List<Map<String, dynamic>>>(
  (ref) => GrabOrdersProvider(),
);