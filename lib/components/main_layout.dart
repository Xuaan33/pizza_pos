import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shiok_pos_android_app/providers/grab_notifications_provider.dart';
import 'package:shiok_pos_android_app/providers/grab_orders_provider.dart';
import 'package:shiok_pos_android_app/screens/kitchen_screen.dart';
import 'package:shiok_pos_android_app/screens/login_screen.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/components/kitchen_notification_overlay.dart';
import 'package:intl/intl.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';

// KITCHEN-ONLY VERSION - CORRECTED
// Fetches ALL orders from ALL stations (including GRAB from all stations)

class MainLayout extends ConsumerStatefulWidget {
  static MainLayoutState? of(BuildContext context) =>
      context.findAncestorStateOfType<MainLayoutState>();
  
  @override
  ConsumerState<MainLayout> createState() => MainLayoutState();
}

class MainLayoutState extends ConsumerState<MainLayout> {
  bool _isLoggingOut = false;

  // ============ ORDER TRACKING ============
  final Set<String> _notifiedOrders = {}; // Track all notified orders
  
  // Separate caching for GRAB and regular orders per station
  final Map<String, List<Map<String, dynamic>>> _cachedStationOrders = {};
  final Map<String, List<Map<String, dynamic>>> _cachedStationGrabOrders = {};
  
  // ============ REFRESH SYSTEM ============
  Timer? _allOrdersRefreshTimer;
  bool _isLoadingAllOrders = false;
  List<String> _kitchenStations = [];

  // API Queue System
  final List<Future<void> Function()> _apiQueue = [];
  bool _isProcessingQueue = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.read(authProvider.notifier).loadFromSharedPreferences();
      await ref.read(grabNotificationsProvider.notifier).loadNotifiedOrders();

      // Initialize notification overlay
      await KitchenNotificationOverlay.initialize();

      // Load kitchen stations first
      await _loadKitchenStations();

      // Start refresh timer
      _startAllOrdersTimer();

