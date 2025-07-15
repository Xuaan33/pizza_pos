import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiok_pos_android_app/components/no_stretch_scroll_behavior.dart';
import 'package:shiok_pos_android_app/components/pos_hex_generator.dart';
import 'package:shiok_pos_android_app/components/receipt_printer.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/screens/checkout_screen.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> orders;
  final Function(Map<String, dynamic>) onOrderPaid;
  final Function(Map<String, dynamic>) onEditOrder;
  final Future<void> Function()? onRefresh;
  final bool isLoading;

  const OrdersScreen({
    Key? key,
    required this.orders,
    required this.onOrderPaid,
    required this.onEditOrder,
    this.onRefresh,
    this.isLoading = false,
  }) : super(key: key);

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  String _filterStatus = 'All'; // 'All', 'Draft', 'Paid'
  String _filterOrderType = 'All'; // 'All', 'Dine in', 'Takeaway', 'Delivery'
  Map<String, dynamic>? _selectedOrder;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Initial load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshOrders();
    });
  }

  Future<void> _refreshOrders() async {
    await widget.onRefresh!();
    if (widget.onRefresh != null && mounted) {
      // Clear the current state to refresh the whole screen
      setState(() {
        _selectedOrder = null;
        _filterStatus = 'All';
        _filterOrderType = 'All';
      });

      // Call the refresh function to reload data
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredOrders = _filterOrders(widget.orders);
    final authState = ref.watch(authProvider);

    return authState.when(
      initial: () => const Center(child: CircularProgressIndicator()),
      unauthenticated: () => const Center(child: Text('Unauthorized')),
      authenticated: (sid, apiKey, apiSecret, username, email, fullName,
          posProfile, branch, paymentMethods, taxes, hasOpening, tier) {
        return Scaffold(
          body: Row(
            children: [
              // Left panel - Order list
              Expanded(
                flex: 5,
                child: _buildOrderListPanel(filteredOrders),
              ),

              // Right panel - Order details
              Expanded(
                flex: 5,
                child: _selectedOrder != null
                    ? _buildOrderDetailsPanel(_selectedOrder!)
                    : _buildEmptyDetailsPanel(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOrderListPanel(List<Map<String, dynamic>> orders) {
    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          // Header with filters
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Recent Orders',
                    style:
                        TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildFilterDropdown(
                        value: _filterStatus,
                        items: ['All', 'Draft', 'Paid'],
                        onChanged: (value) =>
                            setState(() => _filterStatus = value!),
                        label: 'Status',
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: _buildFilterDropdown(
                        value: _filterOrderType,
                        items: ['All', 'Dine in', 'Takeaway', 'Delivery'],
                        onChanged: (value) =>
                            setState(() => _filterOrderType = value!),
                        label: 'Order Type',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Order list
          Expanded(
            child: widget.isLoading
                ? Center(child: CircularProgressIndicator())
                : orders.isEmpty
                    ? Center(child: Text('No orders found'))
                    : ScrollConfiguration(
                        behavior: NoStretchScrollBehavior(),
                        child: ListView.builder(
                          itemCount: orders.length,
                          itemBuilder: (context, index) {
                            return _buildOrderListItem(orders[index]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderListItem(Map<String, dynamic> order) {
    final isSelected = _selectedOrder != null &&
        _selectedOrder!['orderId'] == order['orderId'];
    final isCancelled =
        order['status']?.toString().toLowerCase() == 'cancelled';
    final isDraft =
        !isCancelled && (order['status']?.toString().toLowerCase() == 'draft');
    final total = _calculateOrderTotal(order);

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 0,
      color: isSelected ? Colors.pink[100] : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _selectedOrder = order),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    order['orderId']?.toString() ?? 'ORDER-00',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isCancelled
                          ? Colors.red[200]
                          : (isDraft ? Colors.blue[100] : Colors.green[100]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isCancelled ? 'CANCELLED' : (isDraft ? 'DRAFT' : 'PAID'),
                      style: TextStyle(
                        color: isCancelled
                            ? Colors.red[800]
                            : (isDraft ? Colors.blue[800] : Colors.green[800]),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDate(_parseDateTime(order['entryTime'])),
                    style: TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'RM ${total.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE732A0),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderDetailsPanel(Map<String, dynamic> order) {
    final isDraft = (order['status']?.toString() ?? 'Draft') == 'Draft';
    final isCancelled =
        (order['status']?.toString() ?? 'Cancelled') == 'Cancelled';

    final items = (order['items'] as List<dynamic>?) ?? [];
    final subtotal = (order['net_total'] as num?)?.toDouble() ??
        _calculateOrderSubtotal(order);
    final tax = (order['total_taxes_and_charges'] as num?)?.toDouble() ??
        _calculateOrderTax(order);
    final rounding = (order['base_rounding_adjustment'] as num?)?.toDouble() ??
        _calculateRounding(subtotal + tax);
    final total =
        (order['total'] as num?)?.toDouble() ?? (subtotal + tax + rounding);
    final isPaid = order['isPaid'] == true;
    final taxBreakdown = order['taxBreakdown'] as Map<String, dynamic>?;

    return ScrollConfiguration(
      behavior: NoStretchScrollBehavior(),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Compact Order Info Tile
            Card(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // First row - Order ID and Total
                    Row(
                      children: [
                        Text(
                          'Order Details',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(width: 16),
                        Text(
                          order['orderType']?.toString() ?? 'Dine in',
                          style: TextStyle(
                              color: Colors.black, fontWeight: FontWeight.w600),
                        ),
                        Spacer(),
                        Container(
                          padding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: isCancelled
                                ? Colors.red[200]
                                : (isDraft
                                    ? Colors.blue[100]
                                    : Colors.green[100]),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            isCancelled
                                ? 'CANCELLED'
                                : (isDraft ? 'DRAFT' : 'PAID'),
                            style: TextStyle(
                              color: isCancelled
                                  ? Colors.red[800]
                                  : (isDraft
                                      ? Colors.blue[800]
                                      : Colors.green[800]),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 8),

                    // Second row - Order Type and Table
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (order['tableNumber'] != null) ...[
                          Text(
                            'Table ${order['tableNumber']}',
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                        Text(
                          _formatDate(_parseDateTime(order['entryTime'])),
                          style: TextStyle(
                              color: Colors.black,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          order['orderId']?.toString() ?? 'ORDER-00',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'RM ${total.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE732A0),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),

            Card(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Customer',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        // Optional: you can add a tag like VIP or Member status here
                      ],
                    ),
                    SizedBox(height: 8),
                    // Customer Name
                    Text(
                      order['customerName']?.toString() ?? 'Guest',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    // Remarks if available
                    if (order['custom_item_remarks'] != null &&
                        order['custom_item_remarks'].toString().isNotEmpty &&
                        order['custom_item_remarks'].toString() != 'No remarks')
                      Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Remarks: ${order['custom_item_remarks']}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 16),

            // Items Section
            Card(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Items',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    // Items list
                    ...items
                        .map(
                          (item) => Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Text(
                                        item['name']?.toString() ?? 'Item',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'x${(item['quantity'] ?? 1).toStringAsFixed(0)}',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  'RM ${((item['price'] ?? 0) * (item['quantity'] ?? 1)).toStringAsFixed(2)}',
                                  style: TextStyle(
                                      color: Color(0xFFE732A0),
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),

            // Summary Section
            Card(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300)),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildSummaryRow('Subtotal', subtotal),
                    if (taxBreakdown != null)
                      _buildSummaryRow(
                        'GST (${taxBreakdown['rate']?.toStringAsFixed(0) ?? '6.0'}%)',
                        tax,
                      ),
                    _buildSummaryRow('Rounding Adjustment', rounding),
                    _buildSummaryRow('Total', total, isTotal: true),
                    if (isPaid) ...[
                      Divider(),
                      _buildSummaryRow('Payment Method',
                          order['paymentMethod']?.toString() ?? 'Cash'),
                      if (order['paymentMethod'] == 'Cash') ...[
                        _buildSummaryRow('Paid Amount',
                            'RM ${order['paidAmount']?.toStringAsFixed(2) ?? order['paidAmount']?.toStringAsFixed(2) ?? '0.00'}'),
                        _buildSummaryRow('Change Amount',
                            'RM ${order['changeAmount']?.toStringAsFixed(2) ?? order['changeAmount']?.toStringAsFixed(2) ?? '0.00'}'),
                      ],
                      if (order['paidTime'] != null)
                        _buildSummaryRow(
                          'Paid Time',
                          _formatDate(_parseDateTime(order['paidTime'])),
                        ),
                    ],
                  ],
                ),
              ),
            ),

            SizedBox(height: 24),

            // Action Buttons
            if (isDraft) ...[
              ElevatedButton(
                onPressed: () => {_goToCheckout(order), _selectedOrder = null},
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 48),
                  backgroundColor: Color(0xFFE732A0),
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  'Checkout Order',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(height: 8),
            ],
            ElevatedButton(
              onPressed: () async {
                final orderName = order['orderId']?.toString();
                if (orderName != null) {
                  await ReceiptPrinter.showPrintDialog(context, orderName);
                }
              },
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 48),
                side: BorderSide(color: Colors.black),
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
              child: Text(
                'Print Receipt',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),

            // Inside _buildOrderDetailsPanel method, after the existing buttons:
            if (!isDraft &&
                !isCancelled) ...[
              SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => _processRefund(order),
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 48),
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  'Refund',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required String label,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12,
                color: Colors.black,
                fontWeight: FontWeight.w600)),
        DropdownButtonFormField<String>(
          value: value,
          items: items.map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value),
            );
          }).toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyDetailsPanel() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 48, color: Colors.grey),
          SizedBox(height: 16),
          Text('Select an order to view details',
              style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, dynamic value, {bool isTotal = false}) {
    String formattedValue;

    if (value is num) {
      formattedValue = 'RM ${value.toStringAsFixed(2)}';
    } else if (value is String) {
      formattedValue = value;
    } else {
      formattedValue = value?.toString() ?? '';
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontWeight: isTotal ? FontWeight.bold : FontWeight.bold,
              )),
          Text(formattedValue,
              style: TextStyle(
                fontWeight: isTotal ? FontWeight.bold : FontWeight.bold,
                color: isTotal ? Color(0xFFE732A0) : Colors.black,
              )),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filterOrders(List<Map<String, dynamic>> orders) {
    return orders.where((order) {
      final statusMatch = _filterStatus == 'All' ||
          (order['status']?.toString().toLowerCase() ==
              _filterStatus.toLowerCase());
      final typeMatch = _filterOrderType == 'All' ||
          (order['orderType']?.toString().toLowerCase() ?? 'dine in') ==
              _filterOrderType.toLowerCase();
      return statusMatch && typeMatch;
    }).toList();
  }

  void _goToCheckout(Map<String, dynamic> order) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CheckoutScreen(
          order: {
            ...order,
            'items': List<Map<String, dynamic>>.from(order['items'] ?? []),
          },
          tablesWithSubmittedOrders: {}, // Pass an empty set if not available
          onOrderSubmitted: (newOrder) {
            // Handle order submission if needed
            widget.onOrderPaid(newOrder);
          },
          onOrderPaid: (tableNumber) {
            // Handle order paid if needed
          },
          activeOrders: widget.orders, // Pass the current orders list
        ),
      ),
    ).then((orderCompleted) {
      if (orderCompleted == true) {
        widget.onOrderPaid(order);
      }
    });
  }

  Future<void> _processRefund(Map<String, dynamic> order) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            title: Text(
              'Confirm Refund',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Text(
              'Are you sure you want to refund this order?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'Cancel',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'Refund',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    try {
      // final posInvoiceNumber = '000502';
      final posInvoiceNumber = order['pos_invoice_number']?.toString();
      print('pos lanjiao: $posInvoiceNumber');

      if (posInvoiceNumber == null || posInvoiceNumber.isEmpty) {
        throw Exception('POS invoice number not available for refund');
      }

      // Generate transaction ID from order ID
      final orderId = order['orderId']?.toString() ?? '';
      final transactionId = 'INV${orderId.replaceAll(RegExp(r'[^0-9]'), '')}'
          .padRight(20, '0')
          .substring(0, 20);

      // Generate the void hex message
      final hexMessage = order['paymentMethod']?.toString().toLowerCase().contains('card') == true
    ? PosHexGenerator.generateVoidHexMessage(
        transactionId: transactionId,
        invoiceNumber: posInvoiceNumber,
      )
      
    : PosHexGenerator.generateVoidWalletQrHexMessage(
        transactionId,
        extendedInvoiceNumber: posInvoiceNumber,
      );


      // Connect to POS terminal
      final prefs = await SharedPreferences.getInstance();
      final posIp = prefs.getString('pos_ip') ?? '192.168.1.10';
      final posPort = 8800;

      final socket = await Socket.connect(posIp, posPort,
          timeout: const Duration(seconds: 10));

      try {
        final response = await _handlePosTransaction(socket, hexMessage);

        if (response['status'] != 'success') {
          throw Exception(
              response['response_text'] ?? 'POS transaction declined');
        }

        // If successful, call the refund API
        final refundResponse =
            await PosService().cancelOrder(order['orderId']?.toString() ?? '');

        if (refundResponse['success'] == true) {
          if (mounted) {
            Fluttertoast.showToast(
              msg: "Refund Successful",
              gravity: ToastGravity.BOTTOM,
              backgroundColor: Colors.green,
              textColor: Colors.white,
            );
            _refreshOrders();
          }
        }
      } finally {
        socket.destroy();
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: "Refund Error: ${e.toString()}",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
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

  List<int> _hexStringToBytes(String hexString) {
    return hexString
        .split(' ')
        .map((hex) => int.parse(hex, radix: 16))
        .toList();
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

      try {
        final asciiData =
            String.fromCharCodes(rawData.where((b) => b >= 32 && b <= 126));

        // 1. Extract main invoice number (INV202500293)
        final invoiceMatch = RegExp(r'INV(\d{9})').firstMatch(asciiData);
        if (invoiceMatch != null) {
          invoiceNumber = invoiceMatch.group(1)!;
          transactionId = 'INV$invoiceNumber';
        }

        // 2. Extract POS invoice number - CORRECTED PATTERN
        // Looks for "65000" followed by exactly 6 digits (the POS invoice number)
        final posInvoiceMatch = RegExp(r'65(\d{6})').firstMatch(asciiData);
        if (posInvoiceMatch != null) {
          posInvoiceNumber =
              posInvoiceMatch.group(1)!; // This will capture "000497"
        }

        // 3. Check approval status
        if (asciiData.contains('APPROVED')) {
          status = 'success';
          responseText = 'APPROVED';
        }
      } catch (e) {
        debugPrint('⚠️ ASCII parsing failed: $e');
      }

      return {
        'invoice_number': invoiceNumber, // "202500293" (correct)
        'pos_invoice_number': posInvoiceNumber,
        'response_text': responseText,
        'status': status,
        'transaction_id': transactionId,
      };
    } catch (e) {
      debugPrint('❌ Decode error: $e');
      return {
        'invoice_number': '000000',
        'pos_invoice_number': '000000',
        'response_text': 'Decode error: ${e.toString()}',
        'status': 'error',
        'transaction_id': 'ERROR_${DateTime.now().millisecondsSinceEpoch}',
      };
    }
  }

  double _calculateOrderSubtotal(Map<String, dynamic> order) {
    final items = (order['items'] as List?) ?? [];
    return items.fold(0.0, (sum, item) {
      final price = (item['price'] as num?)?.toDouble() ?? 0.0;
      final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      return sum + (price * quantity);
    });
  }

  double _calculateOrderTax(Map<String, dynamic> order) {
    // Use server tax value if available
    if (order['total_taxes_and_charges'] != null) {
      return (order['total_taxes_and_charges'] as num).toDouble();
    }

    // Fallback to calculating from tax breakdown
    if (order['taxBreakdown'] != null) {
      return _calculateOrderSubtotal(order) *
          ((order['taxBreakdown']['rate'] as num).toDouble()) /
          100;
    }

    // Default to 6% GST if no tax info available
    return _calculateOrderSubtotal(order) * 0.06;
  }

  double _calculateRounding(double amount) {
    // Use server rounding value if available
    // if (order['base_rounding_adjustment'] != null) {
    //   return (order['base_rounding_adjustment'] as num).toDouble();
    // }

    // Fallback to rounding calculation
    return (amount * 20).round() / 20 - amount;
  }

  double _calculateOrderTotal(Map<String, dynamic> order) {
    // Use server values if available
    if (order['total'] != null) {
      return (order['total'] as num).toDouble();
    }

    // Calculate from components
    final subtotal = _calculateOrderSubtotal(order);
    final tax = _calculateOrderTax(order);
    final rounding = _calculateRounding(subtotal + tax);
    return subtotal + tax + rounding;
  }

  DateTime _parseDateTime(dynamic dateTime) {
    if (dateTime == null) return DateTime.now();
    if (dateTime is DateTime) return dateTime;
    if (dateTime is String) {
      try {
        return DateTime.parse(dateTime);
      } catch (e) {
        return DateTime.now();
      }
    }
    return DateTime.now();
  }

  String _formatDate(DateTime date) {
    return DateFormat('HH:mm, dd MMM').format(date);
  }
}
