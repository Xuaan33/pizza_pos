import 'package:flutter/material.dart';
import 'package:shiok_pos_android_app/components/main_layout.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CheckoutScreen extends StatefulWidget {
  final Map<String, dynamic> order;

  const CheckoutScreen({
    Key? key,
    required this.order,
  }) : super(key: key);

  @override
  _CheckoutScreenState createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String _selectedPaymentMethod = 'Cash';
  List<Map<String, dynamic>> _paymentMethods = [];
  bool _isLoadingPaymentMethods = true;

  @override
  void initState() {
    super.initState();
    _loadPaymentMethods();
  }

  Future<void> _loadPaymentMethods() async {
  try {
    setState(() => _isLoadingPaymentMethods = true);
    final prefs = await SharedPreferences.getInstance();
    final posProfile = prefs.getString('pos_profile');
    if (posProfile == null) throw Exception('POS Profile not set');

    final posService = PosService();
    final response = await posService.getPaymentMethods(posProfile);

    if (response['message'] != null) {
      setState(() {
        _paymentMethods = List<Map<String, dynamic>>.from(response['message']);
        _isLoadingPaymentMethods = false;
        if (_paymentMethods.isNotEmpty) {
          _selectedPaymentMethod = _paymentMethods.first['name'];
        }
      });
    } else {
      throw Exception('No payment methods found');
    }
  } catch (e) {
    setState(() => _isLoadingPaymentMethods = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to load payment methods: ${e.toString()}')),
    );
  }
}

  List<Map<String, dynamic>> get orderItems {
    return List<Map<String, dynamic>>.from(widget.order['items']);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildOrderHeader(),
                          const SizedBox(height: 16),
                          _buildOrderItemsList(),
                          const SizedBox(height: 24),
                          _buildOrderSummary(),
                          const SizedBox(height: 24),
                          _buildPayNowButton(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
          const Text(
            'Welcome back, nicholas',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          _buildStatPill('Revenue', 'RM0.00'),
          const SizedBox(width: 8),
          _buildStatPill('Unpaid Orders', 'RM42.30'),
          const SizedBox(width: 8),
          _buildStatPill('Tables Free', '1'),
        ],
      ),
    );
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
              fontSize: 12,
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
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: _paymentMethods.length,
        itemBuilder: (context, index) {
          final method = _paymentMethods[index];
          final isSelected = _selectedPaymentMethod == method['name'];
          
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedPaymentMethod = method['name'];
              });
            },
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected ? const Color(0xFFE732A0) : Colors.blue.shade300,
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
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? const Color(0xFFE732A0) : Colors.black,
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

  Widget _buildOrderHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Item Name',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const Text(
          'Quantity',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const Text(
          'Price (RM)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const Text(
          'Amount (RM)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
      ],
    );
  }

  Widget _buildOrderItemsList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: orderItems.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = orderItems[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 50,
                height: 50,
                child: Image.network(
                  'https://shiokpos.byondwave.com/item-image.jpg',
                  errorBuilder: (context, error, stackTrace) => 
                    Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.fastfood),
                    ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Text(
                  item['name'],
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
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
                  item['price'].toStringAsFixed(2),
                  textAlign: TextAlign.right,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  (item['price'] * item['quantity']).toStringAsFixed(2),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOrderSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildSummaryRow('Net Total', _calculateSubtotal(), 'RM 35.40'),
          const SizedBox(height: 8),
          _buildSummaryRow('Rounding', _calculateRounding(), 'RM 0.01'),
          const SizedBox(height: 8),
          _buildSummaryRow('GST @ 6.0%', _calculateGST(), 'RM 2.39'),
          const Divider(thickness: 1, height: 24),
          _buildSummaryRow('Grand Total', _calculateTotal(), 'RM 42.30', isTotal: true),
          const SizedBox(height: 8),
          _buildSummaryRow('Change Amount', 0.0, 'RM 0.00', isTotal: true),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, double value, String formattedValue, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 16 : 14,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          formattedValue,
          style: TextStyle(
            fontSize: isTotal ? 18 : 14,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            color: isTotal ? const Color(0xFFE732A0) : Colors.black,
          ),
        ),
      ],
    );
  }

  Widget _buildPayNowButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: () {
          MainLayout.of(context)?.handleOrderPaid(widget.order);
          Navigator.pop(context, true);
          MainLayout.of(context)?.selectOrdersTab();

        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFE732A0),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: const Text(
          'Pay Now',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  double _calculateSubtotal() {
    return orderItems.fold(
        0.0, (sum, item) => sum + (item['price'] * item['quantity']));
  }

  double _calculateGST() {
    return _calculateSubtotal() * 0.06;
  }

  double _calculateRounding() {
    final total = _calculateSubtotal() + _calculateGST();
    return ((total * 100).round() / 100) - total;
  }

  double _calculateTotal() {
    return _calculateSubtotal() + _calculateGST() + _calculateRounding();
  }

  String _formatTime(DateTime time) {
    final hour = time.hour > 12 ? time.hour - 12 : time.hour;
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} $period';
  }
}