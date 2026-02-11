import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shiok_pos_android_app/components/main_layout.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';
import 'package:fluttertoast/fluttertoast.dart';

class GrabScreen extends ConsumerStatefulWidget {
  const GrabScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<GrabScreen> createState() => _GrabScreenState();
}

class _GrabScreenState extends ConsumerState<GrabScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _grabOrders = [];
  bool _isLoading = false;
  DateTime _selectedDate = DateTime.now();

  // Status tabs
  final List<String> _statusTabs = [
    'Waiting for confirmation',
    'Order accepted',
    'Driver found',
    'Driver has arrived',
    'Order collected',
    'Order delivered',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statusTabs.length, vsync: this);
    _loadGrabOrders();

    // Reload when tab changes
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadGrabOrders();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadGrabOrders() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    final authState = ref.read(authProvider);
    await authState.whenOrNull(
      authenticated: (
        sid,
        apiKey,
        apiSecret,
        username,
        email,
        fullName,
        posProfile,
        branch,
        paymentMethods,
        taxes,
        hasOpening,
        tier,
        printKitchenOrder,
        openingDate,
        itemsGroups,
        baseUrl,
        merchantId,
        printMerchantReceiptCopy,
        enableFiuu,
        cashDrawerPinNeeded,
        cashDrawerPin,
      ) async {
        try {
          final fromDate = DateFormat('yyyy-MM-dd').format(_selectedDate);
          final toDate = DateFormat('yyyy-MM-dd').format(_selectedDate);

          // Get kitchen stations to use the first one for API call
          final stationsResponse =
              await _safeApiCall(() => PosService().getKitchenStations(
                    posProfile: posProfile,
                  ));

          String kitchenStation = '';
          if (stationsResponse['success'] == true) {
            final stations = (stationsResponse['message'] as List?) ?? [];
            if (stations.isNotEmpty) {
              kitchenStation = stations.first['name'];
            }
          }

          // Fetch Grab orders
          final response =
              await _safeApiCall(() => PosService().getKitchenOrders(
                    posProfile: posProfile,
                    kitchenStation: kitchenStation,
                    fromDate: fromDate,
                    toDate: toDate,
                    orderSource: 'grab',
                  ));

          if (!mounted) return;

          if (response['success'] == true) {
            final orders = (response['message'] as List?) ?? [];
            if (mounted) {
              setState(() {
                _grabOrders = orders.cast<Map<String, dynamic>>();
              });
            }
          }
        } catch (e) {
          print('Error loading GRAB orders: $e');
          if (mounted) {
            Fluttertoast.showToast(
              msg: 'Failed to load Grab orders: $e',
              backgroundColor: Colors.red,
              textColor: Colors.white,
            );
          }
        }
      },
    );

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _acceptOrder(String orderId) async {
    try {
      final response = await _safeApiCall(() =>
          PosService().acceptRejectGrabOrder(
            orderId: orderId,
            toState: 'Accepted',
          ));

      if (response['success'] == true) {
        Fluttertoast.showToast(
          msg: 'Order accepted successfully',
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
        _loadGrabOrders(); // Refresh orders
      } else {
        throw Exception(response['message'] ?? 'Failed to accept order');
      }
    } catch (e) {
      print('Error accepting order: $e');
      Fluttertoast.showToast(
        msg: 'Failed to accept order: $e',
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  Future<void> _rejectOrder(String orderId) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Order'),
        content: const Text('Are you sure you want to reject this order?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await _safeApiCall(() =>
          PosService().acceptRejectGrabOrder(
            orderId: orderId,
            toState: 'Rejected',
          ));

      if (response['success'] == true) {
        Fluttertoast.showToast(
          msg: 'Order rejected',
          backgroundColor: Colors.orange,
          textColor: Colors.white,
        );
        _loadGrabOrders(); // Refresh orders
      } else {
        throw Exception(response['message'] ?? 'Failed to reject order');
      }
    } catch (e) {
      print('Error rejecting order: $e');
      Fluttertoast.showToast(
        msg: 'Failed to reject order: $e',
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  List<Map<String, dynamic>> _getOrdersForCurrentTab() {
    final currentStatus = _statusTabs[_tabController.index];
    
    // TODO: Filter orders by status when API provides status field
    // For now, show all orders in "Waiting for confirmation" tab
    if (_tabController.index == 0) {
      // Waiting for confirmation - show unfulfilled orders
      return _grabOrders.where((order) {
        return order['custom_fulfilled'] != 1;
      }).toList();
    }
    
    // For other tabs, return empty list for now
    // This will be populated once we can get order status from API
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFE732A0),
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Image.asset(
              'assets/icon-grab.png',
              width: 32,
              height: 32,
            ),
            const SizedBox(width: 12),
            const Text(
              'Grab Orders',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            // Date picker
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 20, color: Color(0xFFE732A0)),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null && picked != _selectedDate) {
                        setState(() => _selectedDate = picked);
                        _loadGrabOrders();
                      }
                    },
                    child: Text(
                      DateFormat('dd MMM yyyy').format(_selectedDate),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFE732A0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Refresh button
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _isLoading ? null : _loadGrabOrders,
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: const Color(0xFFE732A0),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFFE732A0),
              indicatorWeight: 3,
              labelStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              tabs: _statusTabs.map((status) {
                final count = _tabController.index == _statusTabs.indexOf(status)
                    ? _getOrdersForCurrentTab().length
                    : 0;
                return Tab(
                  child: Row(
                    children: [
                      Text(status),
                      if (count > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE732A0),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            count.toString(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFE732A0)),
            )
          : TabBarView(
              controller: _tabController,
              children: _statusTabs.map((status) {
                final orders = _getOrdersForCurrentTab();
                
                if (orders.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_bag_outlined,
                          size: 64,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No orders in "$status"',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    return _buildOrderCard(order, status);
                  },
                );
              }).toList(),
            ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order, String status) {
    final orderId = order['name']?.toString() ?? '';
    final items = (order['items'] as List?) ?? [];
    final totalAmount = order['grand_total']?.toDouble() ?? 0.0;
    final orderTime = order['posting_date']?.toString() ?? '';
    final customerName = order['customer']?.toString() ?? 'Guest';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order #$orderId',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      customerName,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'RM ${totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE732A0),
                      ),
                    ),
                    if (orderTime.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        orderTime,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const Divider(height: 24),
            
            // Order items
            ...items.map((item) {
              final itemName = item['item_name']?.toString() ?? '';
              final qty = item['qty']?.toDouble() ?? 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE732A0).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          '${qty.toInt()}x',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE732A0),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        itemName,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),

            // Action buttons for "Waiting for confirmation" tab
            if (status == 'Waiting for confirmation') ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _rejectOrder(orderId),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'Reject',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _acceptOrder(orderId),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE732A0),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'Accept',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<T> _safeApiCall<T>(Future<T> Function() apiCall) async {
    try {
      final mainLayout = MainLayout.of(context);
      if (mainLayout != null) {
        return await mainLayout.safeExecuteAPICall(apiCall);
      }
    } catch (e) {
      debugPrint('MainLayout not available: $e');
    }
    return await apiCall();
  }
}