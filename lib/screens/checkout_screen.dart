import 'package:flutter/material.dart';
import 'package:shiok_pos_android_app/components/main_layout.dart';
import 'package:shiok_pos_android_app/screens/table_screen.dart';
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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  children: [
                    _buildTableInfo(),
                    _buildOrderItemsHeader(),
                    _buildOrderItemsList(),
                    Divider(color: Colors.pink, thickness: 1),
                    _buildOrderSummary(),
                    Spacer(),
                    _buildPaymentMethods(),
                    SizedBox(height: 16),
                    _buildCompleteOrderButton(),
                    SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Image.asset('assets/logo-shiokpos.png', width: 40, height: 40),
          SizedBox(width: 12),
          Text('Welcome back, Clarence',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Spacer(),
          _buildStatusCard('Revenue', 'RM 888.88'),
          SizedBox(width: 12),
          _buildStatusCard('Unpaid Orders', 'RM 888.88'),
          SizedBox(width: 12),
          _buildStatusCard('Tables Free', '12'),
        ],
      ),
    );
  }

  Widget _buildStatusCard(String title, String value) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          Text(title, style: TextStyle(color: Colors.white, fontSize: 14)),
          SizedBox(width: 8),
          Text(value,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTableInfo() {
  return Row(
    children: [
      _buildInfoChip('Table ${widget.tableNumber}'),
      SizedBox(width: 16),
      _buildInfoChip('Entry Time ${DateTime.now().toString().substring(11, 16)}'),
      Spacer(),
      ElevatedButton(
        onPressed: () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => HomeScreen(
                tableNumber: widget.tableNumber,
                existingOrder: widget.orderItems,
              ),
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
            side: BorderSide(color: Colors.black),
          ),
        ),
        child: Text('Add Items'),
      ),
    ],
  );
}

  Widget _buildInfoChip(String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
          ),
        ],
      ),
      child: Text(text, style: TextStyle(fontSize: 16)),
    );
  }

  Widget _buildOrderItemsHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Item', style: _headerStyle())),
          Expanded(
              flex: 2,
              child: Text('Quantity',
                  textAlign: TextAlign.center, style: _headerStyle())),
          Expanded(
              flex: 2,
              child: Text('Unit Price',
                  textAlign: TextAlign.center, style: _headerStyle())),
          Expanded(
              flex: 2,
              child: Text('Total Price',
                  textAlign: TextAlign.right, style: _headerStyle())),
        ],
      ),
    );
  }

  TextStyle _headerStyle() {
    return TextStyle(fontSize: 16, fontWeight: FontWeight.bold);
  }

  Widget _buildOrderItemsList() {
    return Column(
      children: widget.orderItems.map((item) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                  flex: 3,
                  child: Text(item['name'], style: TextStyle(fontSize: 16))),
              Expanded(
                  flex: 2,
                  child:
                      Text('${item['quantity']}', textAlign: TextAlign.center)),
              Expanded(
                  flex: 2,
                  child:
                      Text('RM ${item['price']}', textAlign: TextAlign.center)),
              Expanded(
                  flex: 2,
                  child: Text(
                      'RM ${(item['price'] * item['quantity']).toStringAsFixed(2)}',
                      textAlign: TextAlign.right)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildOrderSummary() {
    return Column(
      children: [
        _buildSummaryRow('Total', 'RM ${_calculateSubtotal().toStringAsFixed(2)}'),
        _buildSummaryRow('SST (6%)', 'RM ${_calculateSST().toStringAsFixed(2)}'),
        _buildSummaryRow('Service Charge (10%)', 'RM ${_calculateServiceCharge().toStringAsFixed(2)}'),
        _buildSummaryRow('Rounding', 'RM ${_calculateRounding().toStringAsFixed(2)}'),
        _buildSummaryRow('Order Total', 'RM ${_calculateTotal().toStringAsFixed(2)}', isPrimary: true),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value,
      {bool isPrimary = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 16, color: isPrimary ? Colors.pink : Colors.black)),
        Text(value,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isPrimary ? Colors.pink : Colors.black)),
      ],
    );
  }

  // Ensure complete payment properly navigates back
Widget _buildCompleteOrderButton() {
  return ElevatedButton(
    onPressed: () {
      // This will pop back to HomeScreen with true
      Navigator.pop(context, true);
    },
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.pink,
      foregroundColor: Colors.white,
      minimumSize: Size(double.infinity, 50),
    ),
    child: Text('Complete Payment'),
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
    // In the image, SST is shown as 8% instead of 6% from the original code
    return _calculateSubtotal() * 0.06;
  }

  double _calculateServiceCharge() {
    // In the image, it shows service charge as 6% instead of 10%
    return _calculateSubtotal() * 0.10;
  }

  double _calculateRounding() {
    double total =
        _calculateSubtotal() + _calculateSST() + _calculateServiceCharge();
    double rounded = (total * 20).round() / 20;
    return rounded - total;
  }

  double _calculateTotal() {
    return _calculateSubtotal() +
        _calculateSST() +
        _calculateServiceCharge() +
        _calculateRounding();
  }

  Widget _buildPaymentMethods() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _paymentMethods.map((method) {
        final isSelected = _selectedPaymentMethod == method;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ElevatedButton(
            onPressed: () {
              setState(() {
                _selectedPaymentMethod = method;
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isSelected ? Colors.pink : Colors.white,
              foregroundColor: isSelected ? Colors.white : Colors.black,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
                side: BorderSide(
                  color: isSelected ? Colors.pink : Colors.black,
                ),
              ),
            ),
            child: Text(
              method,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}