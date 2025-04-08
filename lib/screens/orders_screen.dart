import 'package:flutter/material.dart';
import 'package:shiok_pos_android_app/components/main_layout.dart';
import 'checkout_screen.dart';

class OrdersScreen extends StatefulWidget {
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
  _OrdersScreenState createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  String _filterStatus = 'All'; // 'All', 'Pending', 'Paid'

  @override
  Widget build(BuildContext context) {
    // Show loading indicator if orders are being fetched
    if (widget.isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    // Filter orders based on status
    final filteredOrders = _filterStatus == 'All'
        ? widget.orders
        : widget.orders
            .where((order) =>
                (_filterStatus == 'Pending' && !order['isPaid']) ||
                (_filterStatus == 'Paid' && order['isPaid']))
            .toList();

    return NotificationListener<ScrollNotification>(
      onNotification: (scrollNotification) {
        if (scrollNotification is ScrollEndNotification &&
            scrollNotification.metrics.extentAfter == 0) {
          widget.onRefresh?.call(); // Trigger refresh when scrolled to top
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () async {
          // Pull-to-refresh functionality
          widget.onRefresh?.call();
        },
        child: CustomScrollView(
          slivers: [
            // Header with filter dropdown
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Orders',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    DropdownButton<String>(
                      value: _filterStatus,
                      items: ['All', 'Pending', 'Paid'].map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (newValue) {
                        setState(() => _filterStatus = newValue!);
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Order list or empty state
            if (filteredOrders.isEmpty)
              SliverFillRemaining(
                  child: Center(
                child: Text(
                  'No ${_filterStatus == 'All' ? '' : _filterStatus} Orders',
                  style: TextStyle(color: Colors.grey),
                ),
              ))
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final order = filteredOrders[index];
                    return _buildOrderCard(
                      order,
                      onPay: () =>
                          widget.onOrderPaid(order), // Add pay callback
                    );
                  },
                  childCount: filteredOrders.length,
                ),
              ),
          ],
        ),
      ),
    );
  }

// Updated order card widget
  // Modify _buildOrderCard to only show Checkout button
Widget _buildOrderCard(Map<String, dynamic> order, {VoidCallback? onPay}) {
  final isPaid = order['isPaid'] ?? false;

  return Card(
    margin: EdgeInsets.all(8),
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          // Header with table number and status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Table ${order['tableNumber']}',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isPaid ? Colors.green[100] : Colors.pink[100],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isPaid ? 'PAID' : 'PENDING',
                  style: TextStyle(
                    color: isPaid ? Colors.green[800] : Colors.pink[800],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          // Order items list
          ...order['items']
              .map((item) => ListTile(
                    title: Text('${item['quantity']}x ${item['name']}'),
                    trailing: Text(
                        'RM ${(item['price'] * item['quantity']).toStringAsFixed(2)}'),
                  ))
              .toList(),

          // Checkout button (only for pending orders)
          if (!isPaid)
            ElevatedButton(
              onPressed: () {
                _goToCheckout(order);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pink,
                foregroundColor: Colors.white,
              ),
              child: Text('Checkout Order'),
            ),
        ],
      ),
    ),
  );
}

// Update _goToCheckout method
void _goToCheckout(Map<String, dynamic> order) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => CheckoutScreen(
        tableNumber: order['tableNumber'],
        orderItems: List.from(order['items']),
      ),
    ),
  ).then((orderCompleted) {
    if (orderCompleted == true) {
      widget.onOrderPaid(order);
    }
  });
}

  Widget _buildTopSection() {
    return const Text(
      'Orders',
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildOrderSummaryRow(String label, double amount,
      {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            'RM ${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  void _editOrder(Map<String, dynamic> order) {
    widget.onEditOrder(order);
  }
}
