import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';

class SplitOrderPaymentDialog extends StatefulWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> paymentMethods;
  final VoidCallback onPaymentComplete;
  final VoidCallback onCancel;

  const SplitOrderPaymentDialog({
    required this.order,
    required this.paymentMethods,
    required this.onPaymentComplete,
    required this.onCancel,
  });

  @override
  _SplitOrderPaymentDialogState createState() =>
      _SplitOrderPaymentDialogState();
}

class _SplitOrderPaymentDialogState extends State<SplitOrderPaymentDialog> {
  String _selectedPaymentMethod = '';
  double _amountGiven = 0.0;
  bool _isProcessingPayment = false;

  @override
  Widget build(BuildContext context) {
    final items = List<Map<String, dynamic>>.from(widget.order['items'] ?? []);
    final subtotal = items
        .fold<num>(
          0,
          (sum, item) => sum + (_getItemPrice(item) * _getItemQty(item)),
        )
        .toDouble();
    final gst = subtotal * 0.06;
    final total = subtotal + gst; // don't round away cents here

    return Container(
      width: MediaQuery.of(context).size.width * 0.8,
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Split Order Payment',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),

          // Order items
          Container(
            height: 200,
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  leading: Image.network(
                    '${item['image']}',
                    width: 40,
                    height: 40,
                    errorBuilder: (_, __, ___) => Icon(Icons.fastfood),
                  ),
                  title: Text(item['name']),
                  trailing: Text(
                    'x${_getItemQty(item)} - RM${(_getItemPrice(item) * _getItemQty(item)).toStringAsFixed(2)}',
                  ),
                );
              },
            ),
          ),

          Divider(),

          // Order summary
          _buildSummaryRow('Subtotal', subtotal),
          _buildSummaryRow('GST (6%)', gst),
          _buildSummaryRow('Total', total, isTotal: true),

          SizedBox(height: 16),

          // Payment method selection
          Text('Select Payment Method',
              style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.paymentMethods.map((method) {
              final isSelected = _selectedPaymentMethod == method['name'];
              return ChoiceChip(
                label: Text(method['name']),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _selectedPaymentMethod = method['name']);
                  }
                },
              );
            }).toList(),
          ),

          SizedBox(height: 16),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton(
                onPressed: widget.onCancel,
                child: Text('Cancel Split'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              ),
              ElevatedButton(
                onPressed:
                    _selectedPaymentMethod.isEmpty ? null : _processPayment,
                child: _isProcessingPayment
                    ? CircularProgressIndicator(color: Colors.white)
                    : Text('Pay Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFE732A0),
                  disabledBackgroundColor: Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, double value, {bool isTotal = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              )),
          Text('RM${value.toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                color: isTotal ? Color(0xFFE732A0) : Colors.black,
              )),
        ],
      ),
    );
  }

  Future<void> _processPayment() async {
    setState(() => _isProcessingPayment = true);

    try {
      final total = widget.order['rounded_total']?.toDouble() ??
          (widget.order['grand_total']?.toDouble() ?? 0.0);

      final payments = [
        {
          'mode_of_payment': _selectedPaymentMethod,
          'amount': _selectedPaymentMethod == 'Cash' ? _amountGiven : total,
          'reference_no':
              '${_selectedPaymentMethod}-${DateTime.now().millisecondsSinceEpoch}',
        }
      ];

      final response = await PosService().checkoutOrder(
        invoiceName: widget.order['name'],
        payments: payments,
      );

      if (response['success'] == true) {
        widget.onPaymentComplete();
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Payment failed: ${e.toString()}",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      setState(() => _isProcessingPayment = false);
    }
  }

  num _getItemQty(Map<String, dynamic> item) {
    final q = item['quantity'] ?? item['qty'] ?? 0;
    if (q is num) return q;
    if (q is String) return num.tryParse(q) ?? 0;
    return 0;
  }

  num _getItemPrice(Map<String, dynamic> item) {
    final p = item['price'] ?? item['price_list_rate'] ?? 0;
    if (p is num) return p;
    if (p is String) return num.tryParse(p) ?? 0;
    return 0;
  }
}
