import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:shiok_pos_android_app/components/main_layout.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/screens/home_screen.dart';
import 'package:shiok_pos_android_app/screens/orders_screen.dart';
import 'package:shiok_pos_android_app/screens/table_screen.dart';
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

  @override
  void dispose() {
    _isDisposed = true; // Mark as disposed
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadPaymentMethods();
    _loadTodayInfo();
    _fetchOrderDetails();
  }

  void _loadPaymentMethods() {
    final authState = ref.read(authProvider);
    authState.whenOrNull(
      authenticated: (sid, apiKey, apiSecret, username, email, fullName,
          posProfile, branch, paymentMethods, taxes, hasOpening) {
        setState(() {
          _paymentMethods = paymentMethods;
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
                      hasOpening) {
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

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return authState.when(
        initial: () => const Center(child: CircularProgressIndicator()),
        unauthenticated: () => const Center(child: Text('Unauthorized')),
        authenticated: (sid, apiKey, apiSecret, username, email, fullName,
            posProfile, branch, paymentMethods, taxes, hasOpening) {
          return WillPopScope(
            onWillPop: _confirmExit,
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
                Text(
                  'Welcome back, $username',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                _buildStatPill(
                    'Revenue', 'RM${_totalRevenue.toStringAsFixed(2)}'),
                const SizedBox(width: 8),
                _buildStatPill(
                    'Unpaid Orders', _totalUnpaidOrders.toStringAsFixed(2)),
                const SizedBox(width: 8),
                _buildStatPill('Tables Free', '$_totalTablesFree'),
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
            'MK-Floor 1-Table ${widget.order['tableNumber'] ?? 1}',
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
                Expanded(
                  child: _buildActionButton(
                    'Split Bill',
                    const Color(
                        0xFF00203E), // Dark blue color like in the image
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildActionButton(
                    'Transfer Table',
                    const Color(0xFFFB8A3F), // Orange color like in the image
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    'Pay Later',
                    const Color(0xFF4E73F8), // Blue color like in the image
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

// Replace your _buildOrderHeader() method with this:
  Widget _buildOrderHeader() {
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back),
              onPressed: () => _confirmExit(),
            ),
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

// Replace your _buildOrderItemsList() method with this:
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
        for (final item in orderItems)
          TableRow(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Image.network(
                  '${item['image']}',
                  width: 50,
                  height: 50,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 50,
                    height: 50,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.fastfood),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text(
                  item['name'],
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text(
                  'x${item['quantity'].toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text(
                  item['price'].toStringAsFixed(2),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.right,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text(
                  (item['price'] * item['quantity']).toStringAsFixed(2),
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
    // After TableScreen is shown, navigate to HomeScreen with the order data
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
          _buildSummaryRow(
              'Rounding', "RM ${_calculateRounding().toStringAsFixed(2)}"),
          const SizedBox(height: 8),
          _buildSummaryRow(
              'GST @ 6.0%', "RM ${_calculateGST().toStringAsFixed(2)}"),
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

      final response = await PosService().checkoutOrder(
        invoiceName: invoiceName,
        payments: payments,
      );

      if (response['success'] == true) {
        final paidOrder = OrderMapper.mapPaidOrder(response);
        final completeOrder = {
          ...widget.order as Map<String, dynamic>,
          ...paidOrder,
          'isPaid': true,
          'status': 'Paid',
          'paidTime': DateTime.now().toIso8601String(),
          'paymentMethod': _selectedPaymentMethod,
          'net_total': _calculateSubtotal(),
          'base_rounding_adjustment': _calculateRounding(),
          'rounded_total': totalAmount,
          if (_selectedPaymentMethod == 'Cash') ...{
            'changeAmount': _amountGiven - totalAmount,
            'paidAmount': _amountGiven,
          },
          if (_selectedPaymentMethod != 'Cash') ...{
            'paidAmount': totalAmount,
            'changeAmount': 0.0,
          },
        };

        MainLayout.of(context)?.handleOrderPaid(completeOrder);

        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
          Fluttertoast.showToast(
            msg: "Checkout Successfully",
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.green,
            textColor: Colors.white,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment error: ${e.toString()}')),
        );
      }
      if (mounted) {
        Navigator.of(context).pop(false);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingPayment = false);
      }
    }
  }

  Future<bool> _confirmExit() async {
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
              Navigator.of(context).pop(true); // return true to indicate "Exit"
            },
            child: const Text('Exit',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (shouldExit == true) {
      // Navigate to the root page if user confirms exit
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
      return false; // prevent Flutter from popping the screen (since we already did)
    }

    return false; // Don't pop the screen if user cancelled
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
              content: SingleChildScrollView(
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
                  ],
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
          Navigator.of(context).pop(true);
          MainLayout.of(context)?.selectOrdersTab();
          Fluttertoast.showToast(
            msg: "Order Deleted Successfully",
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.green,
            textColor: Colors.white,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete order: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingPayment = false);
      }
    }
  }

  double _calculateSubtotal() {
    // Use server value if available, otherwise calculate from items
    return (widget.order['grand_total'] as num?)?.toDouble() ??
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
              posProfile, branch, paymentMethods, taxes, hasOpening) {
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
}
