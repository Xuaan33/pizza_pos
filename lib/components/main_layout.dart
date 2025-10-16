import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiok_pos_android_app/components/customer_display_controller.dart';
import 'package:shiok_pos_android_app/screens/home_screen.dart';
import 'package:shiok_pos_android_app/screens/login_screen.dart';
import 'package:shiok_pos_android_app/screens/table_screen.dart';
import 'package:shiok_pos_android_app/screens/orders_screen.dart';
import 'package:shiok_pos_android_app/screens/dashboard_screen.dart';
import 'package:shiok_pos_android_app/screens/settings_screen.dart';
import 'package:shiok_pos_android_app/screens/delivery_screen.dart';
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
  List<Map<String, dynamic>> activeOrders = [];
  Set<int> tablesWithSubmittedOrders = {};
  bool _isOrdersLoading = false;
  bool _isLoggingOut = false;
  bool _customerScreenShown = false;
  Future<void>? _refreshFuture;
  DateTime _selectedDate = DateTime.now();
  int _pageLimit = 30;
  String _filterStatus = 'Pay Later'; // 'All', 'Pay Later', 'Paid', 'Cancelled'
  String _filterOrderType = 'All'; // 'All', 'Dine in', 'Takeaway', 'Delivery'
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _useDateRange = false;

  final List<int> _limitOptions = [30, 50, 100];

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
  void dispose() {
    _refreshFuture = null; // break reference
    super.dispose();
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

    setState(() => _isOrdersLoading = true);

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
        ) async {
          try {
            String? fromDateStr;
            String? toDateStr;

            if (_filterStatus == 'Pay Later' || forceAllForPayLater) {
              fromDateStr = null;
              toDateStr = null;
            } else {
              if (_useDateRange && _fromDate != null && _toDate != null) {
                fromDateStr = DateFormat('yyyy-MM-dd').format(_fromDate!);
                toDateStr = DateFormat('yyyy-MM-dd').format(_toDate!);
              } else {
                fromDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
                toDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
              }
            }

            String? apiStatus;
            if (_filterStatus == 'Pay Later') {
              apiStatus = 'Draft';
            } else if (_filterStatus == 'Paid') {
              apiStatus = null;
            } else if (_filterStatus == 'Cancelled') {
              apiStatus = 'Cancelled';
            }

            final effectivePageLimit = _filterStatus == 'Pay Later' ? 1000 : _pageLimit;

            final future = PosService().getOrders(
              posProfile: posProfile,
              fromDate: fromDateStr,
              toDate: toDateStr,
              status: apiStatus,
              pageLength: effectivePageLimit,
              start: 0,
            );
            _refreshFuture = future;
            final response = await future;
            if (_refreshFuture != future || !mounted) return;

            if (response['message']?['success'] == true) {
              final List<dynamic> invoices =
                  (response['message']?['message'] as List?) ?? [];

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
                      };
                    } catch (e) {
                      print('Error processing invoice ${invoice['name']}: $e');
                      return null;
                    }
                  })
                  .where((order) => order != null)
                  .cast<Map<String, dynamic>>()
                  .toList();

              // Sort orders: Pay Later orders by timestamp, others by order ID
              processedOrders.sort((a, b) {
                final isPayLaterA =
                    a['status']?.toString().toLowerCase() == 'draft';
                final isPayLaterB =
                    b['status']?.toString().toLowerCase() == 'draft';

                if (isPayLaterA && isPayLaterB) {
                  // Both are Pay Later - sort by entryTime descending (newest first)
                  final timeA = a['entryTime'] as DateTime;
                  final timeB = b['entryTime'] as DateTime;
                  return timeB.compareTo(timeA);
                } else if (isPayLaterA) {
                  // Only A is Pay Later - A comes first
                  return -1;
                } else if (isPayLaterB) {
                  // Only B is Pay Later - B comes first
                  return 1;
                } else {
                  // Both are not Pay Later - sort by order ID
                  final idA = a['orderId']?.toString() ?? '';
                  final idB = b['orderId']?.toString() ?? '';
                  return idB.compareTo(idA); // Descending order
                }
              });

              setState(() {
                activeOrders = processedOrders;
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

  int _extractTableNumber(String? tableFullName) {
    if (tableFullName == null || tableFullName.isEmpty) return 0;

    try {
      // Extract from formats like "MK-Floor 1-Table 1" → 1
      final RegExpMatch? match =
          RegExp(r'Table (\d+)$').firstMatch(tableFullName);
      return match != null ? int.tryParse(match.group(1) ?? '0') ?? 0 : 0;
    } catch (e) {
      print('Error parsing table number from $tableFullName: $e');
      return 0;
    }
  }

  Map<String, dynamic> _mapApiInvoiceToOrder(Map<String, dynamic> invoice) {
    final items = ((invoice['items'] as List?) ?? []).map((item) {
      // Always include the raw custom_variant_info exactly as received
      dynamic customVariantInfo = item['custom_variant_info'];

      // Parse options if variant info exists
      Map<String, dynamic> options = {};
      String optionText = '';

      // Parse the variant info if it exists
      if (customVariantInfo != null) {
        try {
          // Handle both string (JSON) and direct list formats
          dynamic parsed = customVariantInfo is String
              ? jsonDecode(customVariantInfo)
              : customVariantInfo;

          if (parsed is List && parsed.isNotEmpty) {
            // New format - list of direct option maps
            if (parsed[0] is Map) {
              options = Map<String, dynamic>.from(parsed[0]);
              optionText =
                  options.entries.map((e) => '${e.key}: ${e.value}').join(', ');
            }
          }
        } catch (e) {
          debugPrint('Variant parsing error: $e');
        }
      }

      return {
        'item_code': item['item_code'] ?? '',
        'name': item['item_name'] ?? item['name'] ?? '',
        'price': (item['price_list_rate'] ?? item['rate'] ?? 0).toDouble(),
        'image': item['image'] ?? 'assets/pizza.png',
        'quantity': (item['qty'] ?? item['quantity'] ?? 1).toDouble(),
        'options': options,
        'option_text': optionText,
        'custom_serve_later': item['custom_serve_later'] == 1,
        'custom_item_remarks': item['custom_item_remarks'] ?? '',
        'custom_variant_info': customVariantInfo, // Include exactly as received
        'discount_amount': (item['discount_amount']).toDouble(),
      };
    }).toList();

    return {
      'orderId': invoice['name']?.toString() ?? 'Unknown',
      'invoiceNumber': invoice['name']?.toString() ?? 'Unknown',
      'status': invoice['status']?.toString() ?? 'Draft',
      'orderType': invoice['custom_order_channel']?.toString() ?? 'Dine in',
      'tableNumber': _extractTableNumber(invoice['custom_table']),
      'items': items,
      'subtotal': (invoice['net_total'] as num?)?.toDouble() ?? 0.0,
      'tax': (invoice['total_taxes_and_charges'] as num?)?.toDouble() ?? 0.0,
      'total': (invoice['grand_total'] as num?)?.toDouble() ?? 0.0,
      'total_taxes_and_charges':
          (invoice['total_taxes_and_charges'] as num?)?.toDouble() ?? 0.0,
      'discount_amount':
          (invoice['discount_amount'] as num?)?.toDouble() ?? 0.0,
      'user_voucher_code': (invoice['user_voucher_code']),
      'entryTime': DateTime.tryParse(invoice['modified']?.toString() ?? '') ??
          DateTime.now(),
      'paidTime': invoice['status']?.toString() == 'Paid'
          ? DateTime.tryParse(invoice['modified']?.toString() ?? '')
          : null,
      'isPaid': invoice['status']?.toString() == 'Paid',
      'paymentMethod':
          invoice['payments'][0]['mode_of_payment']?.toString() ?? 'Cash',
      'customerName': invoice['customer_name']?.toString() ?? 'Guest',
      'custom_item_remarks':
          invoice['custom_item_remarks']?.toString() ?? 'N/A',
      'taxBreakdown': _parseTaxBreakdown(invoice),
    };
  }

  Map<String, dynamic>? _parseTaxBreakdown(Map<String, dynamic> invoice) {
    try {
      final taxes = invoice['taxes'] as List?;
      if (taxes == null || taxes.isEmpty) return null;

      final tax = taxes.first;
      return {
        'rate': (tax['rate'] ?? 0).toDouble(),
        'amount': (tax['amount'] ?? 0).toDouble(),
        'description': tax['account_head'] ?? 'Tax',
      };
    } catch (e) {
      return null;
    }
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
      ) {
        if (tier.toLowerCase() == 'tier1') {
          return [
            FutureBuilder(
              future: _getDefaultTable(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final defaultTable = snapshot.data;
                print('${defaultTable}');

                return HomeScreen(
                  tableNumber: defaultTable != null
                      ? defaultTable['name'] ??
                          'adsf 1' // Use the full table name directly
                      : 'zxcv 1', // Fallback to string
                  existingOrder: null,
                  isTier1: true,
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
              pageLimit: _pageLimit,
              onDateChanged: (newDate) {
                setState(() {
                  _selectedDate = newDate;
                  _useDateRange = false; // Switch to single date mode
                });
                Future.delayed(Duration(milliseconds: 100), () {
                  _refreshOrders();
                });
              },
              onLimitChanged: (newLimit) {
                setState(() => _pageLimit = newLimit);
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
              toDate: _toDate,
              limitOptions: _limitOptions,
            ),
            DashboardScreen(),
            SettingsScreen(),
          ];
        } else {
          return [
            TableScreen(
              tablesWithSubmittedOrders: tablesWithSubmittedOrders,
              onOrderSubmitted: (order) {
                addNewOrder(order);
                _refreshOrders();
              },
              onOrderPaid: markOrderAsPaid,
              activeOrders: activeOrders,
            ),
            DeliveryScreen(),
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
              pageLimit: _pageLimit,
              onDateChanged: (newDate) {
                setState(() {
                  _selectedDate = newDate;
                  _useDateRange = false; // Switch to single date mode
                });
                Future.delayed(Duration(milliseconds: 100), () {
                  _refreshOrders();
                });
              },
              onLimitChanged: (newLimit) {
                setState(() => _pageLimit = newLimit);
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
              toDate: _toDate,
              limitOptions: _limitOptions,
            ),
            DashboardScreen(),
            SettingsScreen(),
          ];
        }
      },
    );
  }

  Future<List<Map<String, dynamic>>> _fetchOrders() async {
    // Simulate network delay
    await Future.delayed(Duration(milliseconds: 500));
    return activeOrders.where((o) => !o['isPaid']).toList();
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
      ) {
        return Container(
          width: 100,
          color: Colors.white,
          child: Column(
            children: [
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedTabIndex = 0; // Go to Home/Table screen
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
              if (tier.toLowerCase() == 'tier2') ...[
                _buildNavItem(0, 'assets/img-sidebar-table.png', 'Tables'),
                _buildNavItem(1, 'assets/img-sidebar-delivery.png', 'Delivery'),
              ],
              _buildNavItem(tier.toLowerCase() == 'tier1' ? 1 : 2,
                  'assets/img-sidebar-orders.png', 'Orders'),
              _buildNavItem(tier.toLowerCase() == 'tier1' ? 2 : 3,
                  'assets/img-sidebar-dashboard.png', 'Dashboard'),
              _buildNavItem(tier.toLowerCase() == 'tier1' ? 3 : 4,
                  'assets/img-sidebar-settings.png', 'Settings'),
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
      [VoidCallback? action]) {
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
                ) {
                  if (tier.toLowerCase() == 'tier1') {
                    isOrdersScreen = index == 1; // Orders is index 1 for tier1
                  } else {
                    isOrdersScreen = index == 2; // Orders is index 2 for tier2
                  }
                },
              );

              final previousLimit = _pageLimit;

              // If this is the Orders screen, set filter to "Pay Later" and limit to 1000
              if (isOrdersScreen) {
                setState(() {
                  _filterStatus = 'Pay Later';
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
                color: isSelected ? Colors.pink : const Color(0xFF555555),
                width: index == 1 ? 50 : 40,
                height: index == 1 ? 50 : 40,
              ),
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
          ...activeOrders[index] as Map<String, dynamic>,
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

      final response = await PosService().getFloorsAndTables(branch);
      if (response['success'] == true) {
        final floorsData = response['message'];

        if (floorsData is List) {
          for (var floor in floorsData) {
            final floorName = floor['floor'];
            final tables = floor['tables'];

            // Case 1: Single-table in a Map (e.g., "DEFAULT" floor)
            if (tables is Map<String, dynamic>) {
              if (floorName == 'DEFAULT' && tables['is_default'] == 1) {
                return tables;
              }
            }

            // Case 2: Multi-table List
            else if (tables is List) {
              for (var table in tables) {
                if (table['is_default'] == 1) {
                  return table;
                }
              }
            }
          }
        }
      }

      return null; // No default table found
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
