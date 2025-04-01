import 'package:flutter/material.dart';
import 'home_screen.dart';

class CheckoutScreen extends StatefulWidget {
  final int tableNumber;
  final List<Map<String, dynamic>> orderItems;
  
  const CheckoutScreen({
    Key? key, 
    required this.tableNumber,
    required this.orderItems,
  }) : super(key: key);

  @override
  _CheckoutScreenState createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String _selectedPaymentMethod = 'Cash';
  final List<String> _paymentMethods = ['Cash', 'Card', 'QR Pay', 'Split Bill'];
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          color: Colors.grey[100],
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Navigation bar
              _buildNavBar(),
              
              const SizedBox(height: 20),
              
              // Order details card
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      // Table and time info
                      _buildTableInfo(),
                      
                      // Order items header
                      _buildOrderItemsHeader(),
                      
                      // Order items list
                      Expanded(
                        child: _buildOrderItemsList(),
                      ),
                      
                      // Order summary
                      _buildOrderSummary(),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Bottom payment methods and complete order button
              _buildBottomActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavBar() {
    return Row(
      children: [
        GestureDetector(
          onTap: () {
            Navigator.pop(context);
          },
          child: Row(
            children: [
              const Icon(Icons.home, size: 20),
              const SizedBox(width: 5),
              Text(
                'Home Screen',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
              const Icon(Icons.chevron_right, size: 20),
              const Text(
                'Tables',
                style: TextStyle(
                  color: Colors.black,
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

  Widget _buildTableInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                'Table ${widget.tableNumber}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Text(
                'Entry Time',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(width: 10),
              Text(
                '${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')} ${DateTime.now().hour >= 12 ? 'pm' : 'am'}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 20),
              ElevatedButton(
                onPressed: () {
                  // Navigate back to HomeScreen to add more items
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HomeScreen(
                        tableNumber: widget.tableNumber,
                        existingOrder: widget.orderItems,
                      ),
                    ),
                  ).then((updatedOrderItems) {
                    if (updatedOrderItems != null) {
                      setState(() {
                        // If this returns null, it means the user just went back without changes
                      });
                    }
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  side: const BorderSide(color: Colors.grey),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('Add Items'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItemsHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: const Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              'Item',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              'Quantity',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Unit Price',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Total Price',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItemsList() {
    return ListView.builder(
      itemCount: widget.orderItems.length,
      itemBuilder: (context, index) {
        final item = widget.orderItems[index];
        final totalItemPrice = item['price'] * item['quantity'];
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey[200]!),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(item['name']),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  '${item['quantity']}',
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'RM ${item['price'].toStringAsFixed(2)}',
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'RM${totalItemPrice.toStringAsFixed(2)}',
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  double _calculateSubtotal() {
    double subtotal = 0;
    for (var item in widget.orderItems) {
      subtotal += (item['price'] * item['quantity']);
    }
    return subtotal;
  }

  double _calculateSST() {
    return _calculateSubtotal() * 0.06; // 6% of subtotal
  }

  double _calculateServiceCharge() {
    return _calculateSubtotal() * 0.10; // 10% of subtotal
  }

  double _calculateRounding() {
    // Round to nearest 0.05
    double total = _calculateSubtotal() + _calculateSST() + _calculateServiceCharge();
    double rounded = (total * 20).round() / 20;
    return rounded - total;
  }

  double _calculateTotal() {
    return _calculateSubtotal() + _calculateSST() + _calculateServiceCharge() + _calculateRounding();
  }

  Widget _buildOrderSummary() {
    final subtotal = _calculateSubtotal();
    final sst = _calculateSST();
    final serviceCharge = _calculateServiceCharge();
    final rounding = _calculateRounding();
    final total = _calculateTotal();
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Column(
        children: [
          _buildSummaryRow('Total', 'RM ${subtotal.toStringAsFixed(2)}'),
          _buildSummaryRow('SST (6%)', 'RM ${sst.toStringAsFixed(2)}'),
          _buildSummaryRow('Service Charge (10%)', 'RM ${serviceCharge.toStringAsFixed(2)}'),
          _buildSummaryRow('Rounding', 'RM ${rounding.toStringAsFixed(2)}'),
          const SizedBox(height: 8),
          _buildSummaryRow(
            'Order Total', 
            'RM ${total.toStringAsFixed(2)}', 
            isPrimary: true
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isPrimary = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isPrimary ? FontWeight.bold : FontWeight.normal,
              color: isPrimary ? Colors.pink : Colors.black,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isPrimary ? FontWeight.bold : FontWeight.normal,
              color: isPrimary ? Colors.pink : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return Row(
      children: [
        // Payment methods
        Expanded(
          child: Row(
            children: _paymentMethods.map((method) {
              final isSelected = _selectedPaymentMethod == method;
              
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _selectedPaymentMethod = method;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSelected ? Colors.pink : Colors.white,
                    foregroundColor: isSelected ? Colors.white : Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  child: Text(method),
                ),
              );
            }).toList(),
          ),
        ),
        
        const SizedBox(width: 16),
        
        // Complete order button
        SizedBox(
          width: 180,
          child: ElevatedButton(
            onPressed: () {
              // Process the order
              // Show success message
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Order completed successfully!'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
              
              // Add a small delay to allow the snackbar to be visible
              Future.delayed(const Duration(milliseconds: 500), () {
                // Navigate back through both screens to table screen
                Navigator.pop(context, true); // true indicates order completed
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
            ),
            child: const Text('Complete Order'),
          ),
        ),
      ],
    );
  }
}