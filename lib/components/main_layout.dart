import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shiok_pos_android_app/screens/table_screen.dart';
import 'package:shiok_pos_android_app/screens/orders_screen.dart';
import 'package:shiok_pos_android_app/screens/dashboard_screen.dart';
import 'package:shiok_pos_android_app/screens/settings_screen.dart';
import 'package:shiok_pos_android_app/screens/delivery_screen.dart';
import 'package:shiok_pos_android_app/service/auth_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';

class MainLayout extends ConsumerStatefulWidget {
  static MainLayoutState? of(BuildContext context) =>
      context.findAncestorStateOfType<MainLayoutState>();
  @override
  ConsumerState<MainLayout> createState() => MainLayoutState();
}

class MainLayoutState extends ConsumerState<MainLayout> {
  int _selectedTabIndex = 0;
  List<Map<String, dynamic>> _activeOrders = [];
  Set<int> _tablesWithSubmittedOrders = {};
  bool _isOrdersLoading = false;
  bool _isLoggingOut = false;
  int _orderCounter = 1;

  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  @override
  void initState() {
    super.initState();
    // Check auth state when widget initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authProvider.notifier).loadSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return authState.when(
      initial: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      unauthenticated: () {
        if (!_isLoggingOut) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
          });
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
      authenticated: (sid, apiKey, apiSecret, username, email, fullName,
          posProfile, branch, paymentMethods, taxes, hasOpening) {
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
      },
    );
  }

  Future<void> _refreshOrders() async {
  setState(() => _isOrdersLoading = true);
  try {
    final authState = ref.read(authProvider);
    authState.whenOrNull(
      authenticated: (sid, apiKey, apiSecret, username, email, fullName, posProfile, branch, paymentMethods, taxes, hasOpening) async {
        final response = await PosService().getOrders(
          posProfile: posProfile,
        );
        
        print('Full API response: ${jsonEncode(response)}'); // Debug log
        
        if (response['message']['success'] == true) {  // Note the nested 'message'
          final List<dynamic> invoices = response['message']['message']; // Nested array
          print('Found ${invoices.length} invoices'); // Debug log
          
          setState(() {
            _activeOrders = invoices.map((invoice) {
              print('Processing invoice: ${invoice['name']}'); // Debug log
              
              // Extract items if they exist
              final items = (invoice['items'] as List? ?? []).map((item) {
                return {
                  'name': item['item_name'] ?? 'Unknown Item',
                  'price': item['rate']?.toDouble() ?? 0.0,
                  'quantity': item['qty']?.toDouble() ?? 1.0,
                  'item_code': item['item_code'] ?? '',
                };
              }).toList();
              
              // Extract taxes if they exist
              final taxBreakdown = (invoice['taxes'] as List? ?? []).isNotEmpty 
                  ? {
                      'rate': invoice['taxes'][0]['rate']?.toDouble() ?? 0.0,
                      'amount': invoice['taxes'][0]['amount']?.toDouble() ?? 0.0,
                      'description': invoice['taxes'][0]['account_head'] ?? 'Tax',
                    }
                  : null;
              
              return {
                'orderId': invoice['name'] ?? 'Unknown',
                'invoiceNumber': invoice['name'] ?? 'Unknown',
                'status': invoice['status'] ?? 'Draft',
                'orderType': invoice['custom_order_channel'] ?? 'Dine in',
                'tableNumber': _extractTableNumber(invoice['custom_table']),
                'items': items,
                'subtotal': (invoice['rounded_total']?.toDouble() ?? 0.0) - 
                           (taxBreakdown?['amount'] ?? 0.0),
                'tax': taxBreakdown?['amount'] ?? 0.0,
                'total': invoice['rounded_total']?.toDouble() ?? 0.0,
                'entryTime': DateTime.parse(invoice['posting_date'] ?? DateTime.now().toString()),
                'paidTime': invoice['status'] == 'Paid' 
                    ? DateTime.parse(invoice['posting_date'] ?? DateTime.now().toString())
                    : null,
                'isPaid': invoice['status'] == 'Paid',
                'paymentMethod': invoice['mode_of_payment'] ?? 'Cash',
                'customerName': invoice['customer_name'] ?? 'Guest',
                'remarks': invoice['remarks'] ?? 'No remarks',
                'taxBreakdown': taxBreakdown,
              };
            }).toList();
          });
          
          print('Mapped ${_activeOrders.length} orders'); // Debug log
        }
      },
    );
  } catch (e) {
    print('Error refreshing orders: $e'); // Debug log
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to load orders: ${e.toString()}')),
    );
  } finally {
    setState(() => _isOrdersLoading = false);
  }
}

int _extractTableNumber(String? tableString) {
  if (tableString == null) return 0;
  try {
    final parts = tableString.split(' ');
    return int.tryParse(parts.last) ?? 0;
  } catch (e) {
    return 0;
  }
}

