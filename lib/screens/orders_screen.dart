import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiok_pos_android_app/components/image_url_helper.dart';
import 'package:shiok_pos_android_app/components/main_layout.dart';
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
  final DateTime selectedDate;
  final int pageLimit;
  final Function(DateTime) onDateChanged;
  final Function(String) onFilterStatusChanged;
  final Function(String) onFilterOrderTypeChanged;
  final String currentFilterStatus;
  final String currentFilterOrderType;
  final Function() onDateRangeSelected;
  final Function() onDateRangeCleared;
  final useDateRange;
  final fromDate;
  final toDate;

  const OrdersScreen({
    Key? key,
    required this.orders,
    required this.onOrderPaid,
    required this.onEditOrder,
    this.onRefresh,
    this.isLoading = false,
    required this.selectedDate,
    required this.pageLimit,
    required this.onDateChanged,
    required this.onFilterStatusChanged,
    required this.onFilterOrderTypeChanged,
    required this.currentFilterStatus,
    required this.currentFilterOrderType,
    required this.onDateRangeSelected,
    required this.onDateRangeCleared,
    required this.useDateRange,
    this.fromDate,
    this.toDate,
  }) : super(key: key);

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  String _searchQuery = '';
  Map<String, dynamic>? _selectedOrder;
  List<Map<String, dynamic>> _paymentMethods = [];
  // ignore: unused_field
  bool _isLoadingPaymentMethods = true;
  String baseImageUrl = '';
  String tier = '';

  @override
  void initState() {
    super.initState();
    // Initial load
    _loadBaseUrl();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshOrders();
    });
    _refreshOrders();
    _loadPaymentMethods();
  }

  Future<void> _loadBaseUrl() async {
    baseImageUrl = await ImageUrlHelper.getBaseImageUrl();
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      tier = prefs.getString('tier') ?? 'tier 1';
      print('CHECK TIER: $tier');
    }); // Refresh UI
  }

  @override
  void didUpdateWidget(OrdersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Schedule refresh for after build phase
    if (oldWidget.selectedDate != widget.selectedDate ||
        oldWidget.pageLimit != widget.pageLimit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshOrders();
      });
    }
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

  Future<void> _refreshOrders() async {
    if (widget.onRefresh != null && mounted) {
      await widget.onRefresh!();
    }
    if (mounted) {
      setState(() {
        _selectedOrder = null;
        // _filterStatus = 'All';
        // _filterOrderType = 'All';
        // _searchQuery = '';
      });
    }
  }

  List<Widget> _buildVariantText(Map<String, dynamic> item) {
    dynamic variantInfo = item['custom_variant_info'];

    if (variantInfo == null) return [];

    // If it's a string, try decode until it becomes a List
    while (variantInfo is String) {
      try {
        variantInfo = jsonDecode(variantInfo);
      } catch (e) {
        debugPrint('Error parsing variant info: $e');
        return [];
      }
    }

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

  @override
  Widget build(BuildContext context) {
    final filteredOrders = _filterOrders(widget.orders);
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
      ) {
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Orders",
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 4),
                        if (widget.useDateRange &&
                            widget.fromDate != null &&
                            widget.toDate != null)
                          Text(
                            '${DateFormat('dd MMM yyyy').format(widget.fromDate!)} - ${DateFormat('dd MMM yyyy').format(widget.toDate!)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          )
                        else if (!widget.useDateRange &&
                            widget.selectedDate != DateTime.now())
                          Text(
                            '${DateFormat('dd MMM yyyy').format(widget.selectedDate)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          )
                        else
                          Text(
                            'All Dates',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600],
                            ),
                          ),

                        // Add a filter status indicator
                        if (widget.currentFilterStatus == 'Pay Later')
                          Text(
                            'Pay Later orders with date filter',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                    Row(
                      children: [
                        // Date Range Button
                        Container(
                          decoration: BoxDecoration(
                            color: widget.useDateRange
                                ? const Color(0xFFE732A0).withOpacity(0.2)
                                : const Color(0xFFE732A0).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: TextButton(
                            onPressed: _selectDateRange,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Date Range',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),

                        SizedBox(width: 8),
                        // Single Date Button
                        Container(
                          decoration: BoxDecoration(
                            color: !widget.useDateRange
                                ? Color(0xFFE732A0).withOpacity(0.2)
                                : Color(0xFFE732A0).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            onPressed: _selectDate,
                            icon: Icon(Icons.calendar_month, size: 24),
                            color: Color(0xFFE732A0),
                            tooltip: 'Select Single Date',
                          ),
                        ),
                        // Show clear/reset button when date filters are active
                        if (widget.useDateRange ||
                            widget.selectedDate == DateTime.now()) ...[
                          SizedBox(width: 8),
                          // Clear/Reset Date Button - This now works for both cases
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: IconButton(
                              onPressed:
                                  _clearDateRange, // This will reset to show all dates for Pay Later
                              icon: Icon(Icons.clear, size: 24),
                              color: Colors.grey,
                              tooltip: 'Clear Date Filter',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 5),

                // Search Bar
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Search Bar (shortened)
                    Expanded(
                      flex: 3,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: TextField(
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search orders...',
                            hintStyle: TextStyle(color: Colors.grey.shade600),
                            prefixIcon:
                                Icon(Icons.search, color: Colors.grey.shade600),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                  ],
                ),

                SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: _buildFilterDropdown(
                        value: widget.currentFilterStatus,
                        items: ['All', 'Pay Later', 'Paid', 'Refunded'],
                        onChanged: (value) =>
                            widget.onFilterStatusChanged(value!),
                        label: 'Status',
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: _buildFilterDropdown(
                        value: widget.currentFilterOrderType,
                        items: ['All', 'Dine in', 'Take Away', 'Delivery'],
                        onChanged: (value) =>
                            widget.onFilterOrderTypeChanged(value!),
                        label: 'Order Type',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 5),
          // Order list with infinite scrolling
          Expanded(
            child: widget.isLoading
                ? Center(child: CircularProgressIndicator())
                : orders.isEmpty
                    ? Center(child: Text('No orders found'))
                    : NotificationListener<ScrollNotification>(
                        onNotification: (scrollNotification) {
                          // This will be handled by the scroll controller in main_layout
                          return false;
                        },
                        child: ListView.builder(
                          controller:
                              MainLayout.of(context)?.ordersScrollController,
                          itemCount:
                              orders.length + 1, // +1 for loading indicator
                          itemBuilder: (context, index) {
                            if (index < orders.length) {
                              return _buildOrderListItem(orders[index]);
                            } else {
                              // Show loading indicator at the bottom
                              return _buildLoadingIndicator();
                            }
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    final mainLayout = MainLayout.of(context);
    if (mainLayout == null ||
        !mainLayout.hasMoreOrders ||
        mainLayout.isLoadingMore == false) {
      return SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: CircularProgressIndicator(),
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
                      isCancelled
                          ? 'REFUNDED'
                          : (isDraft ? 'PAY LATER' : 'PAID'),
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
              SizedBox(height: 4),
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
              SizedBox(height: 8),
              Text(
                'Remarks: ${order['remarks'] != null && order['remarks'].toString().isNotEmpty ? order['remarks'] : 'N/A'}',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

    // Calculate discount amounts
    final orderLevelDiscount =
        (order['discount_amount'] as num?)?.toDouble() ?? 0.0;
    final itemLevelDiscounts = _calculateItemLevelDiscounts(order);
    final totalDiscount =
        orderLevelDiscount > 0 ? orderLevelDiscount : itemLevelDiscounts;

    final items = (order['items'] as List<dynamic>?) ?? [];

    // Calculate original subtotal (before any discounts)
    final originalSubtotal = _calculateOriginalSubtotal(order);

    // Calculate final values with proper negative handling
    final subtotal = (order['net_total'] as num?)?.toDouble() ??
        _calculateOrderSubtotal(order);
    final tax = (order['total_taxes_and_charges'] as num?)?.toDouble() ??
        _calculateOrderTax(order);
    final rounding = (order['base_rounding_adjustment'] as num?)?.toDouble() ??
        _calculateRounding(subtotal + tax);

    // Calculate total with negative value protection
    double total =
        (order['total'] as num?)?.toDouble() ?? (subtotal + tax + rounding);

    // Ensure total is not negative - if negative, set to 0.00
    if (total < 0) {
      total = 0.00;
    }

    // Calculate the actual subtotal to display (original - discount, but not less than 0)
    double displaySubtotal = originalSubtotal;
    if (totalDiscount > originalSubtotal) {
      // If discount exceeds subtotal, show the original subtotal but the effective subtotal becomes 0
      displaySubtotal = originalSubtotal;
    }

    final isPaid = order['isPaid'] == true;

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
                                ? 'REFUNDED'
                                : (isDraft ? 'PAY LATER' : 'PAID'),
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
                        if (tier.toLowerCase() == 'tier 3') ...[
                          if (order['tableNumber'] != null) ...[
                            Text(
                              order['tableNumber'] == 0
                                  ? 'Instant Order'
                                  : '${order['tableNumber']}',
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w600),
                            ),
                          ]
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

                    if (order['remarks'] != null &&
                        order['remarks'].toString().isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Remarks: ${order['remarks'] != null && order['remarks'].toString().isNotEmpty ? order['remarks'] : 'N/A'}',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold),
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
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                item['name'],
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600),
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'x${(item['quantity'] ?? 1).toStringAsFixed(0)}',
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                          if (item['custom_variant_info'] !=
                                              null)
                                            ..._buildVariantText(item),
                                          if (item['custom_serve_later'] ==
                                                  true ||
                                              (item['custom_serve_later']
                                                      is num &&
                                                  item['custom_serve_later'] ==
                                                      1))
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 4),
                                              child: Text(
                                                '● Serve Later',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.blue[700],
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          if (item['custom_item_remarks'] !=
                                                  null &&
                                              item['custom_item_remarks']
                                                  .toString()
                                                  .isNotEmpty)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 4),
                                              child: Text(
                                                'Remarks: ${item['custom_item_remarks']}',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.orange[700],
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: _buildItemPriceColumn(item),
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
                    _buildSummaryRow('Subtotal', displaySubtotal),
                    if (totalDiscount > 0)
                      _buildSummaryRow(
                          _getDiscountLabel(
                              order, totalDiscount, originalSubtotal),
                          -totalDiscount),
                    ..._buildTaxSummaryRows(order),
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

            SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _printLeftoverOrder(order),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 48),
                side: BorderSide(color: Colors.blue),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: Text(
                'Print Leftover Order',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),

            if (!isDraft &&
                !isCancelled &&
                _isToday(_parseDateTime(order['entryTime']))) ...[
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

// Helper method to calculate original subtotal before discounts
  double _calculateOriginalSubtotal(Map<String, dynamic> order) {
    final items = (order['items'] as List?) ?? [];
    final orderLevelDiscount =
        (order['discount_amount'] as num?)?.toDouble() ?? 0.0;

    // Calculate base subtotal from items INCLUDING variant costs
    double baseSubtotal = items.fold(0.0, (sum, item) {
      final quantity = (item['quantity'] ?? 1).toDouble();
      final price = (item['price'] ?? 0).toDouble();
      final variantCost = _calculateVariantCost(item['custom_variant_info']);
      final totalPrice = price + variantCost;
      return sum + (totalPrice * quantity);
    });

    // If there's an order-level discount, return original with variants
    if (orderLevelDiscount > 0) {
      return baseSubtotal;
    }

    // For item-level discounts, calculate original prices with variants
    return items.fold(0.0, (sum, item) {
      final quantity = (item['quantity'] ?? 1).toDouble();
      final currentPrice = (item['price'] ?? 0).toDouble();
      final variantCost = _calculateVariantCost(item['custom_variant_info']);
      final discountAmount =
          (item['discount_amount'] as num?)?.toDouble() ?? 0.0;
      final discountPercentage =
          (item['discount_percentage'] as num?)?.toDouble() ?? 0.0;

      double originalPricePerUnit;

      if (discountAmount > 0) {
        originalPricePerUnit = currentPrice + (discountAmount / quantity);
      } else if (discountPercentage > 0) {
        originalPricePerUnit = currentPrice / (1 - (discountPercentage / 100));
      } else {
        originalPricePerUnit = currentPrice;
      }

      // Add variant cost to the original price
      return sum + ((originalPricePerUnit + variantCost) * quantity);
    });
  }

// Helper method to build item price column with proper original/discounted price display
  List<Widget> _buildItemPriceColumn(Map<String, dynamic> item) {
    final quantity = (item['quantity'] ?? 1).toDouble();
    final basePrice = (item['price'] ?? 0).toDouble();
    final variantCost = _calculateVariantCost(item['custom_variant_info']);
    final totalPricePerItem = basePrice + variantCost;
    final discountAmount = (item['discount_amount'] as num?)?.toDouble() ?? 0.0;
    final discountPercentage =
        (item['discount_percentage'] as num?)?.toDouble() ?? 0.0;

    final itemSubtotal = totalPricePerItem * quantity;

    // Check if this item has any discount
    final hasDiscount = discountAmount > 0 || discountPercentage > 0;

    if (hasDiscount) {
      // Calculate original amount including discount
      double originalAmount;

      if (discountAmount > 0) {
        // For fixed discount: original = current + discount
        originalAmount = itemSubtotal + (discountAmount * quantity);
      } else {
        // For percentage discount: original = current / (1 - percentage/100)
        originalAmount = itemSubtotal / (1 - (discountPercentage / 100));
      }

      return [
        // Show original price with strikethrough
        Text(
          'RM ${originalAmount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 12,
            decoration: TextDecoration.lineThrough,
            color: Colors.grey,
          ),
        ),
        // Show current amount
        Text(
          'RM ${itemSubtotal.toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFFE732A0),
          ),
        ),
        // Show discount details
        if (discountAmount > 0)
          Text(
            'Discount: RM ${(discountAmount * quantity).toStringAsFixed(2)}',
            style: TextStyle(
              color: Colors.green,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        // Show variant cost breakdown if any
        if (variantCost > 0)
          Text(
            '(+RM${variantCost.toStringAsFixed(2)} variant)',
            style: TextStyle(
              color: Colors.blue,
              fontSize: 10,
            ),
          ),
      ];
    } else {
      // No discount, just show the price with variant cost
      return [
        Text(
          'RM ${itemSubtotal.toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFFE732A0),
          ),
        ),
        // Show variant cost breakdown if any
        if (variantCost > 0)
          Text(
            '(+RM${variantCost.toStringAsFixed(2)} variant)',
            style: TextStyle(
              color: Colors.blue,
              fontSize: 10,
            ),
          ),
      ];
    }
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
      // Handle negative values - show as positive with minus sign
      if (value < 0) {
        formattedValue = '- RM ${(-value).toStringAsFixed(2)}';
      } else {
        formattedValue = 'RM ${value.toStringAsFixed(2)}';
      }
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

  double _calculateItemLevelDiscounts(Map<String, dynamic> order) {
    final items = (order['items'] as List?) ?? [];
    return items.fold(0.0, (sum, item) {
      final discount = (item['discount_amount'] as num?)?.toDouble() ?? 0.0;
      return sum + discount;
    });
  }

  List<Map<String, dynamic>> _filterOrders(List<Map<String, dynamic>> orders) {
    final filteredOrders = orders.where((order) {
      // Search filter
      final searchMatch = _searchQuery.isEmpty ||
          (order['orderId']?.toString().toLowerCase() ?? '')
              .contains(_searchQuery.toLowerCase()) ||
          (order['customerName']?.toString().toLowerCase() ?? '')
              .contains(_searchQuery.toLowerCase()) ||
          (order['remarks']?.toString().toLowerCase() ?? '')
              .contains(_searchQuery.toLowerCase());

      // Determine the actual status of the order
      final isCancelled =
          order['status']?.toString().toLowerCase() == 'cancelled';
      final isDraft = !isCancelled &&
          (order['status']?.toString().toLowerCase() == 'draft');

      final String orderStatus;
      if (isCancelled) {
        orderStatus = 'Refunded';
      } else if (isDraft) {
        orderStatus = 'Pay Later';
      } else {
        orderStatus = 'Paid';
      }

      final statusMatch = widget.currentFilterStatus == 'All' ||
          orderStatus.toLowerCase() == widget.currentFilterStatus.toLowerCase();

      final typeMatch = widget.currentFilterOrderType == 'All' ||
          (order['orderType']?.toString().toLowerCase() ?? 'dine in') ==
              widget.currentFilterOrderType.toLowerCase();

      return searchMatch && statusMatch && typeMatch;
    }).toList();

    // Sort orders by entryTime in descending order (most recent first)
    filteredOrders.sort((a, b) {
      final DateTime timeA = _parseDateTime(a['entryTime']);
      final DateTime timeB = _parseDateTime(b['entryTime']);
      return timeB.compareTo(timeA); // Descending order
    });

    return filteredOrders;
  }

  Future<void> _selectDateRange() async {
    // Simply call the parent callback - MainLayout will handle the date selection
    widget.onDateRangeSelected();
  }

// Replace the _clearDateRange method with this:
  void _clearDateRange() {
    // Simply call the parent callback - MainLayout will handle clearing the date range
    widget.onDateRangeCleared();
  }

// Also update the _selectDate method to ensure it works with the new structure:
  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: widget.selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(Duration(days: 0)),
    );

    if (picked != null && picked != widget.selectedDate) {
      // Call parent callback - this will switch to single date mode automatically
      widget.onDateChanged(picked);
    }
  }

  void _goToCheckout(Map<String, dynamic> order) {
    // Safely convert items to the correct type
    final List<dynamic> rawItems = order['items'] ?? [];
    final List<Map<String, dynamic>> formattedItems = [];

    for (var item in rawItems) {
      if (item is Map) {
        // Convert Map<dynamic, dynamic> to Map<String, dynamic>
        final Map<String, dynamic> convertedItem = {};
        item.forEach((key, value) {
          convertedItem[key.toString()] = value;
        });

        // Ensure image URL is properly formatted
        final image = convertedItem['image']?.toString() ?? '';
        if (image.isNotEmpty && !image.startsWith('http')) {
          convertedItem['image'] = '$baseImageUrl$image';
        }

        formattedItems.add(convertedItem);
      }
    }

    final tableFullName = order['tableNumber'];

    print("OIII: ${order['custom_table']}");

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CheckoutScreen(
          order: {
            ...order,
            'items': formattedItems,
            'invoiceNumber': order['orderId'],
            'discount_amount': order['discount_amount'] ?? 0.0,
            'coupon_code': order['coupon_code'],
            'custom_user_voucher': order['custom_user_voucher'],
            'user_voucher_code': order['user_voucher_code'],
            'total_taxes_and_charges': order['total_taxes_and_charges'] ?? 0.0,
            'base_rounding_adjustment':
                order['base_rounding_adjustment'] ?? 0.0,
            'rounded_total': order['rounded_total'] ?? 0.0,
            'tableFullName': tableFullName,
          },
          tablesWithSubmittedOrders: {},
          onOrderSubmitted: (newOrder) {
            widget.onOrderPaid(newOrder);
          },
          onOrderPaid: (tableNumber) {
            // Handle order paid if needed
          },
          activeOrders: widget.orders,
        ),
      ),
    ).then((orderCompleted) {
      if (orderCompleted == true) {
        widget.onOrderPaid(order);
        _refreshOrders();
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
      // Get the payment method from the order
      final paymentMethod = order['paymentMethod']?.toString() ?? 'Cash';

      // Find the corresponding payment method from _paymentMethods to get m1value
      final paymentMethodData = _paymentMethods.firstWhere(
        (method) => method['name'] == paymentMethod,
        orElse: () => {'name': 'Cash', 'custom_fiuu_m1_value': '-1'},
      );

      final m1Value =
          paymentMethodData['custom_fiuu_m1_value']?.toString() ?? '-1';

      // Determine if it's cash payment
      final isCashPayment =
          m1Value == '-1' || paymentMethod.toLowerCase() == 'cash';

      if (isCashPayment) {
        // For cash payments, just cancel the order directly
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
        return;
      }

      final posInvoiceNumber = order['pos_invoice_number']?.toString();
      print('POS Invoice Number: $posInvoiceNumber');
      print('Payment Method: $paymentMethod');
      print('M1 Value: $m1Value');

      if (posInvoiceNumber == null || posInvoiceNumber.isEmpty) {
        throw Exception('POS invoice number not available for refund');
      }

      // Generate transaction ID from order ID
      final orderId = order['orderId']?.toString() ?? '';
      final transactionId = 'INV${orderId.replaceAll(RegExp(r'[^0-9]'), '')}'
          .padRight(20, '0')
          .substring(0, 20);

      String hexMessage;

      // Determine refund type based on m1value
      if (m1Value == '01') {
        // Credit Card - do credit card void
        hexMessage = PosHexGenerator.generateVoidHexMessage(
          transactionId: transactionId,
          invoiceNumber: posInvoiceNumber,
        );
        print('Processing Credit Card refund (m1value: 01)');
      } else {
        // Other payment methods (QR, DuitNow, etc.) - do QR void
        hexMessage = PosHexGenerator.generateVoidWalletQrHexMessage(
          transactionId,
          extendedInvoiceNumber: posInvoiceNumber,
        );
        print('Processing QR/Wallet refund (m1value: $m1Value)');
      }

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

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  double _calculateOrderSubtotal(Map<String, dynamic> order) {
    final items = (order['items'] as List?) ?? [];
    return items.fold(0.0, (sum, item) {
      final price = (item['price'] as num?)?.toDouble() ?? 0.0;
      final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final variantCost = _calculateVariantCost(item['custom_variant_info']);
      final totalPrice = price + variantCost;
      return sum + (totalPrice * quantity);
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
      double total = (order['total'] as num).toDouble();
      // Ensure total is not negative
      return total < 0 ? 0.00 : total;
    }

    // Calculate from components
    final subtotal = _calculateOrderSubtotal(order);
    final tax = _calculateOrderTax(order);
    final rounding = _calculateRounding(subtotal + tax);
    double total = subtotal + tax + rounding;

    // Ensure total is not negative
    return total < 0 ? 0.00 : total;
  }

  double _calculateVariantCost(dynamic variantInfo) {
    if (variantInfo == null) return 0.0;

    double totalVariantCost = 0.0;

    try {
      // Handle case where variantInfo is a JSON string
      dynamic parsedVariant = variantInfo;
      if (variantInfo is String) {
        try {
          parsedVariant = jsonDecode(variantInfo);
        } catch (e) {
          debugPrint('Error parsing variant info: $e');
          return 0.0;
        }
      }

      // Handle case where variantInfo is a List (new format)
      if (parsedVariant is List) {
        for (var variant in parsedVariant) {
          if (variant is Map && variant['options'] is List) {
            for (var option in variant['options']) {
              if (option is Map) {
                final additionalCost =
                    (option['additional_cost'] as num?)?.toDouble() ?? 0.0;
                totalVariantCost += additionalCost;
              }
            }
          }
        }
      }

      // Handle case where variantInfo is a Map (old format)
      if (parsedVariant is Map) {
        debugPrint('Old variant format detected: $parsedVariant');
      }
    } catch (e) {
      debugPrint('Error calculating variant cost: $e');
    }

    return totalVariantCost;
  }

  List<Widget> _buildTaxSummaryRows(Map<String, dynamic> order) {
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
          ) {
            // Filter out taxes with 0% rate
            final applicableTaxes = taxes.where((tax) {
              final rate = (tax['rate'] ?? 0.0).toDouble();
              return rate > 0;
            }).toList();

            if (applicableTaxes.isEmpty) {
              return <Widget>[SizedBox.shrink()];
            }

            // Get discount and subtotal for tax calculation
            final orderLevelDiscount =
                (order['discount_amount'] as num?)?.toDouble() ?? 0.0;
            final itemLevelDiscounts = _calculateItemLevelDiscounts(order);
            final totalDiscount = orderLevelDiscount > 0
                ? orderLevelDiscount
                : itemLevelDiscounts;

            final originalSubtotal = _calculateOriginalSubtotal(order);
            final taxableAmount = originalSubtotal - totalDiscount;

            List<Widget> taxRows = [];

            for (var tax in applicableTaxes) {
              final taxName = tax['description'] ?? 'Tax';
              final taxRate = (tax['rate'] ?? 0.0).toDouble();
              final taxAmount = taxableAmount * (taxRate / 100);

              taxRows.add(_buildSummaryRow(
                '$taxName (${taxRate.toStringAsFixed(1)}%)',
                taxAmount,
              ));
            }

            return taxRows;
          },
        ) ??
        [SizedBox.shrink()];
  }

  String _getDiscountLabel(Map<String, dynamic> order, double totalDiscount,
      double originalSubtotal) {
    final voucherCode = order['user_voucher_code']?.toString();

    // If there's a voucher code, display it
    if (voucherCode != null && voucherCode.isNotEmpty) {
      return 'Discount Amount ($voucherCode)';
    }

    // If no voucher code, calculate and display the percentage
    if (originalSubtotal > 0) {
      final discountPercentage =
          (totalDiscount / originalSubtotal * 100).toDouble();
      return 'Discount Amount (${discountPercentage.toStringAsFixed(2)}%)';
    }

    // Fallback if we can't calculate percentage
    return 'Discount Amount';
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
    return DateFormat('HH:mm, dd MMM yyyy').format(date);
  }

  Future<void> _printLeftoverOrder(Map<String, dynamic> order) async {
    final orderName = order['orderId']?.toString();
    if (orderName == null) {
      Fluttertoast.showToast(
        msg: "Order ID not found",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    // Show loading indicator
    bool isLoading = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          content: Center(
            child: Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Checking for leftover orders...',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      // Call the kitchen order print function
      await ReceiptPrinter.printKitchenOrderOnly(orderName);

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
        isLoading = false;
      }

      Fluttertoast.showToast(
        msg: "Leftover kitchen order printed successfully",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );
    } catch (e) {
      // Close loading dialog if still mounted
      if (mounted && isLoading) {
        Navigator.of(context).pop();
        isLoading = false;
      }

      // Handle specific error cases
      String errorMessage;
      Color backgroundColor;
      String errorString = e.toString();

      // Check for "No additional items to print" error - SPECIFIC HANDLING
      if (errorString.contains('No additional items to print') ||
          errorString.contains('"success":false') &&
              errorString.contains('No additional items')) {
        errorMessage = "There is no leftover kitchen order to print";
        backgroundColor = Colors.orange;
      }
      // Check for other "no leftover" related errors
      else if (errorString.contains('No kitchen order') ||
          errorString.contains('leftover') &&
              errorString.contains('not found') ||
          errorString.contains('400') &&
              errorString.contains('No additional items')) {
        errorMessage = "There is no leftover kitchen order to print";
        backgroundColor = Colors.orange;
      }
      // Check for network errors
      else if (errorString.toLowerCase().contains('network') ||
          errorString.toLowerCase().contains('connection') ||
          errorString.toLowerCase().contains('timeout') ||
          errorString.toLowerCase().contains('socket')) {
        errorMessage = "Network error: Please check your connection";
        backgroundColor = Colors.red;
      }
      // Check for printer errors
      else if (errorString.toLowerCase().contains('printer') ||
          errorString.toLowerCase().contains('print')) {
        errorMessage = "Printer error: Please check printer connection";
        backgroundColor = Colors.red;
      }
      // Check for HTTP 400 errors specifically for no leftover orders
      else if (errorString.contains('HTTP 400') &&
          errorString.contains('No additional items')) {
        errorMessage = "There is no leftover kitchen order to print";
        backgroundColor = Colors.orange;
      }
      // Generic error
      else {
        errorMessage = "Failed to print leftover order";
        backgroundColor = Colors.red;
      }

      if (mounted) {
        Fluttertoast.showToast(
          msg: errorMessage,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: backgroundColor,
          textColor: Colors.white,
        );
      }
    }
  }
}
