import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiok_pos_android_app/components/kitchen_notification_overlay.dart';
import 'package:shiok_pos_android_app/components/receipt_printer.dart';
import 'package:shiok_pos_android_app/providers/grab_notifications_provider.dart';
import 'package:shiok_pos_android_app/providers/grab_orders_provider.dart';
import 'package:shiok_pos_android_app/providers/kitchen_notifications_provider.dart';
import 'package:shiok_pos_android_app/screens/Settings%20Screen/settings_screen.dart';
import 'package:shiok_pos_android_app/screens/home_screen.dart';
import 'package:shiok_pos_android_app/screens/kitchen_screen.dart';
import 'package:shiok_pos_android_app/screens/grab_screen.dart';
import 'package:shiok_pos_android_app/screens/login_screen.dart';
import 'package:shiok_pos_android_app/screens/table_screen.dart';
import 'package:shiok_pos_android_app/screens/orders_screen.dart';
import 'package:shiok_pos_android_app/screens/dashboard_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/secondary%20screen/customer_display_controller.dart';
import 'package:shiok_pos_android_app/service/notification_queue.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';
import 'package:shiok_pos_android_app/components/grab_notification_overlay.dart';

class MainLayout extends ConsumerStatefulWidget {
  static MainLayoutState? of(BuildContext context) =>
      context.findAncestorStateOfType<MainLayoutState>();
  @override
  ConsumerState<MainLayout> createState() => MainLayoutState();
}

class MainLayoutState extends ConsumerState<MainLayout> {
  int _selectedTabIndex = 0;
  List<Map<String, dynamic>> activeOrders = [];
  Set<int> tablesWithSubmittedOrders = {};
  bool _isOrdersLoading = false;
  bool _isLoggingOut = false;
  Future<void>? _refreshFuture;
  DateTime _selectedDate = DateTime.now();
  String _filterStatus = 'All';
  String _filterOrderType = 'All';
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _useDateRange = false;
  int _currentPage = 0;
  bool _hasMoreOrders = true;
  bool _isLoadingMore = false;
  final ScrollController _ordersScrollController = ScrollController();
  ScrollController get ordersScrollController => _ordersScrollController;
  bool get hasMoreOrders => _hasMoreOrders;
  bool get isLoadingMore => _isLoadingMore;
  bool _customerDisplayInitialized = false;

  // ============ IMPROVED GRAB REFRESH SYSTEM ============
  Timer? _globalGrabRefreshTimer;
  List<Map<String, dynamic>> _cachedGrabOrders = []; // Cache for comparison
  bool _isLoadingGlobalGrab = false;
  DateTime? _lastGlobalGrabLoad;

  // API Queue System
  final List<Future<void> Function()> _apiQueue = [];
  bool _isProcessingQueue = false;
  Completer<void>? _currentApiCall;

  final GlobalKey<SettingsScreenState> settingsScreenKey =
      GlobalKey<SettingsScreenState>();
  late FlutterLocalNotificationsPlugin _localNotifications;

  // ============ GRAB ORDERS BADGE COUNT ============
  /// Get the count of pending Grab orders for navigation badge
  int get _pendingGrabOrdersCount {
    final grabOrders = ref.read(grabOrdersProvider);
    return grabOrders.where((order) {
      return order['custom_fulfilled'] != 1; // Count unfulfilled orders
    }).length;
  }

// Separate caching for kitchen orders per station
  final Map<String, List<Map<String, dynamic>>> _cachedStationOrders = {};
  final Map<String, List<Map<String, dynamic>>> _cachedStationGrabOrders = {};

// ============ KITCHEN REFRESH SYSTEM ============
  Timer? _allOrdersRefreshTimer;
  bool _isLoadingAllOrders = false;
  List<String> _kitchenStations = [];

  // ============ NEW: Dashboard refresh callback ============
  VoidCallback? _dashboardRefreshCallback;

