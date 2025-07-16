import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:shiok_pos_android_app/components/customer_display_controller.dart';
import 'package:shiok_pos_android_app/components/no_stretch_scroll_behavior.dart';
import 'package:shiok_pos_android_app/components/pos_hex_generator.dart';
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
  bool _isValidatingVoucher = false;
  bool _isEditing = false;
  List<Map<String, dynamic>> _editableItems = [];
  Map<String, int> _itemStockQuantities = {};
  bool _isLoadingStock = false;

  @override
  void dispose() {
    _isDisposed = true; // Mark as disposed
    // CustomerDisplayController.showDefaultDisplay();

    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadPaymentMethods();
    _loadTodayInfo();
    _fetchOrderDetails();
    _checkStockForItems();
  }

  void _loadPaymentMethods() {
    final authState = ref.read(authProvider);
    authState.whenOrNull(
      authenticated: (sid, apiKey, apiSecret, username, email, fullName,
          posProfile, branch, paymentMethods, taxes, hasOpening, tier) {
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

  // Update the _fetchOrderDetails method in _CheckoutScreenState
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
          setState(() {
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
            _discountAmount = widget.order['discount_amount'];
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch order details: $e')),
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
      authenticated: (sid, apiKey, apiSecret, username, email, fullName,
          posProfile, branch, paymentMethods, taxes, hasOpening, tier) async {
        try {
          final newStockQuantities = <String, int>{};

          for (var item in orderItems) {
            try {
              final response = await PosService().getStockQuantity(
                posProfile: posProfile,
                itemCode: item['item_code'],
              );

              if (response['success'] == true) {
                newStockQuantities[item['item_code']] =
                    (response['message']['qty'] as num?)?.toInt() ?? 0;
              } else {
                newStockQuantities[item['item_code']] =
                    999; // Assume unlimited if API fails
              }
            } catch (e) {
              debugPrint('Error checking stock for ${item['item_code']}: $e');
              newStockQuantities[item['item_code']] =
                  999; // Assume unlimited on error
            }
          }

          setState(() {
            _itemStockQuantities = newStockQuantities;
          });
        } catch (e) {
          debugPrint('Error checking stock: $e');
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
        authenticated: (sid, apiKey, apiSecret, username, email, fullName,
            posProfile, branch, paymentMethods, taxes, hasOpening, tier) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            CustomerDisplayController.showCustomerScreen();
            CustomerDisplayController.updateOrderDisplay(
              items: orderItems
                  .map((item) => {
                        'name': item['name'],
                        'price': item['price'],
                        'quantity': item['quantity'],
                      })
                  .toList(),
              subtotal: _calculateSubtotal(),
              tax: _calculateGST(),
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
                  'Table ${widget.order['tableNumber']}',
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
              } else {
                // For non-cash methods, select immediately
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
                    'https://shiokpos.byondwave.com${method['custom_payment_mode_image']}',
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
    return Container(
      height: 120, // Fixed height for the action buttons grid
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                // Expanded(
                //   child: _buildActionButton(
                //     'Split Bill',
                //     const Color(
                //         0xFF00203E),
                //   ),
                // ),
                // const SizedBox(width: 10),
                // Expanded(
                //   child: _buildActionButton(
                //     'Transfer Table',
                //     const Color(0xFFFB8A3F),

                //   ),
                // ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              children: [
                // Expanded(
                //   child: _buildActionButton(
                //     'Pay Later',
                //     const Color(0xFF4E73F8), // Blue color like in the image
                //   ),
                // ),
                Expanded(
                  child: _buildActionButton(
                    'Split Bill',
                    const Color(0xFF00203E),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _buildPayNowButton()),
              ],
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
                onTap: _deleteOrder,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red,
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
            GestureDetector(
              onTap: () => _showVoucherDialog(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Apply Discount',
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
              onTap: () => _navigateToHomeScreen(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE732A0),
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
            1: FlexColumnWidth(3), // Item name (flexible, takes more space)
            2: FlexColumnWidth(1.5), // Quantity (proportional)
            3: FlexColumnWidth(2), // Price (proportional)
            4: FlexColumnWidth(2), // Amount (proportional)
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                const SizedBox(), // Empty for image column
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Text(
                    'Item Name',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Text(
                    'Quantity',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Text(
                    'Price (RM)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.right,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Text(
                    'Amount (RM)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.right,
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
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(62), // Image column
        1: FlexColumnWidth(3), // Item name (flexible, takes more space)
        2: FlexColumnWidth(1.5), // Quantity (proportional)
        3: FlexColumnWidth(2), // Price (proportional)
        4: FlexColumnWidth(2), // Amount (proportional)
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (int i = 0; i < orderItems.length; i++)
          TableRow(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Stack(
                  children: [
                    Image.network(
                      '${orderItems[i]['image']}',
                      width: 50,
                      height: 50,
                      errorBuilder: (context, error, stackTrace) =>
                          Image.network(
                        'https://shiokpos.byondwave.com${orderItems[i]['image']}',
                        width: 50,
                        height: 50,
                      ),
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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      orderItems[i]['name'],
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (orderItems[i]['custom_variant_info'] != null)
                      ..._buildVariantText(orderItems[i]),
                  ],
                ),
              ),
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
                                  _editableItems[i]['quantity']
                                      .toStringAsFixed(0),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add, size: 20),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  final itemCode =
                                      _editableItems[i]['item_code'];
                                  final availableStock =
                                      _itemStockQuantities[itemCode] ?? 999;
                                  final currentQuantity =
                                      _editableItems[i]['quantity'];

                                  if (currentQuantity >= availableStock) {
                                    Fluttertoast.showToast(
                                      msg:
                                          "Cannot add more than available stock ($availableStock)",
                                      gravity: ToastGravity.BOTTOM,
                                      backgroundColor: Colors.red,
                                      textColor: Colors.white,
                                    );
                                    return;
                                  }

                                  setState(() {
                                    _editableItems[i]['quantity'] += 1;
                                  });
                                },
                              ),
                            ],
                          ),
                          if (_itemStockQuantities[_editableItems[i]
                                  ['item_code']] !=
                              null)
                            Text(
                              'Stock: ${_itemStockQuantities[_editableItems[i]['item_code']]}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                        ],
                      )
                    : Text(
                        'x${orderItems[i]['quantity'].toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text(
                  orderItems[i]['price'].toStringAsFixed(2),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.right,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text(
                  (orderItems[i]['price'] * orderItems[i]['quantity'])
                      .toStringAsFixed(2),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.right,
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildSummaryRow(
              'Net Total', "RM ${_calculateSubtotal().toStringAsFixed(2)}"),
          const SizedBox(height: 8),
          if (_discountAmount > 0) ...[
            _buildSummaryRow(
                'Discount', "-RM ${_discountAmount.toStringAsFixed(2)}"),
            const SizedBox(height: 8),
          ],
          _buildSummaryRow(
              'Rounding', "RM ${_calculateRounding().toStringAsFixed(2)}"),
          const SizedBox(height: 8),
          _buildSummaryRow(
              'GST (6%)', "RM ${_calculateGST().toStringAsFixed(2)}"),
          const Divider(thickness: 1, height: 24),
          _buildSummaryRow(
              'Grand Total', "RM ${totalAmount.toStringAsFixed(2)}",
              isTotal: true),
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

  Widget _buildPayNowButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: () async {
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
          backgroundColor: const Color(0xFFE732A0),
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

  Future<void> _completePayment() async {
    setState(() => _isProcessingPayment = true);

    // Show processing dialog for non-cash payments
    Completer<void>? dialogCompleter;
    if (_selectedPaymentMethod != 'Cash' && mounted) {
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

      if (_selectedPaymentMethod != 'Cash') {
        // 1. Get the selected payment method's m1 value
        final selectedMethod = _paymentMethods.firstWhere(
          (method) => method['name'] == _selectedPaymentMethod,
          orElse: () =>
              {'custom_fiuu_m1_value': '01'}, // Fallback to '01' if not found
        );
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
      }

      // Rest of your checkout logic...
      final response = await PosService().checkoutOrder(
        invoiceName: invoiceName,
        payments: payments,
      );

      if (response['success'] == true) {
        // Handle successful payment
        if (mounted) {
          Fluttertoast.showToast(
            msg: "Payment Successful",
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.green,
            textColor: Colors.white,
          );
        }

        // Close the dialog if it exists
        if (dialogCompleter != null && !dialogCompleter.isCompleted) {
          Navigator.of(context).pop();
          dialogCompleter.complete();
        }
        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        // Close the dialog if it's still open
        if (dialogCompleter != null && !dialogCompleter.isCompleted) {
          Navigator.of(context).pop();
          dialogCompleter.complete();
        }

        Fluttertoast.showToast(
          msg: "Payment Error: ${e.toString()}",
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

      try {
        final asciiData =
            String.fromCharCodes(rawData.where((b) => b >= 32 && b <= 126));

        // 1. Check if this is a QR payment (look for "QR" marker)
        isQrPayment = asciiData.contains(' QR ');

        // 2. Extract main invoice number
        final invoiceMatch = RegExp(r'INV(\d{9})').firstMatch(asciiData);
        if (invoiceMatch != null) {
          invoiceNumber = invoiceMatch.group(1)!;
          transactionId = 'INV$invoiceNumber';
        }

        // 3. Extract reference number based on payment type
        if (isQrPayment) {
          posInvoiceNumber = extractQrReferenceId(asciiData);
        } else {
          // Card Payment - Standard extraction (6 digits before "6400")
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

  Future<bool> _confirmExit() async {
    // For tier 1, show delete order dialog instead of exit dialog
    final authState = ref.read(authProvider);
    final isTier1 = authState.maybeWhen(
      authenticated: (sid, apiKey, apiSecret, username, email, fullName,
          posProfile, branch, paymentMethods, taxes, hasOpening, tier) {
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

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text(
                'Cash Payment',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: ScrollConfiguration(
                behavior: NoStretchScrollBehavior(),
                child: SingleChildScrollView(
                  child: ListBody(
                    children: <Widget>[
                      Text(
                        'Total Amount: RM${totalAmount.toStringAsFixed(2)}',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: amountController,
                        decoration: const InputDecoration(
                          labelText: 'Amount Received',
                          labelStyle: TextStyle(fontWeight: FontWeight.bold),
                          prefixText: 'RM ',
                          hintStyle: TextStyle(fontWeight: FontWeight.bold),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (var amount in [10, 50, 100])
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                              ),
                              onPressed: () {
                                amountController.text =
                                    amount.toStringAsFixed(2);
                              },
                              child: Text('RM $amount'),
                            ),
                        ],
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
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE732A0),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    final amount =
                        double.tryParse(amountController.text) ?? 0.0;
                    if (amount >= totalAmount) {
                      setState(() {
                        _amountGiven = amount;
                      });
                      Navigator.of(context).pop(true);
                    } else {
                      Fluttertoast.showToast(
                        msg: "Amount received is less than total amount",
                        gravity: ToastGravity.BOTTOM,
                        backgroundColor: Colors.red,
                        textColor: Colors.white,
                      );
                    }
                  },
                ),
              ],
            );
          },
        ) ??
        false; // Return false if dialog is dismissed
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
    final voucherController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Apply Discount Voucher',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: voucherController,
            decoration: const InputDecoration(
              labelText: 'Voucher Code',
              border: OutlineInputBorder(),
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
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE732A0),
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Apply',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (result == true && voucherController.text.isNotEmpty) {
      _validateVoucher(voucherController.text);
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

  // Update the _updateOrderWithVoucher method in _CheckoutScreenState
  Future<void> _updateOrderWithVoucher(
      String voucherName, String couponCode) async {
    try {
      final invoiceName = widget.order['invoiceNumber'];
      if (invoiceName == null) return;

      final response = await PosService().submitOrder(
        name: invoiceName,
        posProfile: ref.read(authProvider).maybeWhen(
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
                      tier) {
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
        // Update the order details with new amounts
        await _fetchOrderDetails();
      }
    } catch (e) {
      debugPrint('Error updating order with voucher: $e');
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
          authenticated: (sid, apiKey, apiSecret, username, email, fullName,
              posProfile, branch, paymentMethods, taxes, hasOpening, tier) {
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
        // Make a copy of the items for editing
        _editableItems = List<Map<String, dynamic>>.from(widget.order['items']);
      }
    });
  }

  void _deleteItem(int index) async {
    final isLastItem = _editableItems.length == 1;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            title: Text(
              isLastItem ? 'Delete Order' : 'Remove Item',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Text(
              isLastItem
                  ? 'This is the last item in the order. Removing it will delete the entire order. Are you sure?'
                  : 'Are you sure you want to remove this item from the order?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'CANCEL',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE732A0),
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  isLastItem ? 'DELETE ORDER' : 'REMOVE',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (confirmed) {
      if (isLastItem) {
        // Delete the entire order
        await _deleteOrderFromItem();
      } else {
        // Just remove the item
        setState(() {
          _editableItems.removeAt(index);
        });
      }
    }
  }

  void _decreaseQuantity(int index) {
    if (_editableItems[index]['quantity'] <= 1) {
      Fluttertoast.showToast(
        msg: "Item quantity cannot be 0",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    setState(() {
      _editableItems[index]['quantity'] -= 1;
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
                      tier) {
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
}