      // Initial load
      _refreshAllOrders();
    });
  }

  @override
  void dispose() {
    _stopAllOrdersTimer();
    KitchenNotificationOverlay.dispose();
    super.dispose();
  }

  // ============ LOAD KITCHEN STATIONS ============
  Future<void> _loadKitchenStations() async {
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
          final response = await PosService().getKitchenStations(
            posProfile: posProfile,
          );

          if (response['success'] == true) {
            final stations = (response['message'] as List?) ?? [];
            _kitchenStations = stations
                .map((s) => s['name']?.toString() ?? '')
                .where((name) => name.isNotEmpty)
                .toList();
            print('✅ Loaded ${_kitchenStations.length} kitchen stations: $_kitchenStations');
          }
        } catch (e) {
          print('❌ Error loading kitchen stations: $e');
        }
      },
    );
  }

  // ============ ALL ORDERS TIMER SYSTEM ============
  void _startAllOrdersTimer() {
    _allOrdersRefreshTimer?.cancel();
    _allOrdersRefreshTimer =
        Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted) {
        _refreshAllOrders();
      }
    });
  }

  void _stopAllOrdersTimer() {
    _allOrdersRefreshTimer?.cancel();
    _allOrdersRefreshTimer = null;
  }

  // ============ BACKGROUND REFRESH FOR ALL ORDERS ============
  Future<void> _refreshAllOrders() async {
    if (_isLoadingAllOrders || !mounted || _kitchenStations.isEmpty) {
      print('⏸️  Skipping refresh - loading: $_isLoadingAllOrders, mounted: $mounted, stations: ${_kitchenStations.length}');
      return;
    }

    _addToApiQueue(() => _performAllOrdersRefresh());
  }

  Future<void> _performAllOrdersRefresh() async {
    _isLoadingAllOrders = true;

    try {
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
            final fromDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
            final toDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

            print('🔄 Checking all ${_kitchenStations.length} kitchen stations for new orders...');

            // Check each kitchen station for BOTH regular AND GRAB orders
            for (var station in _kitchenStations) {
              try {
                // ============ 1. FETCH REGULAR ORDERS FOR THIS STATION ============
                final regularResponse = await PosService().getKitchenOrders(
                  posProfile: posProfile,
                  kitchenStation: station,
                  fromDate: fromDate,
                  toDate: toDate,
                  // No orderSource parameter = regular orders
                );

                if (regularResponse['success'] == true && mounted) {
                  final newOrders = (regularResponse['message'] as List?)
                          ?.cast<Map<String, dynamic>>() ?? [];

                  final cachedOrders = _cachedStationOrders[station] ?? [];

                  if (_hasOrdersChanged(cachedOrders, newOrders)) {
                    print('✅ Regular orders changed for station: $station (${newOrders.length} orders)');

                    // Find new orders
                    final newOrdersList = _findNewOrders(cachedOrders, newOrders);
                    
                    _cachedStationOrders[station] = List.from(newOrders);

                    // Notify for each new order
                    for (var order in newOrdersList) {
                      await _showOrderNotification(
                        order, 
                        isGrab: false,
                        stationName: station,
                      );
                    }
                  }
                }

                // Small delay before next API call
                await Future.delayed(const Duration(milliseconds: 300));

                // ============ 2. FETCH GRAB ORDERS FOR THIS STATION ============
                final grabResponse = await PosService().getKitchenOrders(
                  posProfile: posProfile,
                  kitchenStation: station,
                  fromDate: fromDate,
                  toDate: toDate,
                  orderSource: 'grab', // GRAB orders for this station
                );

                if (grabResponse['success'] == true && mounted) {
                  final newGrabOrders = (grabResponse['message'] as List?)
                          ?.cast<Map<String, dynamic>>() ?? [];

                  final cachedGrabOrders = _cachedStationGrabOrders[station] ?? [];

                  if (_hasOrdersChanged(cachedGrabOrders, newGrabOrders)) {
                    print('✅ GRAB orders changed for station: $station (${newGrabOrders.length} orders)');

                    // Find new orders
                    final newGrabOrdersList = _findNewOrders(cachedGrabOrders, newGrabOrders);
                    
                    _cachedStationGrabOrders[station] = List.from(newGrabOrders);

                    // Update provider with all GRAB orders (combined from all stations)
                    final allGrabOrders = _cachedStationGrabOrders.values
                        .expand((orders) => orders)
                        .toList();
                    ref.read(grabOrdersProvider.notifier).updateOrders(allGrabOrders);

                    // Notify for each new GRAB order
                    for (var order in newGrabOrdersList) {
                      await _showOrderNotification(
                        order, 
                        isGrab: true,
                        stationName: station,
                      );
                    }
                  }
                }

                // Small delay before checking next station
                await Future.delayed(const Duration(milliseconds: 300));

              } catch (e) {
                print('❌ Error loading orders for station $station: $e');
              }
            }

            print('✅ Completed refresh cycle for all ${_kitchenStations.length} stations');

          } catch (e) {
            print('❌ Error in all orders refresh: $e');
          }
        },
      );
    } finally {
      _isLoadingAllOrders = false;
    }
  }

  // ============ DETECT CHANGES ============
  bool _hasOrdersChanged(
    List<Map<String, dynamic>> cached, 
    List<Map<String, dynamic>> newOrders
  ) {
    if (cached.length != newOrders.length) {
      return true;
    }

    final cachedIds = cached
        .map((o) => '${o['name']}_${o['custom_fulfilled']}')
        .toSet();
    final newIds = newOrders
        .map((o) => '${o['name']}_${o['custom_fulfilled']}')
        .toSet();

    return !cachedIds.containsAll(newIds) || !newIds.containsAll(cachedIds);
  }

  // ============ FIND NEW ORDERS ============
  List<Map<String, dynamic>> _findNewOrders(
    List<Map<String, dynamic>> cached,
    List<Map<String, dynamic>> newOrders,
  ) {
    final cachedIds = cached.map((o) => o['name']?.toString() ?? '').toSet();
    
    return newOrders.where((order) {
      final orderId = order['name']?.toString() ?? '';
      final isUnfulfilled = order['custom_fulfilled'] != 1;
      final isNotNotified = !_notifiedOrders.contains(orderId);
      final isNew = !cachedIds.contains(orderId);
      
      return orderId.isNotEmpty && isUnfulfilled && isNotNotified && isNew;
    }).toList();
  }

  // ============ SHOW NOTIFICATION ============
  Future<void> _showOrderNotification(
    Map<String, dynamic> order, {
    required bool isGrab,
    String? stationName,
  }) async {
    try {
      final orderId = order['name']?.toString() ?? 'Unknown';
      final customerName = order['customer_name']?.toString() ?? 'Customer';
      final tableName = order['table']?.toString() ?? 'N/A';

      // Mark as notified
      _notifiedOrders.add(orderId);

      if (mounted && context.mounted) {
        // Play system sound
        await SystemSound.play(SystemSoundType.alert);

        // Show notification overlay
        await KitchenNotificationOverlay.show(
          context,
          orderId: orderId,
          customerName: customerName,
          tableName: tableName,
          isGrab: isGrab,
          stationName: stationName,
          onTap: () {
            print('Notification tapped - already on kitchen screen');
          },
        );

        print('🔔 New order notification: $orderId (${isGrab ? "GRAB" : stationName}) - Table: $tableName');
      }
    } catch (e) {
      print('❌ Error showing notification: $e');
    }
  }

  // ============ API QUEUE SYSTEM ============
  Future<void> _addToApiQueue(Future<void> Function() apiCall) async {
    _apiQueue.add(apiCall);

    if (!_isProcessingQueue) {
      await _processApiQueue();
    }
  }

  Future<void> _processApiQueue() async {
    if (_apiQueue.isEmpty) {
      _isProcessingQueue = false;
      return;
    }

    _isProcessingQueue = true;

    while (_apiQueue.isNotEmpty) {
      final apiCall = _apiQueue.removeAt(0);

      try {
        await apiCall();
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        print('❌ Error in API queue: $e');
      }
    }

    _isProcessingQueue = false;
  }

  // ============ PUBLIC API ============
  Future<T> safeExecuteAPICall<T>(Future<T> Function() apiCall) async {
    final completer = Completer<T>();

    _addToApiQueue(() async {
      try {
        final result = await apiCall();
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } catch (e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      }
    });

    return completer.future;
  }

  // ============ LOGOUT ============
  Future<void> _logout() async {
    final shouldLogout = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text(
              'Logout',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: const Text(
              'Are you sure you want to logout?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.grey[200],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                ),
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
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => LoginPage()),
          (route) => false,
        );
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

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return authState.when(
      initial: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      unauthenticated: () {
        if (!_isLoggingOut) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => LoginPage()),
              (route) => false,
            );
          });
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
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
      ) {
        return Scaffold(
          body: Row(
            children: [
              _buildNavigationSidebar(),
              Expanded(
                child: KitchenScreen(
                  autoRefresh: true,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavigationSidebar() {
    return Container(
      width: 100,
      color: Colors.white,
      child: Column(
        children: [
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () {},
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Image.asset(
                'assets/logo-shiokpos.png',
                width: 60,
                height: 60,
              ),
            ),
          ),
          const Spacer(),
          _buildNavItem(-1, 'assets/img-sidebar-logout.png', 'Logout', _logout),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    String imagePath,
    String label, [
    VoidCallback? action,
  ]) {
    return GestureDetector(
      onTap: action,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Image.asset(
              imagePath,
              color: const Color(0xFF555555),
              width: 40,
              height: 40,
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF555555),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}