Map<String, dynamic> _mapApiInvoiceToOrder(Map<String, dynamic> invoice) {
  final items = (invoice['items'] as List).map((item) {
    return {
      'name': item['item_name'],
      'price': item['rate'],
      'quantity': item['qty'],
      'item_code': item['item_code'],
      'description': item['description'],
    };
  }).toList();

  return {
    'orderId': invoice['name'],
    'invoiceNumber': invoice['name'],
    'status': invoice['status'],
    'orderType': invoice['custom_order_channel'] ?? 'Dine in',
    'tableNumber': invoice['custom_table'] ?? 0,
    'items': items,
    'subtotal': invoice['net_total'],
    'tax': invoice['total_taxes_and_charges'],
    'total': invoice['grand_total'],
    'entryTime': DateTime.parse(invoice['creation']),
    'paidTime': DateTime.parse(invoice['posting_date']),
    'isPaid': invoice['status'] == 'Paid',
    'paymentMethod': invoice['mode_of_payment'] ?? 'Cash',
    'customerName': invoice['customer_name'] ?? 'Guest',
    'remarks': invoice['remarks'] ?? 'No remarks',
    'taxBreakdown': _parseTaxBreakdown(invoice),
  };
}

Map<String, dynamic>? _parseTaxBreakdown(Map<String, dynamic> invoice) {
  try {
    final taxes = invoice['taxes'] as List;
    if (taxes.isEmpty) return null;
    
    return {
      'rate': taxes[0]['rate'],
      'amount': taxes[0]['tax_amount'],
      'description': taxes[0]['description'],
    };
  } catch (e) {
    return null;
  }
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
          handleOrderPaid(order);
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
      onTap: action ??
          () {
            if (index == -1) {
              // Logout
              ref.read(authProvider.notifier).logout();
              Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
            } else {
              setState(() => _selectedTabIndex = index);
            }
          },
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

  void handleOrderPaid(Map<String, dynamic> order) async {
    setState(() {
      final index = _activeOrders.indexWhere(
          (o) => o['tableNumber'] == order['tableNumber'] && !o['isPaid']);
      if (index != -1) {
        _activeOrders[index]['isPaid'] = true;
        _activeOrders[index]['status'] = 'Paid';
        _activeOrders[index]['paidTime'] = DateTime.now();
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

  void _logout() async {
    // Show confirmation dialog first
    final shouldLogout = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
            title: const Text(
              'Confirm Logout',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            content: const Text(
              'Are you sure you want to logout?',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: [
              TextButton(
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFE732A0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                ),
                child: const Text(
                  'Confirm',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldLogout) return;

    setState(() {
      _isLoggingOut = true;
    });

    try {
      await ref.read(authProvider.notifier).logout();

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logout failed: ${e.toString()}')),
        );
        setState(() {
          _isLoggingOut = false;
        });
      }
    }
  }

  void _addNewOrder(Map<String, dynamic> order) {
    setState(() {
      _activeOrders.removeWhere(
          (o) => o['tableNumber'] == order['tableNumber'] && !o['isPaid']);

      _activeOrders.add({
        'orderId': 'ORDER-${_orderCounter.toString().padLeft(2, '0')}',
        'tableNumber': order['tableNumber'],
        'items': List.from(order['items']),
        'status': 'Draft', // Add this
        'orderType': 'Dine in',
        'submittedTime': DateTime.now(),
        'entryTime': DateTime.now(), // Track when order was created
        'isPaid': false,
      });

      _orderCounter++;
      _tablesWithSubmittedOrders.add(order['tableNumber']);
    });
  }

  void _updateOrder(Map<String, dynamic> updatedOrder) {
    setState(() {
      final index = _activeOrders.indexWhere((o) =>
          o['tableNumber'] == updatedOrder['tableNumber'] && !o['isPaid']);
      if (index != -1) {
        _activeOrders[index] = updatedOrder;
      }
    });
  }

  void _markOrderAsPaid(int tableNumber) {
    setState(() {
      // Mark as paid
      final index = _activeOrders
          .indexWhere((order) => order['tableNumber'] == tableNumber);
      if (index != -1) {
        _activeOrders[index]['isPaid'] = true;
        _activeOrders[index]['status'] = 'Paid';
      }

      // Update table status
      _tablesWithSubmittedOrders.remove(tableNumber);
    });
  }

  void selectOrdersTab() {
    setState(() {
      _selectedTabIndex = 2; // Orders screen index
    });
  }

  double calculateOrderSubtotal(Map<String, dynamic> order) {
    return (order['items'] as List).fold(0.0, (sum, item) {
      return sum + (item['price'] ?? 0) * (item['quantity'] ?? 1);
    });
  }

  double calculateOrderTax(Map<String, dynamic> order) {
    return calculateOrderSubtotal(order) * 0.06; // 6% GST
  }

  double calculateOrderTotal(Map<String, dynamic> order) {
    return calculateOrderSubtotal(order) + calculateOrderTax(order);
  }
}
