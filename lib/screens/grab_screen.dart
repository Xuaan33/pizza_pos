import 'dart:async';
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
  
  // Pause/Resume state
  bool _isStorePaused = false;
  bool _isLoadingStoreStatus = false;
  String? _pauseDuration; // null, "30m", "1h", "24h"
  DateTime? _pauseUntil;

  // Auto-refresh timer
  Timer? _refreshTimer;

  // Status tabs (removed Order collected and Order delivered)
  final List<String> _statusTabs = [
    'Waiting for confirmation',
    'Order accepted',
    'Driver found',
    'Driver has arrived',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statusTabs.length, vsync: this);
    _loadStoreStatus(); // Load store status first
    _loadGrabOrders();
    _startRefreshTimer(); // Start auto-refresh

    // Reload when tab changes
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadGrabOrders();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel(); // Cancel timer
    _tabController.dispose();
    super.dispose();
  }

  // Start 5-second auto-refresh timer
  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted && !_isLoading) {
        debugPrint('🔄 Auto-refreshing Grab orders (silent)...');
        _loadGrabOrders(silent: true); // Silent refresh - no loading indicator
      }
    });
  }

  // Stop refresh timer
  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> _loadStoreStatus() async {
    if (!mounted) return;

    setState(() => _isLoadingStoreStatus = true);

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
          final response = await _safeApiCall(
            () => PosService().getGrabStoreStatus(branch: branch),
          );

          debugPrint('🔍 Grab store status response: $response');

          if (!mounted) return;

          if (response['success'] == true) {
            final status = response['message'];
            // Actual API format: {closeReason: mex_paused, isInSpecialOpeningHourRange: false, isOpen: false}
            if (status is Map) {
              setState(() {
                // Store is paused if isOpen is false and closeReason contains "pause"
                final isOpen = status['isOpen'] ?? true;
                final closeReason = status['closeReason']?.toString() ?? '';
                
                _isStorePaused = !isOpen && closeReason.toLowerCase().contains('pause');
                
                debugPrint('📊 Store Status:');
                debugPrint('   isOpen: $isOpen');
                debugPrint('   closeReason: $closeReason');
                debugPrint('   _isStorePaused: $_isStorePaused');
                
                // Extract duration from closeReason if available
                // e.g. "mex_paused_1h" or just "mex_paused"
                if (closeReason.contains('_')) {
                  final parts = closeReason.split('_');
                  if (parts.length > 2) {
                    _pauseDuration = parts.last; // Get last part (e.g., "1h", "30m")
                  }
                }
              });
            } else if (status is String) {
              // If message is a string, parse it
              setState(() {
                _isStorePaused = status.toLowerCase().contains('pause') || 
                                status.toLowerCase().contains('close');
              });
            }
          }
        } catch (e) {
          print('❌ Error loading store status: $e');
        }
      },
    );

    if (mounted) {
      setState(() => _isLoadingStoreStatus = false);
    }
  }

  Future<void> _showPauseDialog() async {
    final authState = ref.read(authProvider);
    
    String? selectedDuration = '30m';
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Pause Grab Orders'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'How long do you want to pause accepting orders?',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              RadioListTile<String>(
                title: const Text('30 minutes'),
                value: '30m',
                groupValue: selectedDuration,
                activeColor: const Color(0xFFE732A0),
                onChanged: (value) {
                  setDialogState(() => selectedDuration = value);
                },
              ),
              RadioListTile<String>(
                title: const Text('1 hour'),
                value: '1h',
                groupValue: selectedDuration,
                activeColor: const Color(0xFFE732A0),
                onChanged: (value) {
                  setDialogState(() => selectedDuration = value);
                },
              ),
              RadioListTile<String>(
                title: const Text('24 hours'),
                value: '24h',
                groupValue: selectedDuration,
                activeColor: const Color(0xFFE732A0),
                onChanged: (value) {
                  setDialogState(() => selectedDuration = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE732A0),
              ),
              child: const Text(
                'Pause',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || selectedDuration == null) return;

    // Pause the store
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
          final response = await _safeApiCall(
            () => PosService().pauseGrabStore(
              branch: branch,
              isPause: true,
              duration: selectedDuration,
            ),
          );

          if (response['success'] == true) {
            Fluttertoast.showToast(
              msg: 'Grab store paused for $selectedDuration',
              backgroundColor: Colors.orange,
              textColor: Colors.white,
            );
            _loadStoreStatus(); // Reload status
          } else {
            throw Exception(response['message'] ?? 'Failed to pause store');
          }
        } catch (e) {
          print('Error pausing store: $e');
          Fluttertoast.showToast(
            msg: 'Failed to pause store: $e',
            backgroundColor: Colors.red,
            textColor: Colors.white,
          );
        }
      },
    );
  }

  Future<void> _resumeStore() async {
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
          final response = await _safeApiCall(
            () => PosService().pauseGrabStore(
              branch: branch,
              isPause: false,
              duration: '30m', // Backend requires duration even when resuming, pass any value
            ),
          );

          if (response['success'] == true) {
            Fluttertoast.showToast(
              msg: 'Grab store resumed',
              backgroundColor: Colors.green,
              textColor: Colors.white,
            );
            _loadStoreStatus(); // Reload status
          } else {
            throw Exception(response['message'] ?? 'Failed to resume store');
          }
        } catch (e) {
          print('❌ Error resuming store: $e');
          Fluttertoast.showToast(
            msg: 'Failed to resume store: $e',
            backgroundColor: Colors.red,
            textColor: Colors.white,
          );
        }
      },
    );
  }

  Future<void> _loadGrabOrders({bool silent = false}) async {
    if (!mounted) return;

    // Only show loading indicator if not silent refresh
    if (!silent) {
      setState(() => _isLoading = true);
    }

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
            final ordersData = (response['message'] as List?) ?? [];
            
            debugPrint('═══════════════════════════════════════════════');
            debugPrint('📦 GRAB ORDERS LOADED: ${ordersData.length} orders');
            debugPrint('═══════════════════════════════════════════════');
            
            // Create a DEEP copy of orders to prevent item duplication
            final freshOrders = ordersData.map((orderData) {
              // Deep copy each item in the items array
              final itemsList = orderData['items'] is List 
                  ? (orderData['items'] as List).map((item) {
                      return Map<String, dynamic>.from(item as Map);
                    }).toList()
                  : [];
              
              // Create a fresh order with deep copied items
              return <String, dynamic>{
                ...Map<String, dynamic>.from(orderData),
                'items': itemsList,
              };
            }).toList();
            
            // Fetch state for each Grab order
            for (int i = 0; i < freshOrders.length; i++) {
              final order = freshOrders[i];
              debugPrint('\n--- Processing Order ${i + 1}/${freshOrders.length} ---');
              await _fetchOrderState(order);
            }
            
            if (mounted) {
              setState(() {
                // Completely replace the list to avoid any references
                _grabOrders.clear();
                _grabOrders = freshOrders;
              });
              
              debugPrint('\n═══════════════════════════════════════════════');
              debugPrint('✅ FINISHED: ${_grabOrders.length} orders with states');
              debugPrint('═══════════════════════════════════════════════\n');
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

    if (mounted && !silent) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchOrderState(Map<String, dynamic> order) async {
    try {
      final orderName = order['name']?.toString() ?? 'Unknown';
      
      // Check if 'name' field is the Grab order ID (starts with "GF-")
      String grabOrderId;
      
      if (orderName.startsWith('GF-')) {
        // The 'name' field itself is the Grab order ID!
        grabOrderId = orderName; // orderName is non-null String
        debugPrint('🔍 Order: $orderName (Grab Order ID found in "name" field)');
      } else {
        // Try to find Grab order ID in other possible fields
        final customId = order['custom_grab_order_id']?.toString();
        final grabId = order['grab_order_id']?.toString();
        final shortNum = order['short_order_number']?.toString();
        final orderId = order['order_id']?.toString();
        final externalId = order['external_order_id']?.toString();
        
        grabOrderId = customId ?? grabId ?? shortNum ?? orderId ?? externalId ?? '';
        
        debugPrint('🔍 Order: $orderName');
      }
      
      if (grabOrderId == null || grabOrderId.isEmpty) {
        debugPrint('   ⚠️  No Grab order ID found!');
        debugPrint('   📋 Available fields: ${order.keys.toList()}');
        debugPrint('   💡 Check which field contains the Grab ID (e.g., GF-xxxx)');
        debugPrint('   💡 name field value: "$orderName"');
        return;
      }

      debugPrint('   📱 Grab Order ID: $grabOrderId');
      debugPrint('   🌐 Calling getGrabOrderState API...');

      final stateResponse = await _safeApiCall(
        () => PosService().getGrabOrderState(orderId: grabOrderId),
      );

      debugPrint('   📊 API Response:');
      debugPrint('      success: ${stateResponse['success']}');
      debugPrint('      message: ${stateResponse['message']}');
      debugPrint('      message type: ${stateResponse['message'].runtimeType}');
      debugPrint('      full response: $stateResponse');

      if (stateResponse['success'] == true) {
        final message = stateResponse['message'];
        String state = '';
        
        // Handle different response formats
        if (message is String) {
          state = message;
          debugPrint('   ✅ State (String): "$state"');
        } else if (message is Map) {
          // Check various possible keys for state
          state = message['state']?.toString() ?? 
                  message['status']?.toString() ?? 
                  message['order_state']?.toString() ??
                  message.toString();
          debugPrint('   ✅ State (Map): "$state"');
          debugPrint('      Map keys: ${message.keys.toList()}');
        } else {
          state = message.toString();
          debugPrint('   ✅ State (Other): "$state"');
        }
        
        // Store the state in the order object
        order['grab_state'] = state;
        order['grab_state_raw'] = message; // Store raw for debugging
        
        debugPrint('   💾 Stored in order["grab_state"]: "$state"');
      } else {
        debugPrint('   ❌ API returned success: false');
        debugPrint('      Error: ${stateResponse['message']}');
      }
    } catch (e, stackTrace) {
      debugPrint('   ❌ Exception: $e');
      debugPrint('   Stack: $stackTrace');
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
    return _getOrdersForTab(_tabController.index);
  }

  // Get orders for a specific tab index
  List<Map<String, dynamic>> _getOrdersForTab(int tabIndex) {
    return _grabOrders.where((order) {
      final orderState = order['grab_state']?.toString().toLowerCase() ?? '';
      
      // Map state to tabs (only 4 tabs now)
      switch (tabIndex) {
        case 0: // Waiting for confirmation
          // ONLY show if state explicitly says waiting/pending/confirmation
          // Don't show orders without state or other states here
          return orderState.contains('waiting') || 
                 orderState.contains('pending') ||
                 orderState.contains('confirmation');
        
        case 1: // Order accepted
          return orderState.contains('accept') || 
                 orderState.contains('new'); // "New" state means order accepted
        
        case 2: // Driver found
          return (orderState.contains('driver') && orderState.contains('found')) ||
                 (orderState.contains('driver') && orderState.contains('assign')) ||
                 (orderState.contains('driver') && orderState.contains('allocat')); // "Driver Allocated"
        
        case 3: // Driver has arrived
          return orderState.contains('arrived') || orderState.contains('reach');
        
        default:
          return false;
      }
    }).toList();
  }

  // Get count of orders for a specific tab
  int _getOrderCountForTab(int tabIndex) {
    return _getOrdersForTab(tabIndex).length;
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
            const SizedBox(width: 16),
            // Pause/Resume Toggle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _isStorePaused ? Colors.orange : Colors.green,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isStorePaused ? Icons.pause_circle : Icons.check_circle,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isStorePaused ? 'Paused' : 'Accepting',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _isLoadingStoreStatus
                        ? null
                        : () {
                            if (_isStorePaused) {
                              _resumeStore();
                            } else {
                              _showPauseDialog();
                            }
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _isStorePaused ? 'Resume' : 'Pause',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
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
              tabs: _statusTabs.asMap().entries.map((entry) {
                final index = entry.key;
                final status = entry.value;
                final count = _getOrderCountForTab(index);
                
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
    final orderTime = order['order_time']?.toString() ?? 
                     order['posting_time']?.toString() ?? 
                     order['posting_date']?.toString() ?? '';
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
                Expanded(
                  child: Column(
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
                      if (orderTime.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _getTimeAgo(orderTime),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
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

  // Format time as "X mins ago" like kitchen screen
  String _getTimeAgo(String? timeString) {
    if (timeString == null || timeString.isEmpty) return 'N/A';
    
    try {
      final orderTime = DateTime.parse(timeString);
      final now = DateTime.now();
      final difference = now.difference(orderTime);
      
      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes} min${difference.inMinutes == 1 ? '' : 's'} ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
      } else {
        return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
      }
    } catch (e) {
      debugPrint('Error parsing time: $e');
      return timeString;
    }
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