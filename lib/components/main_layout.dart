import 'package:flutter/material.dart';
import 'package:shiok_pos_android_app/screens/table_screen.dart';
import 'package:shiok_pos_android_app/screens/orders_screen.dart';
import 'package:shiok_pos_android_app/screens/dashboard_screen.dart';
import 'package:shiok_pos_android_app/screens/settings_screen.dart';
import 'package:shiok_pos_android_app/screens/delivery_screen.dart';

class MainLayout extends StatefulWidget {
  @override
  _MainLayoutState createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedTabIndex = 0;
  List<Map<String, dynamic>> _activeOrders = [];
  Set<int> _tablesWithSubmittedOrders = {};
  bool _isOrdersLoading = false; 

  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildNavigationSidebar(),
          Expanded(
            child: IndexedStack(
              index: _selectedTabIndex,
              children: _getScreensWithOrders(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshOrders() async {
    setState(() => _isOrdersLoading = true);
    // Simulate network delay (remove in production)
    await Future.delayed(Duration(milliseconds: 500)); 
    setState(() => _isOrdersLoading = false);
  }

  List<Widget> _getScreensWithOrders() {
  return [
    TableScreen(
      tablesWithSubmittedOrders: _tablesWithSubmittedOrders,
      onOrderSubmitted: (order) {
        _addNewOrder(order);
        _refreshOrders();
      },
      onOrderPaid: _markOrderAsPaid,
      activeOrders: _activeOrders, // Pass active orders to table screen
    ),
    DeliveryScreen(),
    OrdersScreen(
      orders: _activeOrders,
      isLoading: _isOrdersLoading,
      onOrderPaid: (order) {
        _handleOrderPaid(order);
        setState(() => _isOrdersLoading = true);
        Future.delayed(Duration(seconds: 1), () {
          setState(() => _isOrdersLoading = false);
        });
      },
      onEditOrder: _handleEditOrder,
      onRefresh: _refreshOrders,
    ),
    DashboardScreen(),
    SettingsScreen(),
  ];
}

  Future<List<Map<String, dynamic>>> _fetchOrders() async {
  // Simulate network delay
  await Future.delayed(Duration(milliseconds: 500)); 
  return _activeOrders.where((o) => !o['isPaid']).toList();
}

  Widget _buildNavigationSidebar() {
    return Container(
      width: 80,
      color: Colors.white,
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedTabIndex = 0; // Go to TableScreen when tapping logo
              });
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Image.asset(
                'assets/logo-shiokpos.png',
                width: 50,
                height: 50,
              ),
            ),
          ),
          _buildNavItem(1, 'assets/img-sidebar-delivery.png', 'Delivery'),
          _buildNavItem(2, 'assets/img-sidebar-orders.png', 'Orders'),
          _buildNavItem(3, 'assets/img-sidebar-dashboard.png', 'Dashboard'),
          _buildNavItem(4, 'assets/img-sidebar-settings.png', 'Settings'),
          const Spacer(),
          _buildNavItem(-1, 'assets/img-sidebar-logout.png', 'Logout', _logout),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, String imagePath, String label,
      [VoidCallback? action]) {
    final bool isSelected = index == _selectedTabIndex;
    return GestureDetector(
      onTap: action ?? () => setState(() => _selectedTabIndex = index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: isSelected
                    ? const Border(
                        left: BorderSide(color: Colors.pink, width: 3))
                    : null,
              ),
              child: Image.asset(
                imagePath,
                color: isSelected ? Colors.pink : const Color(0xFF9B9B9B),
                width: 26,
                height: 26,
              ),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: isSelected ? Colors.pink : const Color(0xFF9B9B9B),
                    fontSize: 10)),
          ],
        ),
      ),
    );
  }

  void _handleOrderPaid(Map<String, dynamic> order) async {
  setState(() {
    final index = _activeOrders.indexWhere((o) => 
        o['tableNumber'] == order['tableNumber']);
    if (index != -1) {
      _activeOrders[index]['isPaid'] = true;
      _tablesWithSubmittedOrders.remove(order['tableNumber']);
    }
  });
}

  void _handleEditOrder(Map<String, dynamic> order) {
    setState(() {
      final index = _activeOrders
          .indexWhere((o) => o['tableNumber'] == order['tableNumber']);
      if (index != -1) {
        _activeOrders[index] = order;
      }
    });
    setState(() {
      _selectedTabIndex = 0;
    });
  }

  void _logout() {
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  void _addNewOrder(Map<String, dynamic> order) {
  setState(() {
    // Remove any existing order for this table first
    _activeOrders.removeWhere((o) => 
        o['tableNumber'] == order['tableNumber'] && !o['isPaid']);
    
    // Add the new order with additional metadata
    _activeOrders.add({
      'tableNumber': order['tableNumber'],
      'items': List.from(order['items']),
      'submittedTime': DateTime.now(),
      'isPaid': false,
      'isDirectCheckout': order['isDirectCheckout'] ?? false,
    });
    
    // Update table status
    _tablesWithSubmittedOrders.add(order['tableNumber']);
  });
}

void _updateOrder(Map<String, dynamic> updatedOrder) {
  setState(() {
    final index = _activeOrders.indexWhere(
      (o) => o['tableNumber'] == updatedOrder['tableNumber'] && !o['isPaid']
    );
    if (index != -1) {
      _activeOrders[index] = updatedOrder;
    }
  });
}

void _markOrderAsPaid(int tableNumber) {
  setState(() {
    // Mark as paid
    final index = _activeOrders.indexWhere(
        (order) => order['tableNumber'] == tableNumber);
    if (index != -1) {
      _activeOrders[index]['isPaid'] = true;
    }
    
    // Update table status
    _tablesWithSubmittedOrders.remove(tableNumber);
  });
}
}
