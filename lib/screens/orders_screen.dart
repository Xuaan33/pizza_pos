import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/screens/checkout_screen.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> orders;
  final Function(Map<String, dynamic>) onOrderPaid;
  final Function(Map<String, dynamic>) onEditOrder;
  final VoidCallback? onRefresh;
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
  Widget build(BuildContext context) {
    final filteredOrders = _filterOrders(widget.orders);
    final authState = ref.watch(authProvider);

    return authState.when(
        initial: () => const Center(child: CircularProgressIndicator()),
        unauthenticated: () => const Center(child: Text('Unauthorized')),
        authenticated: (sid, apiKey, apiSecret, username, email, fullName,
            posProfile, branch) {
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
        });
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
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                    : ListView.builder(
                        itemCount: orders.length,
                        itemBuilder: (context, index) {
                          return _buildOrderListItem(orders[index]);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilter() {
    return DropdownButton<String>(
      value: _filterStatus,
      items: ['All', 'Draft', 'Paid'].map((String value) {
        return DropdownMenuItem<String>(
          value: value,
          child: Text(value),
        );
      }).toList(),
      onChanged: (value) => setState(() => _filterStatus = value!),
      underline: Container(),
      style: TextStyle(fontSize: 14),
    );
  }

  Widget _buildOrderTypeFilter() {
    return DropdownButton<String>(
      value: _filterOrderType,
      items: ['All', 'Dine in', 'Takeaway', 'Delivery'].map((String value) {
        return DropdownMenuItem<String>(
          value: value,
          child: Text(value),
        );
      }).toList(),
      onChanged: (value) => setState(() => _filterOrderType = value!),
      underline: Container(),
      style: TextStyle(fontSize: 14),
    );
  }

  Widget _buildOrderListItem(Map<String, dynamic> order) {
    final isSelected = _selectedOrder != null &&
        _selectedOrder!['orderId'] == order['orderId'];
    final isDraft = order['status'] == 'Draft';
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
                    order['orderId'] ?? 'ORDER-00',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDraft ? Colors.blue[100] : Colors.green[100],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isDraft ? 'DRAFT' : 'PAID',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDraft ? Colors.blue[800] : Colors.green[800],
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
                    _formatDate(order['entryTime'] ?? DateTime.now()),
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
    final isDraft = order['status'] == 'Draft';
    final items = order['items'] as List<dynamic>;
    final subtotal = _calculateOrderSubtotal(order);
    final tax = _calculateOrderTax(order);
    final rounding = _calculateRounding(subtotal + tax);
    final total = subtotal + tax + rounding;

    return SingleChildScrollView(
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Order Details',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDraft ? Colors.blue[100] : Colors.green[100],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isDraft ? 'DRAFT' : 'PAID',
                          style: TextStyle(
                            color:
                                isDraft ? Colors.blue[800] : Colors.green[800],
                            fontWeight: FontWeight.w600,
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
                        order['orderId'] ?? 'ORDER-00',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'RM ${total.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE732A0),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),

                  // Second row - Order Type and Table
                  Row(
                    children: [
                      Text(
                        order['orderType'] ?? 'Dine in',
                        style: TextStyle(
                            color: Colors.black, fontWeight: FontWeight.w600),
                      ),
                      if (order['tableNumber'] != null) ...[
                        SizedBox(width: 16),
                        Text(
                          'Table ${order['tableNumber']}',
                          style: TextStyle(
                              color: Colors.black, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 8),

                  // Third row - Date
                  Text(
                    _formatDate(order['entryTime'] ?? DateTime.now()),
                    style: TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
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
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  ...items
                      .map((item) => Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item['name'] ?? 'Item',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Text('x${item['quantity'] ?? 1}'),
                                SizedBox(width: 16),
                                Text(
                                  'RM ${(item['price'] * (item['quantity'] ?? 1)).toStringAsFixed(2)}',
                                  style: TextStyle(
                                      color: Color(0xFFE732A0),
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ))
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Summary',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  _buildSummaryRow('Net Total', subtotal),
                  _buildSummaryRow('Rounding', rounding),
                  _buildSummaryRow('GST @ 6%', tax),
                  Divider(height: 16),
                  _buildSummaryRow('Grand Total', total, isTotal: true),
                  SizedBox(height: 8),
                  _buildSummaryRow('Change Amount', 0.0),
                ],
              ),
            ),
          ),
          SizedBox(height: 24),

          // Action Buttons
          if (isDraft) ...[
            ElevatedButton(
              onPressed: () => _goToCheckout(order),
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
          OutlinedButton(
            onPressed: () {}, // Print receipt function
            style: OutlinedButton.styleFrom(
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
        ],
      ),
    );
  }

  Widget _buildOrderItemRow(Map<String, dynamic> item) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item['name'] ?? 'Item',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            'x${item['quantity'] ?? 1}',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          SizedBox(width: 16),
          Text(
            'RM ${(item['price'] * (item['quantity'] ?? 1)).toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFFE732A0),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCompactDate(DateTime date) {
    return DateFormat('HH:mm, dd MMM').format(date);
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

  Widget _buildSummaryRow(String label, double amount, {bool isTotal = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          Text('RM ${amount.toStringAsFixed(2)}',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
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
            'items': List<Map<String, dynamic>>.from(
                order['items']), // Explicit type
          },
        ),
      ),
    ).then((orderCompleted) {
      if (orderCompleted == true) {
        widget.onOrderPaid(order);
      }
    });
  }

  double _calculateOrderSubtotal(Map<String, dynamic> order) {
    return (order['items'] as List).fold(0.0, (sum, item) {
      return sum + (item['price'] ?? 0) * (item['quantity'] ?? 1);
    });
  }

  double _calculateOrderTax(Map<String, dynamic> order) {
    return _calculateOrderSubtotal(order) * 0.06; // 6% GST
  }

  double _calculateOrderTotal(Map<String, dynamic> order) {
    return _calculateOrderSubtotal(order) + _calculateOrderTax(order);
  }

  String _formatDate(DateTime date) {
    return DateFormat('HH:mm, dd MMM').format(date);
  }

  double _calculateRounding(double amount) {
    // Round to nearest 0.05
    return (amount * 20).round() / 20 - amount;
  }
}