  @override
  void initState() {
    super.initState();
    _ordersScrollController.addListener(_onOrdersScroll);

    _initializeLocalNotifications();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeCustomerDisplay();
      ref.read(authProvider.notifier).loadFromSharedPreferences();
      await ref.read(grabNotificationsProvider.notifier).loadNotifiedOrders();
      await ref
          .read(kitchenNotificationsProvider.notifier)
          .loadNotifiedOrders();

      // Initialize both notification overlays
      await GrabNotificationOverlay.initialize();
      await KitchenNotificationOverlay.initialize();
      Future.delayed(const Duration(milliseconds: 2500), () async {
        if (mounted) {
          await _processQueuedNotifications();
        }
      });

      // Load kitchen stations
      await _loadKitchenStations();

      // Start timers
      _startGlobalGrabTimer();
      _startAllOrdersTimer();

      // Initial loads
      _refreshGlobalGrabOrders();
      _refreshAllOrders();
    });
  }

  Future<void> _initializeLocalNotifications() async {
    _localNotifications = FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _handleNotificationTap(response);
      },
    );
  }

  void _handleNotificationTap(NotificationResponse response) {
    if (mounted) {
      final authState = ref.read(authProvider);
      authState.whenOrNull(
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
          final ordersTabIndex = tier.toLowerCase() != 'tier 3' ? 3 : 4;
          setState(() {
            _selectedTabIndex = ordersTabIndex;
          });
        },
      );
    }
  }

  // ============ GRAB TIMER SYSTEM ============
  void _startGlobalGrabTimer() {
    _globalGrabRefreshTimer?.cancel();

    _globalGrabRefreshTimer =
        Timer.periodic(const Duration(seconds: 15), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _refreshGlobalGrabOrders();
    });
  }

  void _stopGlobalGrabTimer() {
    _globalGrabRefreshTimer?.cancel();
    _globalGrabRefreshTimer = null;
  }

  // ============ ALL ORDERS TIMER SYSTEM ============
  void _startAllOrdersTimer() {
    _allOrdersRefreshTimer?.cancel();
    _allOrdersRefreshTimer =
        Timer.periodic(const Duration(seconds: 15), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _refreshAllOrders();
    });
  }

  void _stopAllOrdersTimer() {
    _allOrdersRefreshTimer?.cancel();
    _allOrdersRefreshTimer = null;
  }

  /// Process any queued notifications that were saved during checkout
  Future<void> _processQueuedNotifications() async {
    try {
      final queuedOrderIds = await NotificationQueue.getAndClearQueue();

      if (queuedOrderIds.isEmpty) {
        debugPrint('📭 No queued notifications');
        return;
      }

      debugPrint(
          '📬 Processing ${queuedOrderIds.length} queued notification(s)');

      for (final orderId in queuedOrderIds) {
        // Small delay between notifications
        await Future.delayed(const Duration(milliseconds: 500));

        if (mounted) {
          await triggerKitchenNotificationForOrder(orderId);
        }
      }
    } catch (e) {
      debugPrint('❌ Error processing queued notifications: $e');
    }
  }

  // ============ BACKGROUND REFRESH WITHOUT FLICKERING ============
  Future<void> _refreshGlobalGrabOrders() async {
    // Don't start a new refresh if one is already in progress
    if (_isLoadingGlobalGrab || !mounted) {
      print('⏸️  Skipping GRAB refresh - already loading or not mounted');
      return;
    }

    // Add to queue instead of executing immediately
    _addToApiQueue(() => _performGrabRefresh());
  }

  Future<void> _performGrabRefresh() async {
    if (!mounted) return; // Early return if not mounted
    _isLoadingGlobalGrab = true;

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
            if (!mounted) return; // Early return if not mounted
            final fromDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
            final toDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

            // Get first kitchen station
            final stationsResponse = await PosService().getKitchenStations(
              posProfile: posProfile,
            );

            String firstStation = '';
            if (stationsResponse['success'] == true) {
              final stations = (stationsResponse['message'] as List?) ?? [];
              if (stations.isNotEmpty) {
                firstStation = stations[0]['name']?.toString() ?? '';
              }
            }

            if (firstStation.isNotEmpty) {
              final response = await PosService().getKitchenOrders(
                posProfile: posProfile,
                kitchenStation: firstStation,
                fromDate: fromDate,
                toDate: toDate,
                orderSource: 'grab',
              );

              if (response['success'] == true && mounted) {
                final newOrders = (response['message'] as List?)
                        ?.cast<Map<String, dynamic>>() ??
                    [];

                // Only update if there are actual changes
                if (_hasOrdersChanged(newOrders)) {
                  print('✅ GRAB orders changed, updating...');

                  // Update cached orders
                  _cachedGrabOrders = List.from(newOrders);
                  _lastGlobalGrabLoad = DateTime.now();

                  // Update provider (this won't cause flickering)
                  ref.read(grabOrdersProvider.notifier).updateOrders(newOrders);

                  // Check for new orders and notify
                  await _checkAndNotifyNewOrders(newOrders);
                } else {
                  print('ℹ️  No changes in GRAB orders');
                }
              }
            }
          } catch (e) {
            print('❌ Error loading GRAB orders: $e');
          }
        },
      );
    } finally {
      if (mounted) {
        _isLoadingGlobalGrab = false;
      }
    }
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
          final response = await safeExecuteAPICall(
              () => PosService().getKitchenStations(posProfile: posProfile));

          if (response['success'] == true) {
            final stations = (response['message'] as List?) ?? [];
            _kitchenStations = stations
                .map((s) => s['name']?.toString() ?? '')
                .where((name) => name.isNotEmpty)
                .toList();
            debugPrint(
                '✅ Loaded ${_kitchenStations.length} kitchen stations: $_kitchenStations');
          }
        } catch (e) {
          debugPrint('❌ Error loading kitchen stations: $e');
        }
      },
    );
  }

  bool _hasKitchenStations() {
    return _kitchenStations.isNotEmpty;
  }

  // ============ BACKGROUND REFRESH FOR ALL KITCHEN ORDERS ============
  Future<void> _refreshAllOrders() async {
    if (_isLoadingAllOrders || !mounted || _kitchenStations.isEmpty) {
      debugPrint(
          '⏸️  Skipping kitchen refresh - loading: $_isLoadingAllOrders, mounted: $mounted, stations: ${_kitchenStations.length}');
      return;
    }

    _addToApiQueue(() => _performAllOrdersRefresh());
  }

  Future<void> _performAllOrdersRefresh() async {
    if (!mounted) return; // Early return if not mounted

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
            if (!mounted) return; // Early return if not mounted
            final fromDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
            final toDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

            debugPrint(
                '🔄 Checking all ${_kitchenStations.length} kitchen stations for new orders...');

            // Check each kitchen station for BOTH regular AND GRAB orders
            for (var station in _kitchenStations) {
              try {
                // ============ 1. FETCH REGULAR ORDERS FOR THIS STATION ============
                final regularResponse = await PosService().getKitchenOrders(
                  posProfile: posProfile,
                  kitchenStation: station,
                  fromDate: fromDate,
                  toDate: toDate,
                );

                if (regularResponse['success'] == true && mounted) {
                  final newOrders = (regularResponse['message'] as List?)
                          ?.cast<Map<String, dynamic>>() ??
                      [];

                  final cachedOrders = _cachedStationOrders[station] ?? [];

                  if (_hasKitchenOrdersChanged(cachedOrders, newOrders)) {
                    debugPrint(
                        '✅ Regular orders changed for station: $station (${newOrders.length} orders)');

                    // Find new orders
                    final newOrdersList =
                        _findNewKitchenOrders(cachedOrders, newOrders);

                    _cachedStationOrders[station] = List.from(newOrders);

                    // Notify for each new order
                    for (var order in newOrdersList) {
                      await _showKitchenOrderNotification(
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
                  orderSource: 'grab',
                );

                if (grabResponse['success'] == true && mounted) {
                  final newGrabOrders = (grabResponse['message'] as List?)
                          ?.cast<Map<String, dynamic>>() ??
                      [];

                  final cachedGrabOrders =
                      _cachedStationGrabOrders[station] ?? [];

                  if (_hasKitchenOrdersChanged(
                      cachedGrabOrders, newGrabOrders)) {
                    debugPrint(
                        '✅ GRAB orders changed for station: $station (${newGrabOrders.length} orders)');

                    // Find new orders
                    final newGrabOrdersList =
                        _findNewKitchenOrders(cachedGrabOrders, newGrabOrders);

                    _cachedStationGrabOrders[station] =
                        List.from(newGrabOrders);

                    // Update provider with all GRAB orders (combined from all stations)
                    final allGrabOrders = _cachedStationGrabOrders.values
                        .expand((orders) => orders)
                        .toList();
                    ref
                        .read(grabOrdersProvider.notifier)
                        .updateOrders(allGrabOrders);

                    // Notify for each new GRAB order
                    for (var order in newGrabOrdersList) {
                      await _showKitchenOrderNotification(
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
                debugPrint('❌ Error loading orders for station $station: $e');
              }
            }

            debugPrint(
                '✅ Completed kitchen refresh cycle for all ${_kitchenStations.length} stations');
          } catch (e) {
            debugPrint('❌ Error in all orders refresh: $e');
          }
        },
      );
    } finally {
      if (mounted) {
        _isLoadingAllOrders = false;
      }
    }
  }

  /// Register dashboard refresh callback
  void registerDashboardRefreshCallback(VoidCallback callback) {
    _dashboardRefreshCallback = callback;
    debugPrint('✅ Dashboard refresh callback registered');
  }

  /// Unregister dashboard refresh callback
  void unregisterDashboardRefreshCallback() {
    _dashboardRefreshCallback = null;
    debugPrint('🛑 Dashboard refresh callback unregistered');
  }

  /// Trigger dashboard refresh
  void _triggerDashboardRefresh() {
    if (_dashboardRefreshCallback != null) {
      debugPrint('🔄 Triggering dashboard refresh from notification...');
      _dashboardRefreshCallback!();
    }
  }

  // ============ DETECT CHANGES WITHOUT REBUILDING UI ============

  // ============ DETECT KITCHEN ORDER CHANGES ============
  bool _hasKitchenOrdersChanged(
      List<Map<String, dynamic>> cached, List<Map<String, dynamic>> newOrders) {
    if (cached.length != newOrders.length) {
      return true;
    }

    final cachedIds =
        cached.map((o) => '${o['name']}_${o['custom_fulfilled']}').toSet();
    final newIds =
        newOrders.map((o) => '${o['name']}_${o['custom_fulfilled']}').toSet();

    return !cachedIds.containsAll(newIds) || !newIds.containsAll(cachedIds);
  }

// ============ FIND NEW KITCHEN ORDERS ============
  List<Map<String, dynamic>> _findNewKitchenOrders(
    List<Map<String, dynamic>> cached,
    List<Map<String, dynamic>> newOrders,
  ) {
    final notificationProvider =
        ref.read(kitchenNotificationsProvider.notifier);
    final cachedIds = cached.map((o) => o['name']?.toString() ?? '').toSet();

    return newOrders.where((order) {
      final orderId = order['name']?.toString() ?? '';
      final isUnfulfilled = order['custom_fulfilled'] != 1;
      final isNotNotified = !notificationProvider.hasBeenNotified(orderId);
      final isNotPending =
          !notificationProvider.isPendingPayment(orderId); // 🔥 ADD THIS
      final isNew = !cachedIds.contains(orderId);

      // 🔥 Also check isNotPending
      return orderId.isNotEmpty &&
          isUnfulfilled &&
          isNotNotified &&
          isNotPending &&
          isNew;
    }).toList();
  }

  bool _hasOrdersChanged(List<Map<String, dynamic>> newOrders) {
    if (_cachedGrabOrders.length != newOrders.length) {
      return true;
    }

    // Compare order IDs and fulfillment status
    final cachedIds = _cachedGrabOrders
        .map((o) => '${o['name']}_${o['custom_fulfilled']}')
        .toSet();
    final newIds =
        newOrders.map((o) => '${o['name']}_${o['custom_fulfilled']}').toSet();

    return !cachedIds.containsAll(newIds) || !newIds.containsAll(cachedIds);
  }

  // ============ API QUEUE SYSTEM ============
  Future<void> _addToApiQueue(Future<void> Function() apiCall) async {
    _apiQueue.add(apiCall);

    // Start processing if not already processing
    if (!_isProcessingQueue) {
      await _processApiQueue();
    }
  }

  Future<void> _processApiQueue() async {
    if (_apiQueue.isEmpty || !mounted) {
      _isProcessingQueue = false;
      return;
    }

    _isProcessingQueue = true;

    while (_apiQueue.isNotEmpty && mounted) {
      final apiCall = _apiQueue.removeAt(0);

      try {
        await apiCall();

        // Small delay between API calls to prevent overwhelming the server
        if (mounted) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      } catch (e) {
        print('❌ Error in API queue: $e');
      }
    }

    _isProcessingQueue = false;
  }

  // ============ NOTIFICATION SYSTEM ============
  Future<void> _checkAndNotifyNewOrders(
      List<Map<String, dynamic>> orders) async {
    final notificationProvider = ref.read(grabNotificationsProvider.notifier);
    final newOrders = notificationProvider.filterNewOrders(orders);

    if (newOrders.isNotEmpty) {
      print('🔔 Found ${newOrders.length} new GRAB order(s)');

      for (var order in newOrders) {
        final orderId = order['name']?.toString() ?? '';
        if (orderId.isNotEmpty) {
          await _showGrabNotification(order);
          await notificationProvider.markAsNotified(orderId);
        }
      }
    }
  }

  Future<void> _showGrabNotification(Map<String, dynamic> order) async {
    try {
      final orderId = order['name']?.toString() ?? 'Unknown';
      final customerName = order['customer_name']?.toString() ?? 'Customer';

      // ============ Trigger dashboard refresh ============
      _triggerDashboardRefresh();

      // Show custom in-app notification overlay
      if (mounted && context.mounted) {
        await GrabNotificationOverlay.show(
          context,
          orderId: orderId,
          customerName: customerName,
          onTap: () {
            // Navigate to Kitchen screen with GRAB station selected
            final authState = ref.read(authProvider);
            authState.whenOrNull(
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
                final kitchenTabIndex = tier.toLowerCase() != 'tier 3' ? 3 : 4;
                final orderTabIndex = tier.toLowerCase() != 'tier 3' ? 1 : 2;
                final hasKitchenStations = _hasKitchenStations();
                if (mounted) {
                  setState(() {
                    _selectedTabIndex =
                        hasKitchenStations ? kitchenTabIndex : orderTabIndex;
                  });
                }
              },
            );
          },
        );
      }
    } catch (e) {
      print('❌ Error showing notification: $e');
    }
  }

// ============ SHOW KITCHEN ORDER NOTIFICATION ============
  Future<void> triggerKitchenNotificationForOrder(String orderId) async {
    try {
      debugPrint('🔔 Manually triggering notification for order: $orderId');

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
          // Fetch the order details from the API
          final response = await PosService().getOrders(
            posProfile: posProfile,
            search: orderId,
          );

          if (response['success'] == true &&
              response['message'] != null &&
              (response['message'] as List).isNotEmpty) {
            final order = (response['message'] as List).first;
            final tableName = order['table']?.toString() ?? 'N/A';
            final orderChannel =
                order['custom_order_channel']?.toString() ?? '';
            final isGrab = orderChannel.toLowerCase().contains('grab');

            debugPrint(
                '📦 Order details fetched: $orderId, table: $tableName, isGrab: $isGrab');

            // Show the notification
            await _showKitchenOrderNotification(
              order,
              isGrab: isGrab,
              stationName: isGrab ? 'GRAB' : 'Kitchen',
            );

            debugPrint(
                '✅ Notification triggered successfully for order $orderId');
          } else {
            debugPrint('⚠️ Could not fetch order details for $orderId');
            debugPrint('Response: ${response}');
          }
        },
      );
    } catch (e) {
      debugPrint('❌ Error triggering notification for order $orderId: $e');
    }
  }

  Future<void> _showKitchenOrderNotification(
    Map<String, dynamic> order, {
    required bool isGrab,
    String? stationName,
  }) async {
    try {
      final orderId = order['name']?.toString() ?? 'Unknown';
      final customerName = order['customer_name']?.toString() ?? 'Customer';
      final tableName = order['table']?.toString() ?? 'N/A';

      if (orderId != 'Unknown') {
        await ref
            .read(kitchenNotificationsProvider.notifier)
            .markAsNotified(orderId);
        debugPrint('✅ Marked order as notified: $orderId');
      }

      // ============ AUTO PRINT KITCHEN ORDER ============
      // Print kitchen order automatically when notification comes in
      if (orderId != 'Unknown') {
        try {
          debugPrint('🖨️ Auto-printing kitchen order for: $orderId');
          
          // Check if printing is enabled in settings
          final authState = ref.read(authProvider);
          final shouldPrint = await authState.whenOrNull(
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
              return printKitchenOrder == 1;
            },
          );

          if (shouldPrint == true) {
            // Print kitchen order in background (don't await to avoid blocking notification)
            ReceiptPrinter.printKitchenOrderOnly(orderId).then((_) {
              debugPrint('✅ Kitchen order auto-printed successfully: $orderId');
            }).catchError((e) {
              debugPrint('❌ Kitchen order auto-print failed: $e');
              // Don't show error to user - printing is background task
            });
          } else {
            debugPrint('⏭️ Kitchen order printing disabled in settings');
          }
        } catch (e) {
          debugPrint('❌ Error in auto-print: $e');
          // Don't throw - notification should still show even if printing fails
        }
      }

      // ============ Trigger dashboard refresh ============
      _triggerDashboardRefresh();

      if (mounted && context.mounted) {
        // Show notification overlay
        await KitchenNotificationOverlay.show(
          context,
          orderId: orderId,
          customerName: customerName,
          tableName: tableName,
          isGrab: isGrab,
          stationName: stationName,
          onTap: () {
            // Navigate to Kitchen screen with GRAB station selected
            final authState = ref.read(authProvider);
            authState.whenOrNull(
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
                final kitchenTabIndex = tier.toLowerCase() != 'tier 3' ? 3 : 4;
                final orderTabIndex = tier.toLowerCase() != 'tier 3' ? 1 : 2;
                final hasKitchenStations = _hasKitchenStations();

                if (mounted) {
                  setState(() {
                    _selectedTabIndex =
                        hasKitchenStations ? kitchenTabIndex : orderTabIndex;
                  });
                }
              },
            );

            debugPrint(
                '🔔 New kitchen order notification: $orderId (${isGrab ? "GRAB" : stationName}) - Table: $tableName');
          },
        );
      }
    } catch (e) {
      debugPrint('❌ Error showing kitchen notification: $e');
    }
  }

  // ============ PUBLIC API WRAPPER ============
  /// Wrap other API calls with this method to prevent conflicts with GRAB refresh
  Future<T> executeProtectedAPICall<T>(Future<T> Function() apiCall) async {
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

  Future<T> safeExecuteAPICall<T>(Future<T> Function() apiCall) async {
    try {
      final mainLayout = MainLayout.of(context);
      if (mainLayout != null) {
        return await mainLayout.executeProtectedAPICall(apiCall);
      }
    } catch (e) {
      debugPrint('MainLayout not available, executing API call directly: $e');
    }
    return await apiCall(); // Fallback to direct call
  }

  Future<void> _initializeCustomerDisplay() async {
    if (!_customerDisplayInitialized) {
      try {
        await CustomerDisplayController.showCustomerScreen();
        setState(() {
          _customerDisplayInitialized = true;
        });
      } catch (e) {
        print('Error initializing customer display: $e');
      }
    }
  }

  @override
  void dispose() {
    _ordersScrollController.removeListener(_onOrdersScroll);
    _ordersScrollController.dispose();
    _globalGrabRefreshTimer?.cancel();
    _allOrdersRefreshTimer?.cancel();

    // Clear the API queue
    _apiQueue.clear();
    _isProcessingQueue = false;

    GrabNotificationOverlay.dispose();
    KitchenNotificationOverlay.dispose();
    super.dispose();
  }

  void _onOrdersScroll() {
    if (_ordersScrollController.position.pixels >=
            _ordersScrollController.position.maxScrollExtent - 100 &&
        !_isLoadingMore &&
        _hasMoreOrders &&
        _selectedTabIndex == (_getOrdersTabIndex())) {
      _loadMoreOrders();
    }
  }

  int _getOrdersTabIndex() {
    final authState = ref.read(authProvider);
    return authState.whenOrNull(
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
            return tier.toLowerCase() != 'tier 3' ? 1 : 2;
          },
        ) ??
        2;
  }

  Future<void> _loadMoreOrders() async {
    if (!mounted || _isLoadingMore || !_hasMoreOrders) return;

    setState(() => _isLoadingMore = true);

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
            String? fromDateStr;
            String? toDateStr;
            if (_useDateRange && _fromDate != null && _toDate != null) {
              fromDateStr = DateFormat('yyyy-MM-dd').format(_fromDate!);
              toDateStr = DateFormat('yyyy-MM-dd').format(_toDate!);
            } else {
              fromDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
              toDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
            }

            String? apiStatus;
            if (_filterStatus == 'Pay Later') {
              apiStatus = 'Draft';
            } else if (_filterStatus == 'Paid') {
              apiStatus = null;
            } else if (_filterStatus == 'Cancelled') {
              apiStatus = 'Cancelled';
            }

            final effectivePageLimit = 30;
            final nextStart = (_currentPage + 1) * effectivePageLimit;

            final response =
                await safeExecuteAPICall(() => PosService().getOrders(
                      posProfile: posProfile,
                      fromDate: fromDateStr,
                      toDate: toDateStr,
                      status: apiStatus,
                      pageLength: effectivePageLimit,
                      start: nextStart,
                    ));

            if (!mounted) return;

            if (response['message']?['success'] == true) {
              final List<dynamic> invoices =
                  (response['message']?['message'] as List?) ?? [];

              if (invoices.isEmpty) {
                setState(() {
                  _hasMoreOrders = false;
                });
              } else {
                List<Map<String, dynamic>> newOrders = invoices
                    .map((invoice) {
                      try {
                        final items =
                            (invoice['items'] as List? ?? []).map((item) {
                          return {
                            'name':
                                item['item_name']?.toString() ?? 'Unknown Item',
                            'price': (item['rate'] as num?)?.toDouble() ?? 0.0,
                            'quantity':
                                (item['qty'] as num?)?.toDouble() ?? 1.0,
                            'item_code': item['item_code']?.toString() ?? '',
                            'options': item['options'] ?? {},
                            'option_text': item['option_text'] ?? '',
                            'custom_serve_later': item['custom_serve_later'],
                            'custom_item_remarks':
                                item['custom_item_remarks']?.toString() ?? '',
                            'custom_variant_info':
                                item['custom_variant_info']?.toString() ?? '',
                            'discount_amount':
                                (item['discount_amount'] as num?)?.toDouble() ??
                                    0.0,
                            'image': (item['image'])
                          };
                        }).toList();

                        Map<String, dynamic>? taxBreakdown;
                        final taxes = invoice['taxes'] as List?;
                        if (taxes != null && taxes.isNotEmpty) {
                          taxBreakdown = {
                            'rate':
                                (taxes[0]['rate'] as num?)?.toDouble() ?? 0.0,
                            'amount':
                                (taxes[0]['amount'] as num?)?.toDouble() ?? 0.0,
                            'description':
                                taxes[0]['account_head']?.toString() ?? 'Tax',
                          };
                        }

                        DateTime? parseDate(String? dateString) {
                          try {
                            return dateString != null
                                ? DateTime.parse(dateString)
                                : null;
                          } catch (_) {
                            return null;
                          }
                        }

                        final payments = invoice['payments'] as List? ?? [];
                        String? m1Value;
                        if (payments.isNotEmpty) {
                          m1Value =
                              payments[0]['custom_fiuu_m1_value']?.toString();
                        }

                        return {
                          'orderId': invoice['name']?.toString() ?? 'Unknown',
                          'invoiceNumber':
                              invoice['name']?.toString() ?? 'Unknown',
                          'status': invoice['status']?.toString() ?? 'Draft',
                          'orderType':
                              invoice['custom_order_channel']?.toString() ?? '',
                          'tableNumber': (invoice['custom_table'] ?? ''),
                          'items': items,
                          'subtotal':
                              (invoice['rounded_total'] as num?)?.toDouble() ??
                                  0.0,
                          'tax': taxBreakdown?['amount'] ?? 0.0,
                          'total':
                              (invoice['rounded_total'] as num?)?.toDouble() ??
                                  0.0,
                          'entryTime':
                              parseDate(invoice['modified']?.toString()) ??
                                  DateTime.now(),
                          'paidTime': invoice['status']?.toString() == 'Paid'
                              ? parseDate(invoice['modified']?.toString())
                              : null,
                          'isPaid': invoice['status']?.toString() == 'Paid' ||
                              invoice['status']?.toString() == 'Consolidated',
                          'paymentMethod': payments.isNotEmpty == true
                              ? payments[0]['mode_of_payment']?.toString() ??
                                  'Cash'
                              : 'Cash',
                          'm1value': m1Value,
                          'customerName':
                              invoice['customer_name']?.toString() ?? 'Guest',
                          'remarks': invoice['remarks']?.toString() ?? '',
                          'custom_item_remarks':
                              invoice['custom_item_remarks']?.toString() ??
                                  'N/A',
                          'taxBreakdown': taxBreakdown,
                          'paidAmount':
                              (invoice['paid_amount'] as num?)?.toDouble() ??
                                  0.0,
                          'changeAmount':
                              (invoice['change_amount'] as num?)?.toDouble() ??
                                  0.0,
                          'base_rounding_adjustment':
                              (invoice['base_rounding_adjustment'] as num?)
                                      ?.toDouble() ??
                                  0.0,
                          "pos_invoice_number":
                              invoice['custom_fiuu_invoice_number']
                                      ?.toString() ??
                                  '000000',
                          'total_taxes_and_charges':
                              (invoice['total_taxes_and_charges'] as num?)
                                      ?.toDouble() ??
                                  0.0,
                          'discount_amount':
                              (invoice['discount_amount'] as num?)?.toDouble(),
                          'user_voucher_code': (invoice['user_voucher_code']),
                          'custom_is_refund': (invoice['custom_is_refund'] ?? 0)
                        };
                      } catch (e) {
                        print(
                            'Error processing invoice ${invoice['name']}: $e');
                        return null;
                      }
                    })
                    .where((order) => order != null)
                    .cast<Map<String, dynamic>>()
                    .toList();

                // Sort new orders
                newOrders.sort((a, b) {
                  final isPayLaterA =
                      a['status']?.toString().toLowerCase() == 'draft';
                  final isPayLaterB =
                      b['status']?.toString().toLowerCase() == 'draft';

                  if (isPayLaterA && isPayLaterB) {
                    final timeA = a['entryTime'] as DateTime;
                    final timeB = b['entryTime'] as DateTime;
                    return timeB.compareTo(timeA);
                  } else if (isPayLaterA) {
                    return -1;
                  } else if (isPayLaterB) {
                    return 1;
                  } else {
                    final idA = a['orderId']?.toString() ?? '';
                    final idB = b['orderId']?.toString() ?? '';
                    return idB.compareTo(idA);
                  }
                });

                setState(() {
                  activeOrders.addAll(newOrders);
                  _currentPage++;
                });
              }
            }
          } on SessionTimeoutException {
            await ref.read(authProvider.notifier).logout();
          }
        },
      );
    } catch (e) {
      print('Error loading more orders: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
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
            showDialog(
                context: context,
                builder: (context) => AlertDialog(
                      title: const Text('Session Timeout'),
                      content: const Text(
                          'Your session has expired. Please login again.'),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => LoginPage()),
                              (Route<dynamic> route) => false,
                            );
                          },
                          child: const Text('OK'),
                        ),
                      ],
                    ));
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

  Future<void> _refreshOrders({bool forceAllForPayLater = false}) async {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      setState(() {
        _isOrdersLoading = true;
        _currentPage = 0;
        _hasMoreOrders = true;
        _isLoadingMore = false;
      });
      _loadOrdersData(forceAllForPayLater);
    });
  }

  Future<void> _loadOrdersData(bool forceAllForPayLater) async {
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
            String? fromDateStr;
            String? toDateStr;

            if (_useDateRange && _fromDate != null && _toDate != null) {
              fromDateStr = DateFormat('yyyy-MM-dd').format(_fromDate!);
              toDateStr = DateFormat('yyyy-MM-dd').format(_toDate!);
            } else {
              fromDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
              toDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
            }

            String? apiStatus;
            if (_filterStatus == 'Pay Later') {
              apiStatus = 'Draft';
            } else if (_filterStatus == 'Paid') {
              apiStatus = null;
            } else if (_filterStatus == 'Cancelled') {
              apiStatus = 'Cancelled';
            }

            final effectivePageLimit = 30;

            final future = safeExecuteAPICall(() => PosService().getOrders(
                  posProfile: posProfile,
                  fromDate: fromDateStr,
                  toDate: toDateStr,
                  status: apiStatus,
                  pageLength: effectivePageLimit,
                  start: 0,
                ));
            _refreshFuture = future;
            final response = await future;
            if (_refreshFuture != future || !mounted) return;

            if (response['message']?['success'] == true) {
              final List<dynamic> invoices =
                  (response['message']?['message'] as List?) ?? [];

              // Check if we have more orders
              if (invoices.length < effectivePageLimit) {
                _hasMoreOrders = false;
              }

              List<Map<String, dynamic>> processedOrders = invoices
                  .map((invoice) {
                    try {
                      final items =
                          (invoice['items'] as List? ?? []).map((item) {
                        return {
                          'name':
                              item['item_name']?.toString() ?? 'Unknown Item',
                          'price': (item['rate'] as num?)?.toDouble() ?? 0.0,
                          'quantity': (item['qty'] as num?)?.toDouble() ?? 1.0,
                          'item_code': item['item_code']?.toString() ?? '',
                          'options': item['options'] ?? {},
                          'option_text': item['option_text'] ?? '',
                          'custom_serve_later': item['custom_serve_later'],
                          'custom_item_remarks':
                              item['custom_item_remarks']?.toString() ?? '',
                          'custom_variant_info':
                              item['custom_variant_info']?.toString() ?? '',
                          'discount_amount':
                              (item['discount_amount'] as num?)?.toDouble() ??
                                  0.0,
                          'image': (item['image'])
                        };
                      }).toList();

                      Map<String, dynamic>? taxBreakdown;
                      final taxes = invoice['taxes'] as List?;
                      if (taxes != null && taxes.isNotEmpty) {
                        taxBreakdown = {
                          'rate': (taxes[0]['rate'] as num?)?.toDouble() ?? 0.0,
                          'amount':
                              (taxes[0]['amount'] as num?)?.toDouble() ?? 0.0,
                          'description':
                              taxes[0]['account_head']?.toString() ?? 'Tax',
                        };
                      }

                      DateTime? parseDate(String? dateString) {
                        try {
                          return dateString != null
                              ? DateTime.parse(dateString)
                              : null;
                        } catch (_) {
                          return null;
                        }
                      }

                      // Extract payment method info
                      final payments = invoice['payments'] as List? ?? [];
                      String? m1Value;
                      if (payments.isNotEmpty) {
                        m1Value =
                            payments[0]['custom_fiuu_m1_value']?.toString();
                      }

                      return {
                        'orderId': invoice['name']?.toString() ?? 'Unknown',
                        'invoiceNumber':
                            invoice['name']?.toString() ?? 'Unknown',
                        'status': invoice['status']?.toString() ?? 'Draft',
                        'orderType':
                            invoice['custom_order_channel']?.toString() ?? '',
                        'tableNumber': (invoice['custom_table'] ?? ''),
                        'items': items,
                        'subtotal':
                            (invoice['rounded_total'] as num?)?.toDouble() ??
                                0.0,
                        'tax': taxBreakdown?['amount'] ?? 0.0,
                        'total':
                            (invoice['rounded_total'] as num?)?.toDouble() ??
                                0.0,
                        'entryTime':
                            parseDate(invoice['modified']?.toString()) ??
                                DateTime.now(),
                        'paidTime': invoice['status']?.toString() == 'Paid'
                            ? parseDate(invoice['modified']?.toString())
                            : null,
                        'isPaid': invoice['status']?.toString() == 'Paid' ||
                            invoice['status']?.toString() == 'Consolidated',
                        'paymentMethod': payments.isNotEmpty == true
                            ? payments[0]['mode_of_payment']?.toString() ??
                                'Cash'
                            : 'Cash',
                        'm1value': m1Value,
                        'customerName':
                            invoice['customer_name']?.toString() ?? 'Guest',
                        'remarks': invoice['remarks']?.toString() ?? '',
                        'custom_item_remarks':
                            invoice['custom_item_remarks']?.toString() ?? 'N/A',
                        'taxBreakdown': taxBreakdown,
                        'paidAmount':
                            (invoice['paid_amount'] as num?)?.toDouble() ?? 0.0,
                        'changeAmount':
                            (invoice['change_amount'] as num?)?.toDouble() ??
                                0.0,
                        'base_rounding_adjustment':
                            (invoice['base_rounding_adjustment'] as num?)
                                    ?.toDouble() ??
                                0.0,
                        "pos_invoice_number":
                            invoice['custom_fiuu_invoice_number']?.toString() ??
                                '000000',
                        'total_taxes_and_charges':
                            (invoice['total_taxes_and_charges'] as num?)
                                    ?.toDouble() ??
                                0.0,
                        'discount_amount':
                            (invoice['discount_amount'] as num?)?.toDouble(),
                        'user_voucher_code': (invoice['user_voucher_code']),
                        'custom_is_refund': (invoice['custom_is_refund'] ?? 0)
                      };
                    } catch (e) {
                      print('Error processing invoice ${invoice['name']}: $e');
                      return null;
                    }
                  })
                  .where((order) => order != null)
                  .cast<Map<String, dynamic>>()
                  .toList();

              // Sort orders: All orders by timestamp
              processedOrders.sort((a, b) {
                final idA = a['entryTime'] as DateTime;
                final idB = b['entryTime'] as DateTime;
                return idB.compareTo(idA); // Descending order
              });

              setState(() {
                activeOrders = processedOrders;
                _currentPage = 0;
              });

              print('Successfully mapped ${activeOrders.length} orders');
            }
          } on SessionTimeoutException {
            await ref.read(authProvider.notifier).logout();
          }
        },
      );
    } catch (e) {
      print('Error refreshing orders: $e');
    } finally {
      if (mounted) {
        setState(() => _isOrdersLoading = false);
      }
    }
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(Duration(days: 0)),
      currentDate: DateTime.now(),
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : null,
      initialEntryMode: DatePickerEntryMode.calendar,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Color(0xFFE732A0),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _fromDate = picked.start;
        _toDate = picked.end;
        _useDateRange = true;
      });

      Future.delayed(Duration(milliseconds: 100), () {
        _refreshOrders();
      });
    }
  }

  void _clearDateRange() {
    setState(() {
      _fromDate = null;
      _toDate = null;
      _useDateRange = false;
      _selectedDate = DateTime.now(); // Reset to today
    });

    // Refresh orders to show Pay Later with all dates
    Future.delayed(Duration(milliseconds: 100), () {
      _refreshOrders();
    });
  }

  List<Widget> _getScreensWithOrders() {
    final authState = ref.read(authProvider);

    return authState.when(
      initial: () => [
        const Center(child: CircularProgressIndicator()),
      ],
      unauthenticated: () {
        if (!_isLoggingOut) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            showDialog(
                context: context,
                builder: (context) => AlertDialog(
                      title: const Text('Session Timeout'),
                      content: const Text(
                          'Your session has expired. Please login again.'),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop(); // Close the dialog
                            // Navigate to LoginScreen and remove all previous routes
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => LoginPage()),
                              (Route<dynamic> route) => false,
                            );
                          },
                          child: const Text('OK'),
                        ),
                      ],
                    ));
          });
        }
        return [
          const Scaffold(body: Center(child: CircularProgressIndicator()))
        ];
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
        final hasKitchenStations = _hasKitchenStations();

        if (tier.toLowerCase() != 'tier 3') {
          return [
            FutureBuilder(
              future: _getDefaultTable(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final defaultTable = snapshot.data;
                return HomeScreen(
                  tableNumber: defaultTable != null
                      ? defaultTable['title'] ?? 'Take Away'
                      : 'Take Away',
                  existingOrder: null,
                  isTier1: true,
                  isDefaultTable: true, // NEW
                );
              },
            ),
            OrdersScreen(
              orders: activeOrders,
              isLoading: _isOrdersLoading,
              onOrderPaid: (order) {
                handleOrderPaid(order);
                setState(() => _isOrdersLoading = true);
                Future.delayed(Duration(seconds: 1), () {
                  if (mounted) {
                    setState(() => _isOrdersLoading = false);
                  }
                });
              },
              onEditOrder: _handleEditOrder,
              onRefresh: () async {
                await _refreshOrders();
              },
              selectedDate: _selectedDate,
              pageLimit: 30,
              onDateChanged: (newDate) {
                setState(() {
                  _selectedDate = newDate;
                  _useDateRange = false;
                  _currentPage = 0;
                  _hasMoreOrders = true;
                });
                Future.delayed(Duration(milliseconds: 100), () {
                  _refreshOrders();
                });
              },
              // Pass filter callbacks to OrdersScreen
              onFilterStatusChanged: (newStatus) {
                setState(() {
                  _filterStatus = newStatus;
                  _currentPage = 0; // Reset pagination when filter changes
                  _hasMoreOrders = true;
                });
                Future.delayed(Duration(milliseconds: 100), () {
                  _refreshOrders();
                });
              },
              onFilterOrderTypeChanged: (newOrderType) {
                setState(() {
                  _filterOrderType = newOrderType;
                  _currentPage = 0; // Reset pagination when filter changes
                  _hasMoreOrders = true;
                });
                Future.delayed(Duration(milliseconds: 100), () {
                  _refreshOrders();
                });
              },
              // Pass current filter values
              currentFilterStatus: _filterStatus,
              currentFilterOrderType: _filterOrderType,
              onDateRangeSelected: _selectDateRange,
              onDateRangeCleared: _clearDateRange,
              useDateRange: _useDateRange,
              fromDate: _fromDate,
              toDate: _toDate,
            ),
            DashboardScreen(),
            if (hasKitchenStations)
              KitchenScreen(
                key: ValueKey(
                    'kitchen_${DateTime.now().millisecondsSinceEpoch}'), // Force rebuild
              ),
            SettingsScreen(key: settingsScreenKey),
          ];
        } else {
          return [
            FutureBuilder(
              future: _getDefaultTable(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final defaultTable = snapshot.data;
                return HomeScreen(
                  tableNumber: defaultTable == null
                      ? 'Take Away'
                      : defaultTable['title'] ?? 'Take Away',
                  existingOrder: null,
                  isTier1: false,
                  isDefaultTable: false, // NEW
                );
              },
            ),
            TableScreen(
              tablesWithSubmittedOrders: tablesWithSubmittedOrders,
              onOrderSubmitted: (order) {
                addNewOrder(order);
                _refreshOrders();
              },
              onOrderPaid: markOrderAsPaid,
              activeOrders: activeOrders,
            ),
            OrdersScreen(
                orders: activeOrders,
                isLoading: _isOrdersLoading,
                onOrderPaid: (order) {
                  handleOrderPaid(order);
                  setState(() => _isOrdersLoading = true);
                  Future.delayed(Duration(seconds: 1), () {
                    if (mounted) {
                      setState(() => _isOrdersLoading = false);
                    }
                  });
                },
                onEditOrder: _handleEditOrder,
                onRefresh: () async {
                  await _refreshOrders();
                },
                selectedDate: _selectedDate,
                pageLimit: 30,
                onDateChanged: (newDate) {
                  setState(() {
                    _selectedDate = newDate;
                    _useDateRange = false; // Switch to single date mode
                  });
                  Future.delayed(Duration(milliseconds: 100), () {
                    _refreshOrders();
                  });
                },
                // Pass filter callbacks to OrdersScreen
                onFilterStatusChanged: (newStatus) {
                  setState(() => _filterStatus = newStatus);
                  Future.delayed(Duration(milliseconds: 100), () {
                    _refreshOrders();
                  });
                },
                onFilterOrderTypeChanged: (newOrderType) {
                  setState(() => _filterOrderType = newOrderType);
                  Future.delayed(Duration(milliseconds: 100), () {
                    _refreshOrders();
                  });
                },
                // Pass current filter values
                currentFilterStatus: _filterStatus,
                currentFilterOrderType: _filterOrderType,
                // Pass date range methods
                onDateRangeSelected: _selectDateRange,
                onDateRangeCleared: _clearDateRange,
                useDateRange: _useDateRange,
                fromDate: _fromDate,
                toDate: _toDate),
            DashboardScreen(),
            if (hasKitchenStations)
              KitchenScreen(
                key: ValueKey(
                    'kitchen_${DateTime.now().millisecondsSinceEpoch}'), // Force rebuild
              ),
            const GrabScreen(), // Add Grab screen
            SettingsScreen(key: settingsScreenKey),
          ];
        }
      },
    );
  }

  Widget _buildNavigationSidebar() {
    final authState = ref.read(authProvider);

    return authState.when(
      initial: () => const Center(child: CircularProgressIndicator()),
      unauthenticated: () {
        if (!_isLoggingOut) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Session Timeout'),
                content:
                    const Text('Your session has expired. Please login again.'),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (context) => LoginPage()),
                        (Route<dynamic> route) => false,
                      );
                    },
                    child: const Text('OK'),
                  ),
                ],
              ),
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
        final hasKitchenStations = _hasKitchenStations();

        return Container(
          width: 100,
          color: Colors.white,
          child: Column(
            children: [
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  setState(() {
                    _selectedTabIndex = 0;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: Image.asset(
                    'assets/logo-shiokpos.png',
                    width: 60,
                    height: 60,
                  ),
                ),
              ),
              // Only show TableScreen for tier 3 users
              if (tier.toLowerCase() == 'tier 3') ...[
                _buildNavItem(1, 'assets/img-sidebar-table.png', 'Tables'),
              ],
              // Orders screen index depends on tier
              _buildNavItem(
                tier.toLowerCase() != 'tier 3' ? 1 : 2,
                'assets/img-sidebar-orders.png',
                'Orders',
              ),
              _buildNavItem(
                tier.toLowerCase() != 'tier 3' ? 2 : 3,
                'assets/img-sidebar-dashboard.png',
                'Dashboard',
              ),
              if (hasKitchenStations)
                _buildNavItem(
                  tier.toLowerCase() != 'tier 3' ? 3 : 4,
                  'assets/img-sidebar-kitchen.png',
                  'Fulfilment',
                  null,
                  _pendingGrabOrdersCount, // Pass badge count
                ),
              // Grab screen - Tier 3 only
              if (tier.toLowerCase() == 'tier 3')
                _buildNavItem(
                  hasKitchenStations ? 5 : 4,
                  'assets/icon-grab.png',
                  'Grab',
                  null,
                  0,
                  true, // preserveIconColor = true for Grab icon
                ),
              // Settings (updated index)
              _buildNavItem(
                hasKitchenStations
                    ? (tier.toLowerCase() != 'tier 3' ? 4 : (tier.toLowerCase() == 'tier 3' ? 6 : 5))
                    : (tier.toLowerCase() != 'tier 3' ? 3 : (tier.toLowerCase() == 'tier 3' ? 5 : 4)),
                'assets/img-sidebar-settings.png',
                'Settings',
              ),
              const Spacer(),
              _buildNavItem(
                  -1, 'assets/img-sidebar-logout.png', 'Logout', _logout),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavItem(int index, String imagePath, String label,
      [VoidCallback? action, int badgeCount = 0, bool preserveIconColor = false] // Add preserveIconColor parameter
      ) {
    final bool isSelected = index == _selectedTabIndex;
    return GestureDetector(
      onTap: action ??
          () async {
            if (index == -1) {
              // Logout
              ref.read(authProvider.notifier).logout();
              Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
            } else {
              // Check if this is the Orders screen (index 2 for tier2, index 1 for tier1)
              final authState = ref.read(authProvider);
              bool isOrdersScreen = false;

              authState.whenOrNull(
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
                  mechantId,
                  printMerchantReceiptCopy,
                  enableFiuu,
                  cashDrawerPinNeeded,
                  cashDrawerPin,
                ) {
                  if (tier.toLowerCase() != 'tier 3') {
                    isOrdersScreen = index == 1; // Orders is index 1 for tier1
                  } else {
                    isOrdersScreen = index == 2; // Orders is index 2 for tier2
                  }
                },
              );

              if (isOrdersScreen) {
                setState(() {
                  _filterStatus = 'All';
                });
                // Refresh orders with the new filters
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _refreshOrders();
                });
              }

              setState(() => _selectedTabIndex = index);
            }
          },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
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
                    // Only apply color if preserveIconColor is false
                    color: preserveIconColor 
                        ? null 
                        : (isSelected ? Colors.pink : const Color(0xFF555555)),
                    width: index == 1 ? 50 : 40,
                    height: index == 1 ? 50 : 40,
                  ),
                ),
                // Badge for pending orders
                if (badgeCount > 0)
                  Positioned(
                    top: -4,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.3),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      child: Center(
                        child: Text(
                          badgeCount > 99 ? '99+' : badgeCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(label,
                style: TextStyle(
                    color: isSelected ? Colors.pink : const Color(0xFF555555),
                    fontSize: 10)),
          ],
        ),
      ),
    );
  }

  void handleOrderPaid(Map<String, dynamic> paidOrder) {
    print('Handling paid order: ${jsonEncode({
          ...paidOrder,
          'paidTime': paidOrder['paidTime'] is DateTime
              ? paidOrder['paidTime'].toIso8601String()
              : paidOrder['paidTime']?.toString(),
          'entryTime': paidOrder['entryTime'] is DateTime
              ? paidOrder['entryTime'].toIso8601String()
              : paidOrder['entryTime']?.toString(),
        })}');

    setState(() {
      final index = activeOrders.indexWhere((o) =>
          o['orderId'] == paidOrder['orderId'] ||
          o['invoiceNumber'] == paidOrder['invoiceNumber']);

      if (index != -1) {
        activeOrders[index] = {
          ...activeOrders[index],
          ...paidOrder,
          'isPaid': true,
          'status': 'Paid',
          'paidTime': paidOrder['paidTime'] is DateTime
              ? paidOrder['paidTime'].toIso8601String()
              : paidOrder['paidTime']?.toString(),
          // Preserve change amount if it exists
          if (paidOrder['changeAmount'] != null)
            'changeAmount': paidOrder['changeAmount'],
          // Use actual paid amount for cash payments
          if (paidOrder['paymentMethod'] == 'Cash' &&
              paidOrder['paidAmount'] != null)
            'paidAmount': paidOrder['paidAmount'],
        };
        tablesWithSubmittedOrders.remove(paidOrder['tableNumber']);
      } else {
        activeOrders.add({
          ...paidOrder,
          'isPaid': true,
          'status': 'Paid',
          'paidTime': paidOrder['paidTime'] is DateTime
              ? paidOrder['paidTime'].toIso8601String()
              : paidOrder['paidTime']?.toString(),
          // Preserve change amount if it exists
          if (paidOrder['changeAmount'] != null)
            'changeAmount': paidOrder['changeAmount'],
          // Use actual paid amount for cash payments
          if (paidOrder['paymentMethod'] == 'Cash')
            'paidAmount': paidOrder['paidAmount'],
        });
      }
    });

    if (_selectedTabIndex == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshOrders();
      });
    }
  }

  void _handleEditOrder(Map<String, dynamic> order) {
    setState(() {
      final index = activeOrders
          .indexWhere((o) => o['tableNumber'] == order['tableNumber']);
      if (index != -1) {
        activeOrders[index] = order;
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

  void addNewOrder(Map<String, dynamic> order) {
    try {
      setState(() {
        activeOrders.removeWhere((o) =>
            o['tableNumber'] == order['tableNumber'] &&
            !(o['isPaid'] ?? false));

        final items = order['items'] is List ? List.from(order['items']) : [];

        final newOrder = {
          'orderId': order['invoice']?['name'] ?? 'Unknown',
          'invoiceNumber': order['invoice']?['name'] ?? 'Unknown',
          'tableNumber': order['tableNumber'],
          'items': items,
          'status': order['invoice']?['status'] ?? 'Draft',
          'orderType': order['invoice']?['custom_order_channel'] ?? 'Dine in',
          'subtotal': order['invoice']?['net_total']?.toDouble() ?? 0.0,
          'tax':
              order['invoice']?['total_taxes_and_charges']?.toDouble() ?? 0.0,
          'total': order['invoice']?['grand_total']?.toDouble() ?? 0.0,
          'entryTime': DateTime.now(),
          'isPaid': false,
        };

        activeOrders.add(newOrder);
        tablesWithSubmittedOrders.add(order['tableNumber']);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding order: $e')),
      );
    }
  }

  void updateOrder(Map<String, dynamic> updatedOrder) {
    setState(() {
      final index = activeOrders.indexWhere((o) =>
          o['tableNumber'] == updatedOrder['tableNumber'] && !o['isPaid']);

      if (index != -1) {
        activeOrders[index] = {
          ...activeOrders[index],
          'items': List<Map<String, dynamic>>.from(updatedOrder['items'] ?? []),
          'subtotal': updatedOrder['invoice']?['net_total']?.toDouble() ?? 0.0,
          'tax':
              updatedOrder['invoice']?['total_taxes_and_charges']?.toDouble() ??
                  0.0,
          'total': updatedOrder['invoice']?['grand_total']?.toDouble() ?? 0.0,
          'status': updatedOrder['invoice']?['status'] ?? 'Draft',
        };
      }
    });
  }

  void markOrderAsPaid(int tableNumber) {
    setState(() {
      // Mark as paid
      final index = activeOrders
          .indexWhere((order) => order['tableNumber'] == tableNumber);
      if (index != -1) {
        activeOrders[index]['isPaid'] = true;
        activeOrders[index]['status'] = 'Paid';
      }
      // Update table status
      tablesWithSubmittedOrders.remove(tableNumber);
    });
  }

  void selectOrdersTab() {
    setState(() {
      _selectedTabIndex = 2; // Orders screen index
    });
  }

  void setSelectedTabIndex(int index) {
    setState(() {
      _selectedTabIndex = index;
    });
  }

  Future<Map<String, dynamic>?> _getDefaultTable() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final branch = prefs.getString('branch');
      if (branch == null) return null;

      final response = await safeExecuteAPICall(
          () => PosService().getFloorsAndTables(branch));
      if (response['success'] == true) {
        final floorsData = response['message'];

        if (floorsData is List) {
          // First, try to find a table with is_default = 1
          for (var floor in floorsData) {
            final tables = floor['tables'];

            // Handle both list and map cases
            if (tables is List) {
              for (var table in tables) {
                if (table['is_default'] == 1) {
                  return table; // Found default table
                }
              }
            } else if (tables is Map<String, dynamic>) {
              if (tables['is_default'] == 1) {
                return tables; // Found default table
              }
            }
          }

          // If no default table found but we need one, take the first takeaway table
          for (var floor in floorsData) {
            final tables = floor['tables'];

            if (tables is List) {
              for (var table in tables) {
                if (table['title']
                        ?.toString()
                        .toLowerCase()
                        .contains('take away') ??
                    false) {
                  return table;
                }
              }
            }
          }

          // Last resort: return first table found
          for (var floor in floorsData) {
            final tables = floor['tables'];

            if (tables is List && tables.isNotEmpty) {
              return tables[0];
            } else if (tables is Map<String, dynamic>) {
              return tables;
            }
          }
        }
      }

      return null; // No tables found at all
    } catch (e, stackTrace) {
      print('Error getting default table: $e\n$stackTrace');
      return null;
    }
  }

  Future<bool> showOrderDiscardConfirmationDialog(BuildContext context) async {
    return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                  title: const Text('Discard Order?'),
                  content: const Text(
                      'You have items in your current order. Navigating away will delete it. Do you want to continue?'),
                  actions: [
                    TextButton(
                      child: const Text('Cancel'),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                    ElevatedButton(
                      child: const Text('Yes, Discard'),
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ],
                )) ??
        false;
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