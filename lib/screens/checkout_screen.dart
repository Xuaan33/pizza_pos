import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:shiok_pos_android_app/components/customer_display_controller.dart';
import 'package:shiok_pos_android_app/components/image_url_helper.dart';
import 'package:shiok_pos_android_app/components/no_stretch_scroll_behavior.dart';
import 'package:shiok_pos_android_app/components/pos_hex_generator.dart';
import 'package:shiok_pos_android_app/components/receipt_printer.dart';
import 'package:shiok_pos_android_app/components/split_order_payment_dialog.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/screens/home_screen.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;
  final Set<int> tablesWithSubmittedOrders;
  final Function(Map<String, dynamic>) onOrderSubmitted;
  final Function(int) onOrderPaid;
  final List<Map<String, dynamic>> activeOrders;

  const CheckoutScreen({
    Key? key,
    required this.order,
    required this.tablesWithSubmittedOrders,
    required this.onOrderSubmitted,
    required this.onOrderPaid,
    required this.activeOrders,
  }) : super(key: key);

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String _selectedPaymentMethod = '';
  List<Map<String, dynamic>> _paymentMethods = [];
  bool _isLoadingPaymentMethods = true;
  double _totalRevenue = 0.0;
  double _totalUnpaidOrders = 0.0;
  int _totalTablesFree = 0;
  double _amountGiven = 0.0;
  bool _isProcessingPayment = false;
  bool _isDisposed = false;
  String _voucherCode = '';
  double _discountAmount = 0.0;
  double total_taxes_and_charges = 0.0;
  bool _isValidatingVoucher = false;
  bool _isEditing = false;
  Map<String, int> _itemStockQuantities = {};
  bool _isLoadingStock = false;
  List<List<Map<String, dynamic>>> _editHistory = [];
  List<Map<String, dynamic>> _editableItems = [];
  List<Map<String, dynamic>> _previousEditableItems = [];
  List<Map<String, dynamic>> _itemsToSplit = [];
  bool _isSplitting = false;
  bool _isProcessingSplit = false;
  Map<String, dynamic>? _splitOrder;
  TextEditingController _remarksController = TextEditingController();
  bool _isRemarksEditing = false;
  bool _isSavingRemarks = false;
  String _currentRemarks = '';
    String baseImageUrl = '';


  @override
  void dispose() {
    _isDisposed = true; // Mark as disposed
    // CustomerDisplayController.showDefaultDisplay();
    _remarksController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadBaseUrl();
    _loadPaymentMethods();
    _loadTodayInfo();
    _fetchOrderDetails();
    _checkStockForItems();
    // Initialize remarks
    _currentRemarks = widget.order['remarks'] ?? '';
    _remarksController.text = _currentRemarks;
  }

  Future<void> _loadBaseUrl() async {
    baseImageUrl = await ImageUrlHelper.getBaseImageUrl();
    setState(() {}); // Refresh UI
  }

  void _loadPaymentMethods() {
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
      ) {
        setState(() {
          _paymentMethods = paymentMethods.map((method) {
            return {
              'name': method['name'],
              'custom_payment_mode_image': method['custom_payment_mode_image'],
              'custom_fiuu_m1_value': method['custom_fiuu_m1_value'] ??
                  '01', // Default to '01' if not provided
            };
          }).toList();
          _isLoadingPaymentMethods = false;
        });
      },
    );
  }

  Future<void> _loadTodayInfo() async {
    try {
      final response = await PosService().getTodayInfo();

      if (response['success'] == true) {
        setState(() {
          // Ensure we handle both int and double values
          _totalRevenue = (response['data']['total_revenue'] is int
              ? (response['data']['total_revenue'] as int).toDouble()
              : (response['data']['total_revenue'] ?? 0).toDouble());

          _totalUnpaidOrders = (response['data']['total_unpaid_orders'] is int
              ? (response['data']['total_unpaid_orders'] as int).toDouble()
              : (response['data']['total_unpaid_orders'] ?? 0).toDouble());

          _totalTablesFree = (response['data']['total_table_free'] is double
              ? (response['data']['total_table_free'] as double).toInt()
              : (response['data']['total_table_free'] ?? 0));
        });
      }
    } catch (e) {
      if (!_isDisposed && mounted && ref.read(authProvider) is AsyncData) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load today info: $e')),
        );
      }
    }
  }

  Future<void> _fetchOrderDetails() async {
    try {
      final invoiceName = widget.order['invoiceNumber'];
      if (invoiceName == null) return;

      final response = await PosService().getOrders(
        posProfile: ref.read(authProvider).maybeWhen(
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
                  ) {
                    return posProfile;
                  },
                  orElse: () => null,
                ) ??
            '',
        search: invoiceName,
      );

      if (response['message']?['success'] == true) {
        final List<dynamic> invoices = response['message']?['message'] ?? [];
        if (invoices.isNotEmpty) {
          final invoice = invoices.first;
          final List<dynamic> serverItems = invoice['items'] ?? [];

          setState(() {
            // Update order details
            widget.order['grand_total'] =
                invoice['grand_total']?.toDouble() ?? 0.0;
            widget.order['base_rounding_adjustment'] =
                invoice['base_rounding_adjustment']?.toDouble() ?? 0.0;
            widget.order['rounded_total'] =
                invoice['rounded_total']?.toDouble() ?? 0.0;
            widget.order['discount_amount'] =
                (invoice['discount_amount'] as num?)?.toDouble() ?? 0.0;
            widget.order['coupon_code'] = invoice['coupon_code'];
            widget.order['custom_user_voucher'] =
                invoice['custom_user_voucher'];
            widget.order['taxes'] = invoice['taxes'];
            widget.order['total_taxes_and_charges'] =
                (invoice['total_taxes_and_charges'] as num?)?.toDouble() ?? 0.0;
            widget.order['total'] =
                (invoice['total'] as num?)?.toDouble() ?? 0.0;
            widget.order['remarks'] = invoice['remarks'];

            // Update local discount amount
            _discountAmount = widget.order['discount_amount'];
            total_taxes_and_charges = widget.order['total_taxes_and_charges'];

            // Update remarks
            _currentRemarks = widget.order['remarks'] ?? '';
            _remarksController.text = _currentRemarks;
            _isRemarksEditing = false;

            // Clear existing items and rebuild from server response
            widget.order['items'] = serverItems.map((serverItem) {
              // Find existing item to preserve UI state if needed
              final existingItem = orderItems.firstWhere(
                (item) => item['item_code'] == serverItem['item_code'],
                orElse: () => {},
              );

              return {
                ...existingItem,
                'item_code': serverItem['item_code'],
                'name': serverItem['item_name'] ?? existingItem['name'],
                'price': (serverItem['rate'] as num?)?.toDouble() ??
                    existingItem['price'],
                'quantity': (serverItem['qty'] as num?)?.toDouble() ??
                    existingItem['quantity'],
                'discount_amount':
                    (serverItem['discount_amount'] as num?)?.toDouble() ?? 0.0,
                'discount_percentage':
                    (serverItem['discount_percentage'] as num?)?.toDouble() ??
                        0.0,
                'custom_item_remarks': serverItem['custom_item_remarks'] ??
                    existingItem['custom_item_remarks'],
                'custom_serve_later': serverItem['custom_serve_later'] ??
                    existingItem['custom_serve_later'],
                'custom_variant_info': serverItem['custom_variant_info'] ??
                    existingItem['custom_variant_info'],
                'image': existingItem['image'], // Preserve image from original
              };
            }).toList();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Failed to fetch order details: $e',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    }
  }

  List<Map<String, dynamic>> get orderItems {
    return List<Map<String, dynamic>>.from(widget.order['items']);
  }

  // Add to _CheckoutScreenState class
  Future<void> _checkStockForItems() async {
    if (_isLoadingStock) return;

    setState(() => _isLoadingStock = true);

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
      ) async {
        try {
          final newStockQuantities = <String, int>{};

          // Call API once to get all stock data
          final response = await PosService().getStockBalanceSummary(
            posProfile: posProfile,
            isPosItem: 1,
            disable: 0,
          );

          if (response['success'] == true) {
            final message = response['message'];

            if (message is List) {
              // Create a map for quick lookup by item name
              final stockMap = <String, Map<String, dynamic>>{};

              for (var stockItem in message) {
                if (stockItem is Map<String, dynamic>) {
                  final itemName = stockItem['item']?.toString();
                  if (itemName != null) {
                    stockMap[itemName] = stockItem;
                  }
                }
              }

              // Map stock quantities to order items
              for (var item in orderItems) {
                final itemCode = item['item_code']?.toString();

                if (itemCode != null) {
                  // Try to find matching stock item by item_code
                  final stockItem = stockMap[itemCode];

                  if (stockItem != null) {
                    final qtyValue = stockItem['qty'];
                    int stockQty = 0;

                    if (qtyValue is num) {
                      stockQty = qtyValue.toInt();
                    } else if (qtyValue is String) {
                      stockQty = int.tryParse(qtyValue) ?? 0;
                    }

                    newStockQuantities[itemCode] = stockQty;
                  } else {
                    // Item not found in stock data
                    newStockQuantities[itemCode] = 0;
                  }
                }
              }
            } else {
              debugPrint(
                  'Stock API message is not a List: ${message.runtimeType}');
              // Set default values for all items
              for (var item in orderItems) {
                final itemCode = item['item_code']?.toString();
                if (itemCode != null) {
                  newStockQuantities[itemCode] = 999;
                }
              }
            }
          } else {
            debugPrint(
                'Stock API returned success=false: ${response['message']}');
            // Set default values for all items
            for (var item in orderItems) {
              final itemCode = item['item_code']?.toString();
              if (itemCode != null) {
                newStockQuantities[itemCode] = 999;
              }
            }
          }

          setState(() {
            _itemStockQuantities = newStockQuantities;
          });
        } catch (e, stackTrace) {
          debugPrint('Error checking stock: $e');
          debugPrint('Stack trace: $stackTrace');

          // Set default values for all items on error
          final newStockQuantities = <String, int>{};
          for (var item in orderItems) {
            final itemCode = item['item_code']?.toString();
            if (itemCode != null) {
              newStockQuantities[itemCode] = 999;
            }
          }

          setState(() {
            _itemStockQuantities = newStockQuantities;
          });
        } finally {
          setState(() => _isLoadingStock = false);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    return authState.when(
        initial: () => const Center(child: CircularProgressIndicator()),
        unauthenticated: () => const Center(child: Text('Unauthorized')),
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
        ) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            CustomerDisplayController.updateOrderDisplay(
              items: orderItems.map((item) {
                return {
                  'name': item['name'] ?? 'Unknown',
                  'price': (item['price'] is int)
                      ? (item['price'] as int).toDouble()
                      : item['price'] as double,
                  'quantity': (item['quantity'] is int)
                      ? item['quantity'] as int
                      : (item['quantity'] as double).toInt(),
                  'discount_amount': item['discount_amount'] ?? 0.0,
                  'custom_serve_later': item['custom_serve_later'] ?? false,
                  'custom_item_remarks': item['custom_item_remarks'] ?? '',
                  'custom_variant_info':
                      item['custom_variant_info']?.toString() ?? '',
                };
              }).toList(),
              subtotal: _calculateSubtotal(),
              tax: _calculateGST(),
              discount: _discountAmount,
              rounding: _calculateRounding(),
              total: _calculateTotal(),
            );
          });

          return WillPopScope(
            onWillPop: () async {
              await _confirmExit();
              return false; // Prevent default back behavior
            },
            child: Scaffold(
              backgroundColor: Colors.white,
              body: SafeArea(
                child: Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left side - Payment Methods
                          Expanded(
                            flex: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildTableInfo(),
                                  const SizedBox(height: 16),
                                  _buildPaymentMethodGrid(),
                                  const SizedBox(height: 16),
                                  // Action Buttons Grid
                                  _buildActionButtonsGrid(),
                                ],
                              ),
                            ),
                          ),

                          // Vertical divider
                          Container(
                            width: 1,
                            color: Colors.grey.shade300,
                          ),

                          // Right side - Order details
                          Expanded(
                            flex: 3,
                            child: Column(
                              children: [
                                // Scrollable section
                                Expanded(
                                  child: ScrollConfiguration(
                                    behavior: NoStretchScrollBehavior(),
                                    child: SingleChildScrollView(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          _buildOrderHeader(),
                                          const SizedBox(height: 16),
                                          _buildOrderItemsList(),
                                          const SizedBox(height: 24),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                _buildRemarksField(),
                                // Fixed bottom Order Summary
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16.0),
                                  color: Colors.white,
                                  child: _buildOrderSummary(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
  }

  Widget _buildHeader() {
    return FutureBuilder(
        future: SharedPreferences.getInstance(),
        builder: (context, snapshot) {
          final username = snapshot.hasData
              ? snapshot.data!.getString('username') ?? 'Administrator'
              : 'Administrator';
          return Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // IconButton(
                //   icon: Icon(Icons.arrow_back),
                //   onPressed: () => _confirmExit(),
                // ),
                Text(
                  widget.order['tableNumber'] == 0
                      ? 'Instant Order'
                      : 'MK-Floor 1-Table ${widget.order['tableNumber'] ?? "Take Away"}',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                // _buildStatPill(
                //     'Revenue', 'RM${_totalRevenue.toStringAsFixed(2)}'),
                // const SizedBox(width: 8),
                // _buildStatPill(
                //     'Unpaid Orders', _totalUnpaidOrders.toStringAsFixed(2)),
                // const SizedBox(width: 8),
                // _buildStatPill('Tables Free', '$_totalTablesFree'),
              ],
            ),
          );
        });
  }

  Widget _buildStatPill(String title, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.order['tableNumber'] == 0
                ? 'Instant Order'
                : 'MK-Floor 1-Table ${widget.order['tableNumber'] ?? "Take Away"}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Entry Time',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 8),
              Text(
                _formatTime(widget.order['entryTime'] ?? DateTime.now()),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethodGrid() {
    if (_isLoadingPaymentMethods) {
      return const Expanded(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Expanded(
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: _paymentMethods.length,
        itemBuilder: (context, index) {
          final method = _paymentMethods[index];
          final isSelected = _selectedPaymentMethod == method['name'];
          final isCash = method['name'] == 'Cash';
          final isOfflinePayment = method['custom_fiuu_m1_value'] == '-1';

          return GestureDetector(
            onTap: () async {
              if (isCash) {
                // Show cash dialog and only select if user confirms
                final confirmed = await _showCashPaymentDialog();
                if (confirmed) {
                  setState(() {
                    _selectedPaymentMethod = method['name'];
                  });
                } else {
                  // If dialog is cancelled, deselect the payment method
                  setState(() {
                    _selectedPaymentMethod = '';
                  });
                }
              } else if (isOfflinePayment) {
                // For offline payment methods (m1_value = -1), select immediately
                // No POS terminal communication needed
                setState(() {
                  _selectedPaymentMethod = method['name'];
                });
              } else {
                // For other non-cash methods that require POS terminal, select immediately
                setState(() {
                  _selectedPaymentMethod = method['name'];
                });
              }
            },
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFE732A0)
                      : Colors.blue.shade300,
                  width: isSelected ? 3 : 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.network(
                    '$baseImageUrl${method['custom_payment_mode_image']}',
                    height: 60,
                    width: 60,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.payment, size: 60),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    method['name'],
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color:
                          isSelected ? const Color(0xFFE732A0) : Colors.black,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionButtonsGrid() {
    final canSplit = orderItems.length > 1;

    return Container(
      height: 120,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                if (_isSplitting)
                  Expanded(
                    child: _buildActionButton(
                      'Cancel Split',
                      Colors.grey,
                      onPressed: _toggleSplitMode,
                    ),
                  )
                else
                  Expanded(
                    child: _buildPayNowButton(),
                  ),
                const SizedBox(width: 10),
                if (_isSplitting)
                  Expanded(
                    child: _buildActionButton(
                      'Confirm Split',
                      Colors.green,
                      onPressed: _confirmSplit,
                    ),
                  )
                else
                  Expanded(
                    child: _buildPayLaterButton(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _buildActionButton(
              _isSplitting ? 'Cancel Split' : 'Split Bill',
              _isEditing
                  ? Colors.grey
                  : canSplit
                      ? const Color(0xFF00203E)
                      : Colors.grey,
              onPressed: _isEditing || !canSplit ? null : _toggleSplitMode,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, Color color,
      {VoidCallback? onPressed}) {
    return ElevatedButton(
      onPressed: onPressed ?? () {},
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        minimumSize: Size.fromHeight(50),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  List<Widget> _buildVariantText(Map<String, dynamic> item) {
    dynamic variantInfo = item['custom_variant_info'];
    if (variantInfo == null) return [];

    // Handle case where variantInfo is a JSON string
    if (variantInfo is String) {
      try {
        variantInfo = jsonDecode(variantInfo);
      } catch (e) {
        debugPrint('Error parsing variant info: $e');
        return [];
      }
    }

    // Handle case where variantInfo is a List
    if (variantInfo is List) {
      return variantInfo.expand((variant) {
        if (variant is Map && variant['options'] is List) {
          return (variant['options'] as List).map((option) {
            return Text(
              '• ${variant['variant_group']}: ${option['option']}'
              '${option['additional_cost'] > 0 ? ' (+RM${option['additional_cost'].toStringAsFixed(2)})' : ''}',
              style: TextStyle(fontSize: 12, color: Colors.black),
            );
          }).toList();
        }
        return <Widget>[];
      }).toList();
    }

    // Handle case where variantInfo is a Map (old format)
    if (variantInfo is Map) {
      return variantInfo.entries.map((entry) {
        return Text(
          '• ${entry.key}: ${entry.value}',
          style: TextStyle(fontSize: 12, color: Colors.black),
        );
      }).toList();
    }

    return [];
  }

  Widget _buildOrderHeader() {
    return Column(
      children: [
        Row(
          children: [
            if (widget.order['invoiceNumber'] != null)
              GestureDetector(
                onTap: _isEditing ? null : _deleteOrder,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _isEditing ? Colors.grey : Colors.red,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Delete Order',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            Spacer(),
            // Add these to your _buildOrderHeader method
            if (_isEditing) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _undoLastChange,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Undo',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _discardChanges,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Discard',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _isEditing ? null : _showVoucherDialog(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _isEditing ? Colors.grey : Colors.blue,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _discountAmount > 0 ? 'Remove Discount' : 'Apply Discount',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _isEditing ? _updateOrder : _toggleEditMode,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _isEditing ? Colors.green : Colors.yellow,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isEditing ? 'Update Order' : 'Edit Order',
                  style: TextStyle(
                    color: _isEditing ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _isEditing ? null : _navigateToHomeScreen(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _isEditing ? Colors.grey : const Color(0xFFE732A0),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Add Item',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Table(
          columnWidths: const {
            0: FixedColumnWidth(62), // Image column
            1: FlexColumnWidth(3), // Item name
            2: FlexColumnWidth(1.5), // Quantity
            3: FlexColumnWidth(1.5), // Split checkbox
            4: FlexColumnWidth(1.5), // Price
            5: FlexColumnWidth(1.5), // Amount
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                const SizedBox(), // Empty for image column
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'Item Name',
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.left, // Align left for Item Name
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'Quantity',
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center, // Center align Quantity
                  ),
                ),
                if (_isSplitting) // Only show split header when in split mode
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'Split',
                      style: TextStyle(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center, // Center align Split
                    ),
                  )
                else
                  const SizedBox.shrink(),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'Price (RM)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.right, // Right align Price
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'Amount (RM)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.right, // Right align Amount
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOrderItemsList() {
    final items = _isEditing ? _editableItems : orderItems;

    return Table(
      columnWidths: const {
        0: FixedColumnWidth(62), // Image column
        1: FlexColumnWidth(3.5), // Item name
        2: FlexColumnWidth(2.5), // Quantity
        3: FlexColumnWidth(1.5), // Split checkbox
        4: FlexColumnWidth(2), // Price
        5: FlexColumnWidth(2), // Amount
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (int i = 0; i < items.length; i++)
          TableRow(
            decoration: BoxDecoration(
              color: _itemsToSplit.any((item) => item['original_index'] == i)
                  ? Colors.pink.withOpacity(0.1)
                  : null,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            children: [
              // Image cell
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Stack(
                  children: [
                    Image.network(
                      _getProperImageUrl('${items[i]['image']}'),
                      width: 50,
                      height: 50,
                      errorBuilder: (context, error, stackTrace) => Image.asset(
                          'assets/pizza.png',
                          width: 50,
                          height: 50),
                    ),
                    if (_isEditing)
                      Positioned(
                        top: 0,
                        left: 0,
                        child: GestureDetector(
                          onTap: () => _deleteItem(i),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Item name cell
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      items[i]['name'],
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (items[i]['custom_variant_info'] != null)
                      ..._buildVariantText(items[i]),
                    if (items[i]['custom_serve_later'] == true ||
                        (items[i]['custom_serve_later'] is num &&
                            items[i]['custom_serve_later'] == 1))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '● Serve Later',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    if (items[i]['custom_item_remarks'] != null &&
                        items[i]['custom_item_remarks'].toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Remarks: ${items[i]['custom_item_remarks']}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Quantity cell
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: _isEditing
                    ? Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove, size: 20),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _decreaseQuantity(i),
                              ),
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 2),
                                child: Text(
                                  (_editableItems[i]['quantity'] as num)
                                      .toStringAsFixed(0),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              IconButton(
                                  icon: const Icon(Icons.add, size: 20),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _increaseQuantity(i)),
                            ],
                          ),
                          if (_itemStockQuantities[_editableItems[i]
                                  ['item_code']] !=
                              null)
                            Text(
                              'Stock: ${_itemStockQuantities[_editableItems[i]['item_code']]}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                        ],
                      )
                    : Text(
                        'x${(items[i]['quantity'] as num).toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
              ),

              // Split checkbox cell (only visible in split mode)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: _isSplitting
                    ? Checkbox(
                        value: _itemsToSplit.any((splitItem) =>
                            splitItem['item_code'] == items[i]['item_code'] &&
                            _compareOptions(
                                splitItem['options'], items[i]['options'])),
                        onChanged: (value) async {
                          if (value == true) {
                            if ((items[i]['quantity'] as num).toInt() > 1) {
                              await _showQuantitySelectorDialog(items[i]);
                            } else {
                              setState(() {
                                _itemsToSplit.add({
                                  ...items[i],
                                  'split_quantity': 1,
                                });
                              });
                            }
                          } else {
                            setState(() {
                              _itemsToSplit.removeWhere((splitItem) =>
                                  splitItem['item_code'] ==
                                      items[i]['item_code'] &&
                                  _compareOptions(splitItem['options'],
                                      items[i]['options']));
                            });
                          }
                        },
                      )
                    : const SizedBox.shrink(),
              ),

              // Price cell
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Show original price if there's a discount
                    if ((items[i]['discount_amount'] ?? 0) > 0) ...[
                      Text(
                        'RM${(items[i]['price']).toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 12,
                          decoration: TextDecoration.lineThrough,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                    // Show current price
                    Text(
                      'RM${(items[i]['price']).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: (items[i]['discount_amount'] ?? 0) > 0
                            ? Color(0xFFE732A0)
                            : Colors.black,
                      ),
                    ),
                  ],
                ),
              ),

              // Amount cell
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Show original amount if there's a discount
                    if ((items[i]['discount_amount'] ?? 0) > 0) ...[
                      Text(
                        'RM${((items[i]['price']) * items[i]['quantity'] + items[i]['discount_amount']).toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 12,
                          decoration: TextDecoration.lineThrough,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                    // Show current amount with proper discount calculation
                    Text(
                      'RM${((items[i]['price'] * items[i]['quantity'])).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: (items[i]['discount_amount'] ?? 0) > 0
                            ? Color(0xFFE732A0)
                            : Colors.black,
                      ),
                    ),
                    // Show discount amount if any
                    if ((items[i]['discount_amount'] ?? 0) > 0) ...[
                      Text(
                        'Discount: RM${(items[i]['discount_amount'] * items[i]['quantity']).toStringAsFixed(2)}',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  void _navigateToHomeScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HomeScreen(
          tableNumber: widget.order['tableNumber'],
          existingOrder: {
            ...widget.order,
            'items': widget.order['items'],
            'orderId': widget.order['invoiceNumber'],
            'invoiceNumber': widget.order['invoiceNumber'],
          },
          isTier1: true,
        ),
      ),
    );
  }

  Widget _buildOrderSummary() {
    final totalAmount = _calculateTotal();
    final isCashPayment = _selectedPaymentMethod == 'Cash';
    final paidAmount = isCashPayment ? _amountGiven : totalAmount;
    final changeAmount = isCashPayment ? _amountGiven - totalAmount : 0.0;

    // Calculate original subtotal before any discounts
    final originalSubtotal = orderItems.fold(0.0, (sum, item) {
      return sum + (item['price'] * item['quantity']);
    });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Show subtotal
          _buildSummaryRow(
            'Subtotal',
            "RM ${originalSubtotal.toStringAsFixed(2)}",
          ),
          const SizedBox(height: 8),

          if (_discountAmount > 0) ...[
            _buildSummaryRow(
              'Discount',
              "-RM ${_discountAmount.toStringAsFixed(2)}",
            ),
            const SizedBox(height: 8),
          ],

          _buildSummaryRow(
            'GST (6%)',
            "RM ${total_taxes_and_charges.toStringAsFixed(2)}",
          ),
          const SizedBox(height: 8),

          _buildSummaryRow(
            'Rounding',
            "RM ${_calculateRounding().toStringAsFixed(2)}",
          ),
          const Divider(thickness: 1, height: 24),

          _buildSummaryRow(
            'Grand Total',
            "RM ${totalAmount.toStringAsFixed(2)}",
            isTotal: true,
          ),
          const SizedBox(height: 8),

          if (isCashPayment) ...[
            _buildSummaryRow(
              'Amount Given',
              "RM ${paidAmount.toStringAsFixed(2)}",
            ),
            const SizedBox(height: 8),
            _buildSummaryRow(
              'Change Amount',
              "RM ${changeAmount.toStringAsFixed(2)}",
              isTotal: true,
            ),
          ] else ...[
            _buildSummaryRow(
              'Payment Method',
              _selectedPaymentMethod,
              isTotal: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRemarksField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _remarksController,
              decoration: InputDecoration(
                hintText: 'Add remarks...',
                hintStyle: TextStyle(fontSize: 16, color: Colors.grey),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Color(0xFFE732A0)),
                ),
              ),
              style: TextStyle(fontSize: 16),
              maxLines: 1,
              enabled: !_isSavingRemarks,
              onChanged: (value) {
                setState(() {
                  _isRemarksEditing = value != _currentRemarks;
                });
              },
              onSubmitted: (_) {
                if (_isRemarksEditing && !_isSavingRemarks) {
                  _saveRemarks();
                  FocusScope.of(context).unfocus();
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          _isSavingRemarks
              ? Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Container(
                  decoration: BoxDecoration(
                    color: _isRemarksEditing
                        ? Color(0xFFE732A0)
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.check, size: 18, color: Colors.white),
                    onPressed: _isRemarksEditing && !_isSavingRemarks
                        ? () {
                            _saveRemarks();
                            FocusScope.of(context).unfocus();
                          }
                        : null,
                    constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
                ),
        ],
      ),
    );
  }

  Future<void> _saveRemarks() async {
    if (_remarksController.text.isEmpty || _isSavingRemarks) return;

    setState(() => _isSavingRemarks = true);

    try {
      final invoiceName = widget.order['invoiceNumber'];
      if (invoiceName == null) return;

      final response = await PosService().submitOrder(
        name: invoiceName,
        posProfile: ref.read(authProvider).maybeWhen(
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
                  ) {
                    return posProfile;
                  },
                  orElse: () => null,
                ) ??
            '',
        customer: 'Guest',
        items: orderItems.map((item) {
          return {
            'item_code': item['item_code'] ?? '',
            'qty': item['quantity'],
            'price_list_rate': item['price'],
            'custom_item_remarks': item['custom_item_remarks'] ?? '',
            'custom_serve_later': item['custom_serve_later'] == true ? 1 : 0,
            if (item['custom_variant_info'] != null)
              'custom_variant_info': item['custom_variant_info'],
          };
        }).toList(),
        couponCode: widget.order['coupon_code'],
        custom_user_voucher: widget.order['custom_user_voucher'],
        remarks: _remarksController.text, // Add remarks parameter
      );

      if (response['success'] == true) {
        setState(() {
          _currentRemarks = _remarksController.text;
          _isRemarksEditing = false;
          widget.order['remarks'] = _currentRemarks;
        });

        Fluttertoast.showToast(
          msg: "Remarks updated successfully",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Failed to save remarks: ${e.toString()}",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      setState(() => _isSavingRemarks = false);
    }
  }

  Widget _buildSummaryRow(String label, dynamic value, {bool isTotal = false}) {
    String formattedValue;

    if (value == null) {
      formattedValue = '';
    } else if (value is num) {
      formattedValue = 'RM ${value.toStringAsFixed(2)}';
    } else if (value is DateTime) {
      formattedValue = DateFormat('dd MMM yyyy HH:mm').format(value);
    } else if (value is String && value.contains('T')) {
      // Handle ISO date strings
      try {
        formattedValue =
            DateFormat('dd MMM yyyy HH:mm').format(DateTime.parse(value));
      } catch (e) {
        formattedValue = value;
      }
    } else {
      formattedValue = value.toString();
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.bold,
              )),
          Text(formattedValue,
              style: TextStyle(
                fontSize: 18,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.bold,
                color: isTotal ? Color(0xFFE732A0) : Colors.black,
              )),
        ],
      ),
    );
  }

  Widget _buildPayLaterButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: _isEditing
            ? null
            : () async {
                // if (_selectedPaymentMethod.isEmpty) {
                //   Fluttertoast.showToast(
                //     msg: "Please select a payment method",
                //     gravity: ToastGravity.BOTTOM,
                //     backgroundColor: Colors.red,
                //     textColor: Colors.white,
                //   );
                //   return;
                // }

                await _completePayment(payLater: true);
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: _isEditing ? Colors.grey : Colors.blue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        child: const Text(
          'Pay Later',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildPayNowButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: _isEditing
            ? null
            : () async {
                if (_selectedPaymentMethod.isEmpty) {
                  Fluttertoast.showToast(
                    msg: "Please select a payment method",
                    gravity: ToastGravity.BOTTOM,
                    backgroundColor: Colors.red,
                    textColor: Colors.white,
                  );
                  return;
                }

                _completePayment();
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: _isEditing ? Colors.grey : const Color(0xFFE732A0),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        child: const Text(
          'Pay Now',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Future<void> _completePayment({bool payLater = false}) async {
    setState(() => _isProcessingPayment = true);

    // Check if this is an offline payment method (m1_value = -1)
    final selectedMethod = _paymentMethods.firstWhere(
      (method) => method['name'] == _selectedPaymentMethod,
      orElse: () => {'custom_fiuu_m1_value': '01'},
    );
    final m1Value = selectedMethod['custom_fiuu_m1_value']?.toString() ?? '01';
    final isOfflinePayment = m1Value == '-1';

    // Show processing dialog for non-cash payments that require POS terminal
    Completer<void>? dialogCompleter;
    if (_selectedPaymentMethod != 'Cash' &&
        !isOfflinePayment &&
        mounted &&
        !payLater) {
      dialogCompleter = Completer<void>();
      _showPaymentProcessingDialog(context).then((_) {
        if (!dialogCompleter!.isCompleted) {
          dialogCompleter.complete();
        }
      });
    }

    try {
      final totalAmount = _calculateTotal();
      final List<Map<String, dynamic>> payments = [
        {
          'mode_of_payment': _selectedPaymentMethod,
          'amount':
              _selectedPaymentMethod == 'Cash' ? _amountGiven : totalAmount,
          if (_selectedPaymentMethod == 'Cash')
            'reference_no': 'CASH-${DateTime.now().millisecondsSinceEpoch}',
        }
      ];

      final invoiceName = widget.order['invoiceNumber'];
      if (invoiceName == null) {
        throw Exception('Invoice number not available');
      }

      // Get printKitchenOrder flag from auth provider
      final shouldPrintKitchenOrder = ref.read(authProvider).maybeWhen(
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
            ) {
              return printKitchenOrder == 1;
            },
            orElse: () => false,
          );

      // Only process POS terminal communication for non-cash, non-offline payments
      if (_selectedPaymentMethod != 'Cash' && !isOfflinePayment && !payLater) {
        // 1. Get the selected payment method's m1 value
        final m1Value =
            selectedMethod['custom_fiuu_m1_value']?.toString() ?? '01';

        // 2. Generate the purchase hex message with the correct m1 value
        final transactionId =
            'INV${invoiceName.replaceAll(RegExp(r'[^0-9]'), '')}';
        final paddedTransactionId =
            transactionId.padRight(20, '0').substring(0, 20);
        final hexMessage = PosHexGenerator.generatePurchaseHexMessage(
          paddedTransactionId,
          totalAmount,
          m1Value, // Use the m1 value from the payment method
        );

        // Rest of your POS terminal communication code...
        final prefs = await SharedPreferences.getInstance();
        final posIp = prefs.getString('pos_ip') ?? '192.168.1.10';
        final posPort = 8800;

        // 3. Connect to POS terminal with longer timeout
        final socket = await Socket.connect(posIp, posPort,
            timeout: const Duration(seconds: 10));

        try {
          // Set up response handler with timeout
          final response = await _handlePosTransaction(socket, hexMessage);

          if (response['status'] != 'success') {
            throw Exception(
                response['response_text'] ?? 'POS transaction declined');
          }

          // Add POS response details to payment
          payments[0]['pos_response'] = response;
          payments[0]['reference_no'] = response['transaction_id'] ??
              'POS-${DateTime.now().millisecondsSinceEpoch}';
          payments[0]['pos_reference_no'] =
              response['pos_invoice_number'] ?? ''; // Add POS reference
        } finally {
          socket.destroy();
        }
      } else if (isOfflinePayment && !payLater) {
        // For offline payments, add a simple reference number
        payments[0]['reference_no'] =
            'OFFLINE-${DateTime.now().millisecondsSinceEpoch}';
      }

      // For Pay Later, we just submit the order without processing payment
      if (payLater) {
        // Show print receipt dialog
        final shouldPrint = await _showPrintReceiptDialog();

        if (shouldPrint) {
          await ReceiptPrinter.showPrintDialog(
            context,
            invoiceName,
            shouldPrintKitchenOrder: shouldPrintKitchenOrder,
          );
        }
        if (mounted) {
          Fluttertoast.showToast(
            msg: "Order saved for later payment",
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.green,
            textColor: Colors.white,
          );
          Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
        }
      } else {
        // Original payment processing code
        final response = await PosService().checkoutOrder(
          invoiceName: invoiceName,
          payments: payments,
        );

        if (response['success'] == true) {
          // Show print receipt dialog
          final shouldPrint = await _showPrintReceiptDialog();

          if (shouldPrint) {
            await ReceiptPrinter.showPrintDialog(
              context,
              invoiceName,
              shouldPrintKitchenOrder: shouldPrintKitchenOrder,
            );
          }
          if (mounted) {
            Fluttertoast.showToast(
              msg: "Payment Successful",
              gravity: ToastGravity.BOTTOM,
              backgroundColor: Colors.green,
              textColor: Colors.white,
            );
          }

          if (dialogCompleter != null && !dialogCompleter.isCompleted) {
            Navigator.of(context).pop();
            dialogCompleter.complete();
          }
          Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
        }
      }
    } catch (e) {
      if (mounted) {
        if (dialogCompleter != null && !dialogCompleter.isCompleted) {
          Navigator.of(context).pop();
          dialogCompleter.complete();
        }

        Fluttertoast.showToast(
          msg: "Error: ${e.toString()}",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingPayment = false);
      }
    }
  }

  Future<Map<String, dynamic>> _handlePosTransaction(
      Socket socket, String hexMessage) async {
    final completer = Completer<Map<String, dynamic>>();
    final responseBuffer = <int>[];
    bool ackReceived = false;
    StreamSubscription? subscription;

    subscription = socket.listen(
      (List<int> data) {
        debugPrint(
            '📦 Received data: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');

        // Handle ACK separately
        if (!ackReceived && data.length == 1 && data[0] == 0x06) {
          ackReceived = true;
          debugPrint('✅ Received ACK (0x06), waiting for full response...');
          return;
        }

        // Add data to buffer
        responseBuffer.addAll(data);

        // Check if we have a complete response (STX...ETX)
        if (ackReceived && responseBuffer.isNotEmpty) {
          final stxIndex = responseBuffer.indexOf(0x02);
          final etxIndex = responseBuffer.indexOf(0x03);

          if (stxIndex != -1 && etxIndex != -1 && etxIndex > stxIndex) {
            debugPrint('📨 Complete response received, parsing...');

            try {
              // Extract the complete message from STX to ETX
              final messageData =
                  responseBuffer.sublist(stxIndex, etxIndex + 1);
              final response = _parsePosResponse(messageData);

              debugPrint('🎯 Parsed response: $response');

              if (!completer.isCompleted) {
                subscription?.cancel();
                completer.complete(response);
              }
            } catch (e) {
              final messageData =
                  responseBuffer.sublist(stxIndex, etxIndex + 1);
              final response = _parsePosResponse(messageData);

              debugPrint('🎯 Parsed response: $response');
              debugPrint('❌ Error parsing response: $e');
              if (!completer.isCompleted) {
                subscription?.cancel();
                completer.completeError(e);
              }
            }
          }
        }
      },
      onError: (error) {
        debugPrint('❌ Socket error: $error');
        if (!completer.isCompleted) {
          subscription?.cancel();
          completer.completeError(error);
        }
      },
      onDone: () {
        debugPrint('🔌 Socket connection closed');
        if (!completer.isCompleted) {
          subscription?.cancel();
          completer.completeError(
              Exception('Socket closed before receiving complete response'));
        }
      },
    );

    // Send the hex message
    final bytes = _hexStringToBytes(hexMessage);
    debugPrint(
        '📤 Sending message: ${bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
    socket.add(bytes);

    return completer.future.timeout(
      const Duration(seconds: 120),
      onTimeout: () {
        subscription?.cancel();
        throw TimeoutException('POS terminal response timeout');
      },
    );
  }

  Map<String, dynamic> _parsePosResponse(List<int> data) {
    try {
      debugPrint(
          '🔍 Parsing response data: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');

      // Check for complete message (STX...ETX)
      if (data.length >= 3 &&
          data.first == 0x02 &&
          data[data.length - 1] == 0x03) {
        // Extract the payload (everything between STX and ETX, excluding LRC if present)
        final payload = data.sublist(1, data.length - 1);

        // Convert to hex string for easier parsing
        final hexString =
            payload.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
        debugPrint('📄 Payload hex: $hexString');

        // Try to convert to ASCII for debugging
        try {
          final asciiString =
              String.fromCharCodes(payload.where((b) => b >= 32 && b <= 126));
          debugPrint('📝 ASCII representation: $asciiString');
        } catch (e) {
          debugPrint('⚠️ Could not convert to ASCII: $e');
        }

        final decoded = _decodeHexResponse(hexString, payload);
        debugPrint('✅ Decoded response: $decoded');

        return decoded;
      }

      throw Exception('Invalid POS response format - missing STX/ETX markers');
    } catch (e) {
      debugPrint('❌ Parse error: $e');
      return {
        'invoice_number': '000000',
        'response_text': 'Parse error: ${e.toString()}',
        'status': 'error',
        'transaction_id': '',
      };
    }
  }

  Map<String, dynamic> _decodeHexResponse(String hexString, List<int> rawData) {
    try {
      String invoiceNumber = '000000';
      String posInvoiceNumber = '000000';
      String responseText = 'UNKNOWN';
      String status = 'error';
      String transactionId = '';
      bool isQrPayment = false;
      bool isDuitNowPayment = false;

      try {
        final asciiData =
            String.fromCharCodes(rawData.where((b) => b >= 32 && b <= 126));

        // 1. Check if this is a QR or DuitNow payment
        isQrPayment = asciiData.contains(' QR ');
        isDuitNowPayment = asciiData.contains('DevN5');

        // 2. Extract main invoice number
        final invoiceMatch = RegExp(r'INV(\d{9})').firstMatch(asciiData);
        if (invoiceMatch != null) {
          invoiceNumber = invoiceMatch.group(1)!;
          transactionId = 'INV$invoiceNumber';
        }

        // 3. Extract reference number based on payment type
        if (isDuitNowPayment) {
          posInvoiceNumber = extractDuitNowReferenceId(asciiData);
        } else if (isQrPayment) {
          posInvoiceNumber = extractQrReferenceId(asciiData);
        } else {
          // Card Payment
          final index = asciiData.indexOf('6400');
          if (index != -1 && index >= 6) {
            posInvoiceNumber = asciiData.substring(index - 6, index);
          }
        }

        // 4. Check approval status
        if (asciiData.contains('APPROVED')) {
          status = 'success';
          responseText = 'APPROVED';
        }
      } catch (e) {
        debugPrint('⚠️ ASCII parsing failed: $e');
      }

      return {
        'invoice_number': invoiceNumber,
        'pos_invoice_number': posInvoiceNumber,
        'response_text': responseText,
        'status': status,
        'transaction_id': transactionId,
        'is_qr_payment': isQrPayment,
        'is_duitnow_payment': isDuitNowPayment,
      };
    } catch (e) {
      debugPrint('❌ Decode error: $e');
      return {
        'invoice_number': '000000',
        'pos_invoice_number': '000000',
        'response_text': 'Decode error: ${e.toString()}',
        'status': 'error',
        'transaction_id': 'ERROR_${DateTime.now().millisecondsSinceEpoch}',
        'is_qr_payment': false,
        'is_duitnow_payment': false,
      };
    }
  }

  String extractQrReferenceId(String asciiData) {
    try {
      // Extract YYMM from E6600325YYYY04
      final yymmMatch = RegExp(r'E6600325(\d{4})04').firstMatch(asciiData);

      // Extract HHMMSS after '04'
      final timeMatch = RegExp(r'E6600325\d{4}04(\d{6})').firstMatch(asciiData);

      // Extract 6-digit payment ref from '65000XXXXXX'
      final paymentRefMatch = RegExp(r'65(\d{6})64').firstMatch(asciiData);

      if (yymmMatch != null && timeMatch != null && paymentRefMatch != null) {
        final yymm = yymmMatch.group(1)!; // e.g. 0716
        final timeStr = timeMatch.group(1)!; // e.g. 012026
        final middleRef = paymentRefMatch.group(1)!; // e.g. 000521

        // Parse HHMMSS and subtract 2 seconds
        int hh = int.parse(timeStr.substring(0, 2));
        int mm = int.parse(timeStr.substring(2, 4));
        int ss = int.parse(timeStr.substring(4, 6));

        int totalSeconds = hh * 3600 + mm * 60 + ss - 2;
        if (totalSeconds < 0) totalSeconds = 0; // Guard against negatives

        final adjHH = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
        final adjMM = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
        final adjSS = (totalSeconds % 60).toString().padLeft(2, '0');

        final adjustedTime = '$adjHH$adjMM$adjSS'; // HHMMSS adjusted
        print("SOHAI $yymm$adjustedTime$middleRef");

        return '$yymm$adjustedTime$middleRef';
      }
    } catch (e) {
      debugPrint('Error extracting QR reference: $e');
    }

    return '000000000000000000';
  }

  String extractDuitNowReferenceId(String asciiData) {
    try {
      final match = RegExp(r'DevN5(\d{16})').firstMatch(asciiData);
      if (match != null) {
        return match.group(1)!;
      }
    } catch (e) {
      debugPrint('Error extracting DuitNow reference: $e');
    }
    return '000000000000000000';
  }

  // Helper function to convert hex string to bytes
  List<int> _hexStringToBytes(String hexString) {
    return hexString
        .split(' ')
        .map((hex) => int.parse(hex, radix: 16))
        .toList();
  }

  String extractPosInvoiceNumber(String asciiData) {
    try {
      // Find the index of "6400"
      final index = asciiData.indexOf('6400');
      if (index != -1 && index >= 6) {
        // Extract 6 characters before "6400"
        return asciiData.substring(index - 6, index);
      }
    } catch (e) {
      debugPrint('Error extracting POS invoice number: $e');
    }
    return '000000';
  }

  Future<bool> _showPrintReceiptDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text(
                'Print Receipt?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: const Text(
                'Would you like to print the receipt for this transaction?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'No',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE732A0),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text(
                    'Yes',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<bool> _confirmExit() async {
    // For tier 1, show delete order dialog instead of exit dialog
    final authState = ref.read(authProvider);
    final isTier1 = authState.maybeWhen(
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
      ) {
        return tier.toLowerCase() == 'tier1';
      },
      orElse: () => false,
    );

    if (isTier1) {
      await _deleteOrder();
      return false; // Prevent default back behavior
    } else {
      final shouldExit = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Discard Payment?',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text(
              'Are you sure you want to exit without completing payment?',
              style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE732A0),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pushNamedAndRemoveUntil(
                    context, '/', (route) => false);
                // CustomerDisplayController.showDefaultDisplay();
              },
              child: const Text('Exit',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (shouldExit == true) {
        // Navigate to the root page if user confirms exit
        // CustomerDisplayController.showDefaultDisplay();
        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
        return false;
      }

      return false; // Don't pop the screen if user cancelled
    }
  }

  Future<bool> _showCashPaymentDialog() async {
    final totalAmount = _calculateTotal();
    final amountController = TextEditingController();
    double currentAmount = 0.0;

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return Dialog(
              backgroundColor: Colors.white,
              insetPadding: EdgeInsets.all(20), // Makes dialog bigger
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: 500), // Minimum width
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Cash Payment',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Total Amount: RM${totalAmount.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 20),
                      TextField(
                        controller: amountController,
                        decoration: InputDecoration(
                          labelText: 'Amount Received',
                          labelStyle: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                          prefixText: 'RM ',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              vertical: 15, horizontal: 15),
                        ),
                        style: TextStyle(fontSize: 18),
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true),
                        onChanged: (value) {
                          currentAmount = double.tryParse(value) ?? 0.0;
                        },
                      ),
                      SizedBox(height: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // First row of buttons (1, 5, 10, 20)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [1, 5, 10, 20].map((amount) {
                                return Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4.0),
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: Size(80, 60),
                                        textStyle: TextStyle(
                                            fontSize: 18, color: Colors.black),
                                      ),
                                      onPressed: () {
                                        currentAmount += amount;
                                        amountController.text =
                                            currentAmount.toStringAsFixed(2);
                                      },
                                      child: Text('RM$amount',
                                          style: TextStyle(
                                              color: Colors.black,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),

                          SizedBox(height: 12),

                          // Second row of buttons (50, 100, Clear)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12.0),
                            child: Row(
                              children: [
                                for (var label in ['RM50', 'RM100', 'Clear'])
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4.0),
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          minimumSize: Size(80, 60),
                                          textStyle: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold),
                                        ),
                                        onPressed: () {
                                          if (label == 'Clear') {
                                            currentAmount = 0.0;
                                            amountController.clear();
                                          } else {
                                            final add = int.parse(
                                                label.replaceAll('RM', ''));
                                            currentAmount += add;
                                            amountController.text =
                                                currentAmount
                                                    .toStringAsFixed(2);
                                          }
                                        },
                                        child: Text(label,
                                            style:
                                                TextStyle(color: Colors.black)),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          SizedBox(height: 30),

                          // Action buttons
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 30.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                      minimumSize: Size(120, 50),
                                      textStyle: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    child: Text('Cancel',
                                        style: TextStyle(color: Colors.black)),
                                  ),
                                ),
                                SizedBox(width: 20),
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: Size(120, 50),
                                      backgroundColor: Color(0xFFE732A0),
                                      textStyle: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    onPressed: () {
                                      if (currentAmount >= totalAmount) {
                                        setState(() {
                                          _amountGiven = currentAmount;
                                        });
                                        Navigator.of(context).pop(true);
                                      } else {
                                        Fluttertoast.showToast(
                                          msg:
                                              "Amount received is less than total amount",
                                          gravity: ToastGravity.BOTTOM,
                                          backgroundColor: Colors.red,
                                          textColor: Colors.white,
                                        );
                                      }
                                    },
                                    child: Text('OK',
                                        style: TextStyle(color: Colors.white)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            );
          },
        ) ??
        false;
  }

  Future<void> _deleteOrderFromItem() async {
    final orderName = widget.order['invoiceNumber']?.toString();
    if (orderName == null || orderName.isEmpty) {
      // If no invoice number, just navigate back
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
      return;
    }

    setState(() => _isProcessingPayment = true);

    try {
      final response = await PosService().deleteOrder(orderName);

      if (response['success'] == true) {
        if (mounted) {
          Fluttertoast.showToast(
            msg: "Order Deleted Successfully",
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.green,
            textColor: Colors.white,
          );
          Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
        }
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: "Failed to delete order: ${e.toString()}",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingPayment = false);
      }
    }
  }

  Future<void> _deleteOrder() async {
    final orderName = widget.order['invoiceNumber']?.toString();
    if (orderName == null || orderName.isEmpty) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: const Text(
              'Delete Order',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            content: const Text(
              'Are you sure you want to delete this order? This action cannot be undone.',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'CANCEL',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                child: Text(
                  'DELETE',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() => _isProcessingPayment = true);

    try {
      final response = await PosService().deleteOrder(orderName);

      if (response['success'] == true) {
        if (mounted) {
          Fluttertoast.showToast(
            msg: "Order Deleted Successfully",
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.green,
            textColor: Colors.white,
          );
          Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
        }
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: "Failed to delete order: ${e.toString()}",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingPayment = false);
      }
    }
  }

  Future<void> _showVoucherDialog() async {
    final hasDiscount = _discountAmount > 0 ||
        widget.order['coupon_code'] != null ||
        widget.order['custom_user_voucher'] != null;

    if (hasDiscount) {
      final shouldRemove = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Remove Discount',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'Are you sure you want to remove the current discount?',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            TextButton(
              child: const Text(
                'CANCEL',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE732A0),
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'REMOVE',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );

      if (shouldRemove == true) {
        await _removeDiscount();
      }
      return;
    }

    final voucherController = TextEditingController();
    final discountPercentageController = TextEditingController();
    final discountAmountController = TextEditingController();
    int selectedDiscountType =
        0; // 0 = voucher, 1 = percentage, 2 = amount, 3 = itemized

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text(
                'Apply Discount',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: ScrollConfiguration(
                behavior: NoStretchScrollBehavior(),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Discount type selector
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text(
                              'Voucher',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            selected: selectedDiscountType == 0,
                            onSelected: (selected) {
                              setState(() {
                                selectedDiscountType =
                                    selected ? 0 : selectedDiscountType;
                              });
                            },
                          ),
                          ChoiceChip(
                            label: Text(
                              'Percentage',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            selected: selectedDiscountType == 1,
                            onSelected: (selected) {
                              setState(() {
                                selectedDiscountType =
                                    selected ? 1 : selectedDiscountType;
                                if (selected) {
                                  voucherController.clear();
                                  discountAmountController.clear();
                                }
                              });
                            },
                          ),
                          ChoiceChip(
                            label: Text(
                              'Amount',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            selected: selectedDiscountType == 2,
                            onSelected: (selected) {
                              setState(() {
                                selectedDiscountType =
                                    selected ? 2 : selectedDiscountType;
                                if (selected) {
                                  voucherController.clear();
                                  discountPercentageController.clear();
                                }
                              });
                            },
                          ),
                          ChoiceChip(
                            label: Text(
                              'Itemized Discount',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            selected: selectedDiscountType == 3,
                            onSelected: (selected) {
                              setState(() {
                                selectedDiscountType =
                                    selected ? 3 : selectedDiscountType;
                                if (selected) {
                                  voucherController.clear();
                                  discountPercentageController.clear();
                                  discountAmountController.clear();
                                }
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Voucher code field (only visible when voucher is selected)
                      if (selectedDiscountType == 0)
                        TextField(
                          controller: voucherController,
                          decoration: const InputDecoration(
                            labelText: 'Voucher Code',
                            border: OutlineInputBorder(),
                          ),
                        ),

                      // Percentage field (only visible when percentage is selected)
                      if (selectedDiscountType == 1)
                        TextField(
                          controller: discountPercentageController,
                          decoration: const InputDecoration(
                            labelText: 'Discount Percentage (%)',
                            border: OutlineInputBorder(),
                            suffixText: '%',
                          ),
                          keyboardType:
                              TextInputType.numberWithOptions(decimal: true),
                          onChanged: (value) {
                            if (value.isNotEmpty) {
                              final percentage = double.tryParse(value) ?? 0;
                              final amount =
                                  _calculateSubtotal() * percentage / 100;
                              discountAmountController.text =
                                  amount.toStringAsFixed(2);
                            } else {
                              discountAmountController.clear();
                            }
                          },
                        ),

                      // Amount field (only visible when amount is selected)
                      if (selectedDiscountType == 2)
                        TextField(
                          controller: discountAmountController,
                          decoration: const InputDecoration(
                            labelText: 'Discount Amount (RM)',
                            border: OutlineInputBorder(),
                            prefixText: 'RM ',
                          ),
                          keyboardType:
                              TextInputType.numberWithOptions(decimal: true),
                          onChanged: (value) {
                            if (value.isNotEmpty) {
                              final amount = double.tryParse(value) ?? 0;
                              final percentage =
                                  (amount / _calculateSubtotal()) * 100;
                              discountPercentageController.text =
                                  percentage.toStringAsFixed(2);
                            } else {
                              discountPercentageController.clear();
                            }
                          },
                        ),

                      // Itemized discount button (only visible when itemized is selected)
                      if (selectedDiscountType == 3)
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context)
                                .pop(true); // Close this dialog
                            _showItemizedDiscountDialog(); // Show itemized discount dialog
                          },
                          child: Text(
                            'Select Items to Discount',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                if (selectedDiscountType !=
                    3) // Hide Apply button for itemized discount
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE732A0),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      'Apply',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      if (selectedDiscountType == 0 &&
                          voucherController.text.isEmpty) {
                        Fluttertoast.showToast(
                          msg: "Please enter a voucher code",
                          gravity: ToastGravity.BOTTOM,
                          backgroundColor: Colors.red,
                          textColor: Colors.white,
                        );
                        return;
                      } else if (selectedDiscountType == 1 &&
                          discountPercentageController.text.isEmpty) {
                        Fluttertoast.showToast(
                          msg: "Please enter a discount percentage",
                          gravity: ToastGravity.BOTTOM,
                          backgroundColor: Colors.red,
                          textColor: Colors.white,
                        );
                        return;
                      } else if (selectedDiscountType == 2 &&
                          discountAmountController.text.isEmpty) {
                        Fluttertoast.showToast(
                          msg: "Please enter a discount amount",
                          gravity: ToastGravity.BOTTOM,
                          backgroundColor: Colors.red,
                          textColor: Colors.white,
                        );
                        return;
                      }
                      Navigator.of(context).pop(true);
                    },
                  ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      if (selectedDiscountType == 0) {
        // Voucher code
        _validateVoucher(voucherController.text);
      } else if (selectedDiscountType == 1) {
        // Percentage discount
        final percentage =
            double.tryParse(discountPercentageController.text) ?? 0;
        final amount = _calculateSubtotal() * percentage / 100;
        await _applyManualDiscount(amount);
      } else if (selectedDiscountType == 2) {
        // Fixed amount discount
        final amount = double.tryParse(discountAmountController.text) ?? 0;
        await _applyManualDiscount(amount);
      }
      // Itemized discount handled separately in _showItemizedDiscountDialog
    }
  }

  Future<void> _showItemizedDiscountDialog() async {
    final items = _isEditing ? _editableItems : orderItems;
    final List<Map<String, dynamic>> itemsWithDiscounts = List.from(items);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.8,
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'Itemized Discount',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: itemsWithDiscounts.length,
                        itemBuilder: (context, index) {
                          final item = itemsWithDiscounts[index];
                          final itemTotal = item['price'] * item['quantity'];

                          // Real-time calculation functions
                          void updateFromPercentage(String value) {
                            if (value.isEmpty) {
                              setState(() {
                                itemsWithDiscounts[index] = {
                                  ...item,
                                  'discount_percentage': 0,
                                  'discount_amount': 0,
                                };
                              });
                              return;
                            }

                            final percentage = double.tryParse(value) ?? 0;
                            final cappedPercentage =
                                percentage > 100 ? 100 : percentage;
                            final amount = (itemTotal * cappedPercentage / 100)
                                .clamp(0, itemTotal);

                            setState(() {
                              itemsWithDiscounts[index] = {
                                ...item,
                                'discount_percentage': cappedPercentage,
                                'discount_amount': amount,
                              };
                            });
                          }

                          void updateFromAmount(String value) {
                            if (value.isEmpty) {
                              setState(() {
                                itemsWithDiscounts[index] = {
                                  ...item,
                                  'discount_percentage': 0,
                                  'discount_amount': 0,
                                };
                              });
                              return;
                            }

                            final amount = double.tryParse(value) ?? 0;
                            final cappedAmount =
                                amount > itemTotal ? itemTotal : amount;
                            final percentage = itemTotal > 0
                                ? (cappedAmount / itemTotal) * 100
                                : 0;

                            setState(() {
                              itemsWithDiscounts[index] = {
                                ...item,
                                'discount_percentage': percentage,
                                'discount_amount': cappedAmount,
                              };
                            });
                          }

                          // Get current calculated values for display
                          final currentDiscountAmount =
                              itemsWithDiscounts[index]['discount_amount'] ?? 0;
                          final currentDiscountPercentage =
                              itemsWithDiscounts[index]
                                      ['discount_percentage'] ??
                                  0;

                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['name'],
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          initialValue: (itemsWithDiscounts[
                                                              index][
                                                          'discount_percentage'] ??
                                                      0) ==
                                                  0
                                              ? ''
                                              : (itemsWithDiscounts[index][
                                                          'discount_percentage']
                                                      as num)
                                                  .toStringAsFixed(2)
                                                  .replaceAll(
                                                      RegExp(r'\.?0+$'), ''),
                                          decoration: InputDecoration(
                                            labelText: 'Discount %',
                                            border: OutlineInputBorder(),
                                            suffixText: '%',
                                            errorText:
                                                currentDiscountPercentage > 100
                                                    ? 'Max 100%'
                                                    : null,
                                          ),
                                          keyboardType:
                                              TextInputType.numberWithOptions(
                                                  decimal: true),
                                          onChanged: updateFromPercentage,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextFormField(
                                          initialValue: (itemsWithDiscounts[
                                                              index]
                                                          ['discount_amount'] ??
                                                      0) ==
                                                  0
                                              ? ''
                                              : (itemsWithDiscounts[index]
                                                          ['discount_amount']
                                                      as num)
                                                  .toStringAsFixed(2)
                                                  .replaceAll(
                                                      RegExp(r'\.?0+$'), ''),
                                          decoration: InputDecoration(
                                            labelText: 'Discount Amount (RM)',
                                            border: OutlineInputBorder(),
                                            prefixText: 'RM ',
                                            errorText: currentDiscountAmount >
                                                    itemTotal
                                                ? 'Max RM${itemTotal.toStringAsFixed(2)}'
                                                : null,
                                          ),
                                          keyboardType:
                                              TextInputType.numberWithOptions(
                                                  decimal: true),
                                          onChanged: updateFromAmount,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Real-time calculated values display
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Original: RM${itemTotal.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        if (currentDiscountAmount > 0) ...[
                                          Text(
                                            'Discount: ${currentDiscountPercentage.toStringAsFixed(1)}% = RM${currentDiscountAmount.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.orange.shade700,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                        Text(
                                          'Final Amount: RM${(itemTotal - currentDiscountAmount).toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: currentDiscountAmount > 0
                                                ? Colors.green.shade700
                                                : Colors.black,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE732A0),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async {
                              // Validate all inputs before proceeding
                              bool hasInvalidDiscounts = false;
                              String errorMessage = '';

                              for (int i = 0;
                                  i < itemsWithDiscounts.length;
                                  i++) {
                                final item = itemsWithDiscounts[i];
                                final discountAmount =
                                    item['discount_amount'] ?? 0;
                                final discountPercentage =
                                    item['discount_percentage'] ?? 0;
                                final itemTotal =
                                    item['price'] * item['quantity'];

                                if (discountAmount > itemTotal) {
                                  hasInvalidDiscounts = true;
                                  errorMessage =
                                      "Discount for '${item['name']}' exceeds item amount";
                                  break;
                                }

                                if (discountPercentage > 100) {
                                  hasInvalidDiscounts = true;
                                  errorMessage =
                                      "Discount percentage for '${item['name']}' cannot exceed 100%";
                                  break;
                                }
                              }

                              if (hasInvalidDiscounts) {
                                Fluttertoast.showToast(
                                  msg: errorMessage,
                                  gravity: ToastGravity.BOTTOM,
                                  backgroundColor: Colors.red,
                                  textColor: Colors.white,
                                  toastLength: Toast.LENGTH_LONG,
                                );
                              } else {
                                Navigator.of(context).pop();
                                await _applyItemizedDiscounts(
                                    itemsWithDiscounts);
                              }
                            },
                            child: const Text(
                              'Apply Discounts',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _applyItemizedDiscounts(
      List<Map<String, dynamic>> itemsWithDiscounts) async {
    // Validate discounts before sending
    for (int i = 0; i < itemsWithDiscounts.length; i++) {
      final item = itemsWithDiscounts[i];
      final discountAmount = item['discount_amount'] ?? 0;
      final discountPercentage = item['discount_percentage'] ?? 0;
      final itemTotal = item['price'] * item['quantity'];

      // Check if discount exceeds item total
      if (discountAmount > itemTotal) {
        Fluttertoast.showToast(
          msg:
              "Discount for '${item['name']}' cannot exceed item total (RM${itemTotal.toStringAsFixed(2)})",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
        return;
      }
    }

    _showLoadingOverlay(true);

    try {
      final invoiceName = widget.order['invoiceNumber'];
      if (invoiceName == null) return;

      // Prepare items for submission - ensure only one discount type per item
      final itemsToSubmit = itemsWithDiscounts.map((item) {
        final itemData = {
          'item_code': item['item_code'] ?? '',
          'qty': item['quantity'],
          'price_list_rate': item['price'],
          'custom_item_remarks': item['custom_item_remarks'] ?? '',
          'custom_serve_later': item['custom_serve_later'] == true ? 1 : 0,
          if (item['custom_variant_info'] != null)
            'custom_variant_info': item['custom_variant_info'],
        };

        // Add only one discount field - prioritize amount over percentage
        if (item['discount_amount'] != null && item['discount_amount'] > 0) {
          itemData['discount_amount'] = item['discount_amount'];
        } else if (item['discount_percentage'] != null &&
            item['discount_percentage'] > 0) {
          itemData['discount_percentage'] = item['discount_percentage'];
        }

        return itemData;
      }).toList();

      final response = await PosService().submitOrder(
        name: invoiceName,
        posProfile: ref.read(authProvider).maybeWhen(
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
                  ) {
                    return posProfile;
                  },
                  orElse: () => null,
                ) ??
            '',
        customer: 'Guest',
        items: itemsToSubmit,
      );

      if (response['success'] == true) {
        // Update the order details with new amounts
        await _fetchOrderDetails();

        // Update local state
        setState(() {
          if (_isEditing) {
            _editableItems = List.from(itemsWithDiscounts);
          }
          _discountAmount = itemsWithDiscounts.fold(
            0.0,
            (sum, item) => sum + (item['discount_amount'] ?? 0),
          );
        });

        Fluttertoast.showToast(
          msg: "Itemized discounts applied successfully",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Error applying itemized discounts: ${e.toString()}",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      _showLoadingOverlay(false);
    }
  }

  Future<void> _applyManualDiscount(double amount) async {
    _showLoadingOverlay(true);

    try {
      final invoiceName = widget.order['invoiceNumber'];
      if (invoiceName == null) return;

      // Update local state immediately
      setState(() {
        _discountAmount = amount;

        // Update each item's discount amount proportionally
        final subtotal = _calculateSubtotal();
        if (subtotal > 0) {
          for (var item in orderItems) {
            final itemTotal = item['price'] * item['quantity'];
            final itemDiscount = (itemTotal / subtotal) * amount;
            item['discount_amount'] = itemDiscount;
          }
        }
      });

      final response = await PosService().submitOrder(
        name: invoiceName,
        posProfile: ref.read(authProvider).maybeWhen(
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
                  ) {
                    return posProfile;
                  },
                  orElse: () => null,
                ) ??
            '',
        customer: 'Guest',
        items: orderItems.map((item) {
          return {
            'item_code': item['item_code'] ?? '',
            'qty': item['quantity'],
            'price_list_rate': item['price'],
            'custom_item_remarks': item['custom_item_remarks'] ?? '',
            'custom_serve_later': item['custom_serve_later'] == true ? 1 : 0,
            if (item['custom_variant_info'] != null)
              'custom_variant_info': item['custom_variant_info'],
          };
        }).toList(),
        discountAmount: amount, // Pass the discount amount directly
      );

      if (response['success'] == true) {
        // Update the order details with new amounts from server
        await _fetchOrderDetails();
        Fluttertoast.showToast(
          msg: "Discount applied successfully",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Error applying discount: ${e.toString()}",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      // Revert local changes on error
      setState(() {
        _discountAmount = 0;
        for (var item in orderItems) {
          item['discount_amount'] = 0;
        }
      });
    } finally {
      _showLoadingOverlay(false);
    }
  }

  Future<void> _removeDiscount() async {
    _showLoadingOverlay(true);

    try {
      final invoiceName = widget.order['invoiceNumber'];
      if (invoiceName == null) return;

      // Update local state immediately
      setState(() {
        _discountAmount = 0;
        _voucherCode = '';

        // Remove discounts from all items
        for (var item in orderItems) {
          item['discount_amount'] = 0;
        }

        if (_isEditing) {
          for (var item in _editableItems) {
            item['discount_amount'] = 0;
          }
        }
      });

      final response = await PosService().submitOrder(
        name: invoiceName,
        posProfile: ref.read(authProvider).maybeWhen(
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
                  ) =>
                      posProfile,
                  orElse: () => null,
                ) ??
            '',
        customer: 'Guest',
        items: orderItems.map((item) {
          return {
            'item_code': item['item_code'] ?? '',
            'qty': item['quantity'],
            'price_list_rate': item['price'],
            'custom_item_remarks': item['custom_item_remarks'] ?? '',
            'custom_serve_later': item['custom_serve_later'] == true ? 1 : 0,
            if (item['custom_variant_info'] != null)
              'custom_variant_info': item['custom_variant_info'],
          };
        }).toList(),
        couponCode: null, // Set to null to remove
        custom_user_voucher: null, // Set to null to remove
        discountAmount: 0, // Set to 0 to remove
      );

      if (response['success'] == true) {
        // Force a complete refresh of order details
        await _fetchOrderDetails();

        Fluttertoast.showToast(
          msg: "Discount removed successfully",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Error removing discount: ${e.toString()}",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      _showLoadingOverlay(false);
    }
  }

  Future<void> _validateVoucher(String voucherCode) async {
    _showLoadingOverlay(true);

    try {
      final response = await PosService().validateVoucher(voucherCode);

      if (response['success'] == true) {
        final voucherData = response['message'];
        final voucherName = voucherData['name'];
        final couponCode = voucherData['coupon_code'];

        setState(() {
          _voucherCode = voucherName;
        });

        // Update the order with the voucher
        await _updateOrderWithVoucher(voucherName, couponCode);

        Fluttertoast.showToast(
          msg: "Voucher applied successfully",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      } else {
        Fluttertoast.showToast(
          msg: "Voucher code is invalid or redeemed",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Error validating voucher: ${e.toString()}",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      _showLoadingOverlay(false);
    }
  }

  Future<void> _updateOrderWithVoucher(
      String voucherName, String couponCode) async {
    try {
      final invoiceName = widget.order['invoiceNumber'];
      if (invoiceName == null) return;

      // Update local state immediately
      setState(() {
        _voucherCode = voucherName;
        // We'll let the server calculate the discount amount
        // The _fetchOrderDetails() call below will update the actual discount amount
      });

      final response = await PosService().submitOrder(
        name: invoiceName,
        posProfile: ref.read(authProvider).maybeWhen(
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
                  ) {
                    return posProfile;
                  },
                  orElse: () => null,
                ) ??
            '',
        customer: 'Guest',
        items: orderItems.map((item) {
          return {
            'item_code': item['item_code'] ?? '',
            'qty': item['quantity'],
            'price_list_rate': item['price'],
            'custom_item_remarks': item['custom_item_remarks'] ?? '',
            'custom_serve_later': item['custom_serve_later'] == true ? 1 : 0,
            if (item['custom_variant_info'] != null)
              'custom_variant_info': item['custom_variant_info'],
          };
        }).toList(),
        couponCode: couponCode,
        custom_user_voucher: voucherName,
      );

      if (response['success'] == true) {
        // Update the order details with new amounts from server
        await _fetchOrderDetails();
      }
    } catch (e) {
      debugPrint('Error updating order with voucher: $e');
      // Revert local changes on error
      setState(() {
        _voucherCode = '';
      });
    }
  }

  void _showLoadingOverlay(bool show) {
    if (show) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return WillPopScope(
            onWillPop: () async => false,
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        },
      );
    } else {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  double _calculateSubtotal() {
    // Use server value if available, otherwise calculate from items
    return (widget.order['total'] as num?)?.toDouble() ??
        orderItems.fold(
            0.0, (sum, item) => sum + (item['price'] * item['quantity']));
  }

  double _calculateRounding() {
    // Use server value if available, otherwise calculate
    return (widget.order['base_rounding_adjustment'] as num?)?.toDouble() ??
        ((_calculateSubtotal() + _calculateGST()) * 100).round() / 100 -
            (_calculateSubtotal() + _calculateGST());
  }

  double _calculateTotal() {
    // Use server value if available, otherwise calculate
    return (widget.order['rounded_total'] as num?)?.toDouble() ??
        (_calculateSubtotal() + _calculateGST() + _calculateRounding());
  }

  double _calculateGST() {
    final authState = ref.read(authProvider);
    return authState.whenOrNull(
          authenticated: (sid,
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
              merchantId) {
            // Find the GST tax rate
            final gstTax = taxes.firstWhere(
              (tax) => tax['description']?.contains('GST') ?? false,
              orElse: () => {'rate': 6.0}, // Default to 6% if not found
            );
            return _calculateSubtotal() * (gstTax['rate'] ?? 6.0) / 100;
          },
        ) ??
        (_calculateSubtotal() * 0.06); // Fallback to 6% if not authenticated
  }

  String _formatTime(DateTime time) {
    final hour = time.hour > 12 ? time.hour - 12 : time.hour;
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} $period';
  }

  Future<void> _showPaymentProcessingDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User must not close dialog manually
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Add your GIF here (make sure to add the GIF to your assets)
              Image.asset(
                'assets/gif-do-payment.gif',
                height: 150,
                width: 150,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 20),
              const Text(
                'Processing Payment...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Please wait while we process your payment',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              const CircularProgressIndicator(),
            ],
          ),
        );
      },
    );
  }

  void _toggleEditMode() {
    setState(() {
      _isEditing = !_isEditing;
      if (_isEditing) {
        // Save original items
        _previousEditableItems =
            List<Map<String, dynamic>>.from(widget.order['items'])
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
        // Make a deep copy for editing
        _editableItems = List<Map<String, dynamic>>.from(widget.order['items'])
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        // Initialize edit history with the current state
        _editHistory = [
          _editableItems.map((item) => Map<String, dynamic>.from(item)).toList()
        ];
        debugPrint(
            'Edit mode enabled, initial state: ${_editableItems.map((item) => "${item['name']}: ${item['quantity']}").toList()}');
      } else {
        // Clear edit history and reset editable items when exiting edit mode
        _editHistory = [];
        _editableItems = [];
        _previousEditableItems = [];
      }
    });
  }

  void _saveEditState() {
    // Create a deep copy of the current state
    final currentState =
        _editableItems.map((item) => Map<String, dynamic>.from(item)).toList();
    _editHistory.add(currentState);
    // Keep only the last 10 states to prevent memory issues
    if (_editHistory.length > 10) {
      _editHistory.removeAt(0);
    }
    debugPrint(
        'Saved state to history: ${currentState.map((item) => "${item['name']}: ${item['quantity']}").toList()}');
  }

  void _undoLastChange() {
    if (_editHistory.length > 1) {
      setState(() {
        _editHistory.removeLast(); // Remove the current state
        // Create a deep copy of the previous state
        _editableItems = _editHistory.last
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        debugPrint(
            'Restored state: ${_editableItems.map((item) => "${item['name']}: ${item['quantity']}").toList()}');
      });
    } else {
      Fluttertoast.showToast(
        msg: "Nothing to undo",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.grey,
        textColor: Colors.white,
      );
    }
  }

  void _discardChanges() {
    setState(() {
      // Restore original items
      _editableItems = _previousEditableItems
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      // Reset edit history to initial state
      _editHistory = [List<Map<String, dynamic>>.from(_editableItems)];
      _isEditing = false; // Exit edit mode
    });
  }

  void _deleteItem(int index) async {
    final isLastItem = _editableItems.length == 1;

    if (!isLastItem) {
      setState(() {
        _editableItems.removeAt(index);
        debugPrint('Deleted item at index $index');
        _saveEditState(); // Save state AFTER change
      });
      return;
    }
    // Only show confirmation dialog for last item
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            title: Text(
              'Delete Order',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Text(
              'This is the last item in the order. Removing it will delete the entire order. Are you sure?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'CANCEL',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFE732A0),
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  'DELETE ORDER',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (confirmed) {
      await _deleteOrderFromItem();
    }
  }

  void _increaseQuantity(int index) {
    final itemCode = _editableItems[index]['item_code'];
    final availableStock = _itemStockQuantities[itemCode] ?? 999;
    final currentQuantity = _editableItems[index]['quantity'] as num;

    if (currentQuantity >= availableStock) {
      Fluttertoast.showToast(
        msg: "Cannot add more than available stock ($availableStock)",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    setState(() {
      _editableItems[index] = {
        ..._editableItems[index],
        'quantity': currentQuantity + 1,
      };
      debugPrint(
          'Increased quantity for ${itemCode} to ${currentQuantity + 1}');
      _saveEditState(); // Save state AFTER change
    });
  }

  void _decreaseQuantity(int index) {
    final currentQuantity = _editableItems[index]['quantity'] as num;

    if (currentQuantity <= 1) {
      Fluttertoast.showToast(
        msg: "Item quantity cannot be 0",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    setState(() {
      _editableItems[index] = {
        ..._editableItems[index],
        'quantity': currentQuantity - 1,
      };
      debugPrint(
          'Decreased quantity for ${_editableItems[index]['item_code']} to ${currentQuantity - 1}');
      _saveEditState(); // Save state AFTER change
    });
  }

  Future<void> _updateOrder() async {
    if (_editableItems.isEmpty) {
      Fluttertoast.showToast(
        msg: "Order cannot be empty",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    // Validate stock before updating
    for (var item in _editableItems) {
      final itemCode = item['item_code'];
      final availableStock = _itemStockQuantities[itemCode] ?? 999;
      final quantity = item['quantity'];

      if (quantity > availableStock) {
        Fluttertoast.showToast(
          msg:
              "Cannot order more than available stock ($availableStock) for ${item['name']}",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
        return;
      }
    }

    _showLoadingOverlay(true);

    try {
      final invoiceName = widget.order['invoiceNumber'];
      if (invoiceName == null) return;

      final response = await PosService().submitOrder(
        name: invoiceName,
        posProfile: ref.read(authProvider).maybeWhen(
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
                    printKitchenOrde,
                    openingDate,
                    itemsGroups,
                    baseUrl,
                    merchantId,
                  ) {
                    return posProfile;
                  },
                  orElse: () => null,
                ) ??
            '',
        customer: 'Guest',
        items: _editableItems.map((item) {
          return {
            'item_code': item['item_code'] ?? '',
            'qty': item['quantity'],
            'price_list_rate': item['price'],
            'custom_item_remarks': item['custom_item_remarks'] ?? '',
            'custom_serve_later': item['custom_serve_later'] == true ? 1 : 0,
            if (item['custom_variant_info'] != null)
              'custom_variant_info': item['custom_variant_info'],
          };
        }).toList(),
        couponCode: widget.order['coupon_code'],
        custom_user_voucher: widget.order['custom_user_voucher'],
      );

      if (response['success'] == true) {
        // Update the order details with new amounts
        await _fetchOrderDetails();
        setState(() {
          _isEditing = false;
          widget.order['items'] = _editableItems;
        });
        Fluttertoast.showToast(
          msg: "Order updated successfully",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Error updating order: ${e.toString()}",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      _showLoadingOverlay(false);
    }
  }

  void _toggleSplitMode() {
    if (orderItems.length <= 1) {
      Fluttertoast.showToast(
        msg: "Cannot split an order with only one item",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    setState(() {
      _isSplitting = !_isSplitting;
      if (!_isSplitting) {
        _itemsToSplit.clear();
      }
    });
  }

  Future<void> _selectItemForSplit(int index, Map<String, dynamic> item) async {
    if (item['quantity'] > 1) {
      final quantity = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Select Quantity to Split'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('How many of "${item['name']}" to split?'),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(Icons.remove),
                    onPressed: () {
                      Navigator.pop(
                          context, max<int>((item['quantity'] as int) - 1, 1));
                    },
                  ),
                  Text('${item['quantity']}'),
                  IconButton(
                    icon: Icon(Icons.add),
                    onPressed: () {
                      Navigator.pop(
                          context,
                          min<int>(item['quantity'] + 1 as int,
                              item['quantity'] as int));
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 0),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, item['quantity']),
              child: Text('Split All'),
            ),
          ],
        ),
      );

      if (quantity == null || quantity <= 0) return;

      setState(() {
        _itemsToSplit.add({
          ...item,
          'original_index': index,
          'split_quantity': quantity,
        });
      });
    } else {
      setState(() {
        _itemsToSplit.add({
          ...item,
          'original_index': index,
          'split_quantity': 1,
        });
      });
    }
  }

  Future<void> _confirmSplit() async {
    if (orderItems.length <= 1) {
      Fluttertoast.showToast(
        msg: "Cannot split an order with only one item",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }
    if (_itemsToSplit.isEmpty) {
      Fluttertoast.showToast(
        msg: "Please select items to split",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    setState(() => _isProcessingSplit = true);

    try {
      final authState = ref.read(authProvider);
      final posProfile = authState.maybeWhen(
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
        ) {
          return posProfile;
        },
        orElse: () => null,
      );

      if (posProfile == null) throw Exception('Not authenticated');

      // 1. Create new order with split items
      final response = await PosService().submitOrder(
          posProfile: posProfile,
          customer: 'Guest',
          items: _itemsToSplit
              .map((item) => {
                    'item_code': item['item_code'],
                    'qty': item['split_quantity'],
                    'price_list_rate': item['price'],
                    "custom_item_remarks": item['custom_item_remarks'],
                    "custom_serve_later": item['custom_serve_later'],
                    if (item['custom_variant_info'] != null)
                      'custom_variant_info': item['custom_variant_info'],
                  })
              .toList(),
          table: "MK-Floor 1-Take Away",
          orderChannel: "Dine In");

      if (response['success'] == true) {
        final splitOrder = response['message'];
        setState(() => _splitOrder = splitOrder);

        // 2. Show payment dialog for split order
        final paymentSuccess = await _showSplitOrderPaymentDialog(splitOrder);

        if (paymentSuccess) {
          // 3. If payment successful, update original order
          await _updateOriginalOrderAfterSplit();

          // 4. Fetch updated order details from server
          await _fetchOrderDetails();

          Fluttertoast.showToast(
            msg: "Order split and paid successfully",
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.green,
            textColor: Colors.white,
          );
        } else {
          // If payment failed or cancelled, delete the split order
          await PosService().deleteOrder(splitOrder['name']);

          Fluttertoast.showToast(
            msg: "Split cancelled - items restored to original order",
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.blue,
            textColor: Colors.white,
          );
        }
      }
    } catch (e) {
      // Fluttertoast.showToast(
      //   msg: "Error splitting order: ${e.toString()}",
      //   gravity: ToastGravity.BOTTOM,
      //   backgroundColor: Colors.red,
      //   textColor: Colors.white,
      // );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingSplit = false;
          _isSplitting = false;
          _itemsToSplit.clear();
        });
      }
    }
  }

  Future<void> _showQuantitySelectorDialog(Map<String, dynamic> item) async {
    final quantity = (item['quantity'] as num).toDouble();
    double selectedQuantity = quantity > 1 ? 1 : quantity;

    final result = await showDialog<double>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: StatefulBuilder(
              builder: (context, setState) {
                return SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Select Quantity to Split',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text('How many of "${item['name']}" to split?'),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove),
                              onPressed: () {
                                setState(() {
                                  selectedQuantity = selectedQuantity > 1
                                      ? selectedQuantity - 1
                                      : 1;
                                });
                              },
                            ),
                            Text(
                              selectedQuantity
                                  .toStringAsFixed(quantity % 1 == 0 ? 0 : 2),
                              style: const TextStyle(fontSize: 18),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: () {
                                setState(() {
                                  selectedQuantity = selectedQuantity < quantity
                                      ? selectedQuantity + 1
                                      : quantity;
                                });
                              },
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Slider(
                            value: selectedQuantity,
                            min: 1,
                            max: quantity,
                            divisions: (quantity - 1).toInt(),
                            label: selectedQuantity
                                .toStringAsFixed(quantity % 1 == 0 ? 0 : 2),
                            onChanged: (value) {
                              setState(() {
                                selectedQuantity = value;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, 0.0),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, quantity),
                              child: const Text('Split All'),
                            ),
                            ElevatedButton(
                              onPressed: () =>
                                  Navigator.pop(context, selectedQuantity),
                              child: const Text('Confirm'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );

    if (result == null || result <= 0) return;

    if (mounted) {
      setState(() {
        _itemsToSplit.add({
          ...item,
          'split_quantity': result,
          'original_quantity': quantity,
        });
      });
    }
  }

  String _getProperImageUrl(String imagePath) {
    if (imagePath == null || imagePath.isEmpty) {
      return 'assets/pizza.png';
    }

    if (imagePath.startsWith('http')) {
      return imagePath;
    }

    if (imagePath.startsWith('/')) {
      return '$baseImageUrl$imagePath';
    }

    if (!imagePath.startsWith('assets/')) {
      return '$baseImageUrl/$imagePath';
    }

    return imagePath; // local asset
  }

  Future<bool> _showSplitOrderPaymentDialog(
      Map<String, dynamic> splitOrder) async {
    final paymentCompleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SplitOrderPaymentDialog(
        order: splitOrder,
        paymentMethods: _paymentMethods,
        onPaymentComplete: () => Navigator.pop(context, true),
        onCancel: () => Navigator.pop(context, false),
        onPaymentFailed: () => Navigator.pop(context, false),
      ),
    );

    return paymentCompleted ?? false;
  }

  Future<void> _updateOriginalOrderAfterSplit() async {
    try {
      final invoiceName = widget.order['invoiceNumber'];
      if (invoiceName == null) return;

      // Create updated items list by reducing quantities or removing items
      final updatedItems =
          List<Map<String, dynamic>>.from(widget.order['items']);

      for (var splitItem in _itemsToSplit) {
        final originalItemIndex = updatedItems.indexWhere(
          (item) =>
              item['item_code'] == splitItem['item_code'] &&
              _compareOptions(item['options'], splitItem['options']),
        );

        if (originalItemIndex != -1) {
          final originalItem = updatedItems[originalItemIndex];
          final remainingQty = (originalItem['quantity'] as num).toDouble() -
              (splitItem['split_quantity'] as num).toDouble();

          if (remainingQty <= 0) {
            updatedItems.removeAt(originalItemIndex);
          } else {
            updatedItems[originalItemIndex] = {
              ...originalItem,
              'quantity': remainingQty,
            };
          }
        }
      }

      // Submit updated order
      final authState = ref.read(authProvider);
      final posProfile = authState.maybeWhen(
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
        ) {
          return posProfile;
        },
        orElse: () => null,
      );

      if (posProfile == null) throw Exception('Not authenticated');

      await PosService().submitOrder(
          name: invoiceName,
          posProfile: posProfile,
          customer: 'Guest',
          items: updatedItems.map((item) {
            return {
              'item_code': item['item_code'],
              'qty': item['quantity'],
              'price_list_rate': item['price'],
              'custom_item_remarks': item['custom_item_remarks'] ?? '',
              'custom_serve_later': item['custom_serve_later'] == true ? 1 : 0,
              if (item['custom_variant_info'] != null)
                'custom_variant_info': item['custom_variant_info'],
            };
          }).toList(),
          table: "MK-Floor 1-Take Away");

      // Update local state
      if (mounted) {
        setState(() {
          widget.order['items'] = updatedItems;
        });
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Error updating original order: ${e.toString()}",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      rethrow;
    }
  }

  bool _compareOptions(dynamic options1, dynamic options2) {
    if (options1 == null && options2 == null) return true;
    if (options1 == null || options2 == null) return false;

    // If they're both Maps, compare key-value pairs
    if (options1 is Map && options2 is Map) {
      final map1 = Map<String, dynamic>.from(options1);
      final map2 = Map<String, dynamic>.from(options2);

      if (map1.length != map2.length) return false;

      for (final key in map1.keys) {
        if (map1[key] != map2[key]) return false;
      }

      return true;
    }

    // If they're both Lists, compare elements
    if (options1 is List && options2 is List) {
      if (options1.length != options2.length) return false;

      for (int i = 0; i < options1.length; i++) {
        if (options1[i] != options2[i]) return false;
      }

      return true;
    }

    // Fallback to simple equality
    return options1 == options2;
  }
}
