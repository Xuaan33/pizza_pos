import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shiok_pos_android_app/components/pos_hex_generator.dart';
import 'package:shiok_pos_android_app/components/receipt_printer.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplitOrderPaymentDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> paymentMethods;
  final VoidCallback onPaymentComplete;
  final VoidCallback onCancel;
  final Function() onPaymentFailed;

  const SplitOrderPaymentDialog({
    Key? key,
    required this.order,
    required this.paymentMethods,
    required this.onPaymentComplete,
    required this.onCancel,
    required this.onPaymentFailed,
  }) : super(key: key);

  @override
  ConsumerState<SplitOrderPaymentDialog> createState() =>
      _SplitOrderPaymentDialogState();
}

class _SplitOrderPaymentDialogState
    extends ConsumerState<SplitOrderPaymentDialog> {
  String _selectedPaymentMethod = '';
  double _amountGiven = 0.0;
  bool _isProcessingPayment = false;
  bool _isCashPayment = false;
  String baseImageUrl = 'http://shiokpos.byondwave.com';
  bool _isDeletingOrder = false;
  bool _isLoading = true;
  Map<String, dynamic> _orderDetails = {};

  @override
  void initState() {
    super.initState();
    _fetchOrderDetails();
  }

  Future<void> _fetchOrderDetails() async {
    try {
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
                      hasOpening,
                      tier) {
                    return posProfile;
                  },
                  orElse: () => null,
                ) ??
            '',
        search: widget.order['name'],
      );

      if (response['message']?['success'] == true) {
        final invoices = response['message']?['message'] ?? [];
        if (invoices.isNotEmpty) {
          setState(() {
            _orderDetails = invoices.first;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        Fluttertoast.showToast(
          msg: 'Failed to fetch order details: $e',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Dialog(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Loading order details...'),
            ],
          ),
        ),
      );
    }

    final items = List<Map<String, dynamic>>.from(widget.order['items'] ?? []);

    final isCashPayment = _selectedPaymentMethod == 'Cash';
    final paidAmount = isCashPayment
        ? _amountGiven
        : (_orderDetails['rounded_total'] ?? 0).toDouble();
    final changeAmount = isCashPayment
        ? _amountGiven - (_orderDetails['rounded_total'] ?? 0).toDouble()
        : 0.0;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Header
              Row(
                children: const [
                  Icon(Icons.receipt, size: 30, color: Color(0xFFE732A0)),
                  SizedBox(width: 10),
                  Text(
                    'Split Order Payment',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE732A0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Body Scrollable Content
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Item List
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final price =
                              (item['price'] ?? item['price_list_rate'] ?? 0)
                                  .toDouble();
                          final quantity =
                              (item['quantity'] ?? item['qty'] ?? 1).toDouble();
                          final totalPrice = price * quantity;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    item['image'] != null
                                        ? '$baseImageUrl${item['image']}'
                                        : '$baseImageUrl${item['image']}',
                                    width: 50,
                                    height: 50,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Image.asset(
                                      'assets/pizza.png',
                                      width: 50,
                                      height: 50,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['item_name'] ??
                                            item['name'] ??
                                            'Unknown Item',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      if (item['custom_variant_info'] != null)
                                        ..._buildVariantText(item),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'RM${price.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      'x${quantity.toStringAsFixed(0)}',
                                      style: TextStyle(
                                          color: Colors.grey.shade600),
                                    ),
                                    Text(
                                      'RM${totalPrice.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFE732A0),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      // Summary
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            _buildSummaryRow('Net Total',
                                (_orderDetails['total'] ?? 0).toDouble()),
                            if ((_orderDetails['discount_amount'] ?? 0) > 0)
                              _buildSummaryRow(
                                'Discount',
                                -(_orderDetails['discount_amount'] ?? 0)
                                    .toDouble(),
                              ),
                            _buildSummaryRow(
                                'Rounding',
                                (_orderDetails['base_rounding_adjustment'] ?? 0)
                                    .toDouble()),
                            _buildSummaryRow(
                                'GST (6%)',
                                ((_orderDetails['total_taxes_and_charges'] ??
                                            0) -
                                        (_orderDetails['discount_amount'] ?? 0))
                                    .toDouble()),
                            const Divider(height: 24),
                            _buildSummaryRow(
                                'Grand Total',
                                (_orderDetails['rounded_total'] ?? 0)
                                    .toDouble(),
                                isTotal: true),
                            const SizedBox(height: 8),
                            if (isCashPayment) ...[
                              _buildSummaryRow('Amount Given', _amountGiven),
                              _buildSummaryRow('Change Amount', changeAmount,
                                  isTotal: true),
                            ] else
                              _buildSummaryRow(
                                'Payment Method',
                                _selectedPaymentMethod,
                                isTotal: true,
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Payment method chips
                      Align(
                        alignment: Alignment.center,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Select Payment Method',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: widget.paymentMethods.map((method) {
                                final isSelected =
                                    _selectedPaymentMethod == method['name'];
                                return ChoiceChip(
                                  label: Text(method['name']),
                                  selected: isSelected,
                                  onSelected: (selected) async {
                                    if (selected) {
                                      if (method['name'] == 'Cash') {
                                        final totalAmount =
                                            (_orderDetails['rounded_total'] ??
                                                    0)
                                                .toDouble();
                                        final confirmed =
                                            await _showCashPaymentDialog(
                                                totalAmount);
                                        if (confirmed) {
                                          setState(() {
                                            _selectedPaymentMethod =
                                                method['name'];
                                            _isCashPayment = true;
                                          });
                                        }
                                      } else {
                                        setState(() {
                                          _selectedPaymentMethod =
                                              method['name'];
                                          _isCashPayment = false;
                                        });
                                      }
                                    } else {
                                      setState(() {
                                        _selectedPaymentMethod = '';
                                        _isCashPayment = false;
                                      });
                                    }
                                  },
                                  backgroundColor: Colors.white,
                                  selectedColor: const Color(0xFFE732A0),
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    side: BorderSide(
                                      color: isSelected
                                          ? const Color(0xFFE732A0)
                                          : Colors.grey,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isDeletingOrder ? null : _deleteSplitOrder,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isDeletingOrder ? Colors.grey : Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isDeletingOrder
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Cancel Split',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _selectedPaymentMethod.isEmpty
                          ? null
                          : _processPayment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedPaymentMethod.isEmpty
                            ? Colors.grey
                            : const Color(0xFFE732A0),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isProcessingPayment
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Pay Now',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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

  Widget _buildSummaryRow(String label, dynamic value, {bool isTotal = false}) {
    String formattedValue;

    if (value == null) {
      formattedValue = '';
    } else if (value is num) {
      formattedValue = 'RM ${value.toStringAsFixed(2)}';
    } else {
      formattedValue = value.toString();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.bold,
            ),
          ),
          Text(
            formattedValue,
            style: TextStyle(
              fontSize: 18,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.bold,
              color: isTotal ? const Color(0xFFE732A0) : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _showCashPaymentDialog(double totalAmount) async {
    final amountController = TextEditingController();
    double currentAmount = 0.0;

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return Dialog(
              backgroundColor: Colors.white,
              insetPadding: EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: 500),
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Cash Payment',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Total Amount: RM${totalAmount.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 20),
                      TextField(
                        controller: amountController,
                        decoration: InputDecoration(
                          labelText: 'Amount Received',
                          labelStyle: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                          prefixText: 'RM ',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              vertical: 15, horizontal: 15),
                        ),
                        style: TextStyle(fontSize: 18),
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true),
                        onChanged: (value) {
                          currentAmount = double.tryParse(value) ?? 0.0;
                        },
                      ),
                      SizedBox(height: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [1, 5, 10, 20].map((amount) {
                                return Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4.0),
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: Size(80, 60),
                                        textStyle: TextStyle(
                                            fontSize: 18, color: Colors.black),
                                      ),
                                      onPressed: () {
                                        currentAmount += amount;
                                        amountController.text =
                                            currentAmount.toStringAsFixed(2);
                                      },
                                      child: Text('RM$amount',
                                          style: TextStyle(
                                              color: Colors.black,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          SizedBox(height: 12),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12.0),
                            child: Row(
                              children: [
                                for (var label in ['RM50', 'RM100', 'Clear'])
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4.0),
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          minimumSize: Size(80, 60),
                                          textStyle: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold),
                                        ),
                                        onPressed: () {
                                          if (label == 'Clear') {
                                            currentAmount = 0.0;
                                            amountController.clear();
                                          } else {
                                            final add = int.parse(
                                                label.replaceAll('RM', ''));
                                            currentAmount += add;
                                            amountController.text =
                                                currentAmount
                                                    .toStringAsFixed(2);
                                          }
                                        },
                                        child: Text(label,
                                            style:
                                                TextStyle(color: Colors.black)),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(height: 30),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 30.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                      minimumSize: Size(120, 50),
                                      textStyle: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    child: Text('Cancel',
                                        style: TextStyle(color: Colors.black)),
                                  ),
                                ),
                                SizedBox(width: 20),
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: Size(120, 50),
                                      backgroundColor: Color(0xFFE732A0),
                                      textStyle: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    onPressed: () {
                                      if (currentAmount >= totalAmount) {
                                        setState(() {
                                          _amountGiven = currentAmount;
                                        });
                                        Navigator.of(context).pop(true);
                                      } else {
                                        Fluttertoast.showToast(
                                          msg:
                                              "Amount received is less than total amount",
                                          gravity: ToastGravity.BOTTOM,
                                          backgroundColor: Colors.red,
                                          textColor: Colors.white,
                                        );
                                      }
                                    },
                                    child: Text('OK',
                                        style: TextStyle(color: Colors.white)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            );
          },
        ) ??
        false;
  }

  Future<void> _processPayment() async {
    setState(() => _isProcessingPayment = true);

    try {
      final items =
          List<Map<String, dynamic>>.from(widget.order['items'] ?? []);
      final subtotal = items.fold<double>(
          0,
          (sum, item) =>
              sum +
              ((item['price'] ?? item['price_list_rate'] ?? 0).toDouble() *
                  (item['quantity'] ?? item['qty'] ?? 1).toDouble()));
      final gst = subtotal * 0.06;
      final total = (_orderDetails['rounded_total'] ?? 0).toDouble();

      // Prepare payment data
      final payments = [
        {
          'mode_of_payment': _selectedPaymentMethod,
          'amount': _isCashPayment ? _amountGiven : total,
          if (_selectedPaymentMethod == 'Cash')
            'reference_no': 'CASH-${DateTime.now().millisecondsSinceEpoch}',
        }
      ];

      // Handle non-cash payments (TNG, DuitNow, Credit Card)
      if (!_isCashPayment) {
        // Get the selected payment method's m1 value
        final selectedMethod = widget.paymentMethods.firstWhere(
          (method) => method['name'] == _selectedPaymentMethod,
          orElse: () => {'custom_fiuu_m1_value': '01'},
        );
        final m1Value =
            selectedMethod['custom_fiuu_m1_value']?.toString() ?? '01';

        // Generate the purchase hex message
        final transactionId =
            'INV${widget.order['name'].replaceAll(RegExp(r'[^0-9]'), '')}';
        final paddedTransactionId =
            transactionId.padRight(20, '0').substring(0, 20);
        final hexMessage = PosHexGenerator.generatePurchaseHexMessage(
          paddedTransactionId,
          total,
          m1Value,
        );

        // Connect to POS terminal
        final prefs = await SharedPreferences.getInstance();
        final posIp = prefs.getString('pos_ip') ?? '192.168.1.10';
        final posPort = 8800;

        final socket = await Socket.connect(posIp, posPort,
            timeout: const Duration(seconds: 10));

        try {
          // Process POS transaction
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
              response['pos_invoice_number'] ?? '';
        } finally {
          socket.destroy();
        }
      }

      // Complete the payment
      final response = await PosService().checkoutOrder(
        invoiceName: widget.order['name'],
        payments: payments,
      );

      if (response['success'] == true) {
        // Show print receipt dialog
        final shouldPrint = await _showPrintReceiptDialog();

        if (shouldPrint) {
          await ReceiptPrinter.showPrintDialog(context, widget.order['name']);
        }
        widget.onPaymentComplete();
        Fluttertoast.showToast(
          msg: "Payment Successful",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      } else {
        widget.onPaymentFailed();
        Fluttertoast.showToast(
          msg: "Payment failed: ${response['message']}",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    } catch (e) {
      widget.onPaymentFailed();
      Fluttertoast.showToast(
        msg: "Payment failed: ${e.toString()}",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessingPayment = false);
      }
    }
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

  Future<void> _deleteSplitOrder() async {
    if (_isDeletingOrder) return;

    setState(() => _isDeletingOrder = true);

    try {
      final orderName = widget.order['name'];
      if (orderName == null || orderName.isEmpty) {
        throw Exception('Invalid order name');
      }

      final response = await PosService().deleteOrder(orderName);

      if (response['success'] == true) {
        Fluttertoast.showToast(
          msg: "Split order deleted",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
        widget.onCancel();
      } else {
        throw Exception(response['message'] ?? 'Failed to delete split order');
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Error deleting split order: ${e.toString()}",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      if (mounted) {
        setState(() => _isDeletingOrder = false);
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
            'Received data: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');

        // Handle ACK
        if (!ackReceived && data.length == 1 && data[0] == 0x06) {
          ackReceived = true;
          debugPrint('Received ACK (0x06), waiting for full response...');
          return;
        }

        // Add data to buffer
        responseBuffer.addAll(data);

        // Check for complete response (STX...ETX)
        if (ackReceived && responseBuffer.isNotEmpty) {
          final stxIndex = responseBuffer.indexOf(0x02);
          final etxIndex = responseBuffer.indexOf(0x03);

          if (stxIndex != -1 && etxIndex != -1 && etxIndex > stxIndex) {
            debugPrint('Complete response received, parsing...');

            try {
              final messageData =
                  responseBuffer.sublist(stxIndex, etxIndex + 1);
              final response = _parsePosResponse(messageData);
              debugPrint('Parsed response: $response');

              if (!completer.isCompleted) {
                subscription?.cancel();
                completer.complete(response);
              }
            } catch (e) {
              debugPrint('Error parsing response: $e');
              if (!completer.isCompleted) {
                subscription?.cancel();
                completer.completeError(e);
              }
            }
          }
        }
      },
      onError: (error) {
        debugPrint('Socket error: $error');
        if (!completer.isCompleted) {
          subscription?.cancel();
          completer.completeError(error);
        }
      },
      onDone: () {
        debugPrint('Socket connection closed');
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
        'Sending message: ${bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
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
      if (data.length >= 3 &&
          data.first == 0x02 &&
          data[data.length - 1] == 0x03) {
        final payload = data.sublist(1, data.length - 1);
        final hexString =
            payload.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');

        try {
          final asciiString =
              String.fromCharCodes(payload.where((b) => b >= 32 && b <= 126));
          debugPrint('ASCII representation: $asciiString');
        } catch (e) {
          debugPrint('Could not convert to ASCII: $e');
        }

        return _decodeHexResponse(hexString, payload);
      }

      throw Exception('Invalid POS response format - missing STX/ETX markers');
    } catch (e) {
      debugPrint('Parse error: $e');
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
      bool isDuitNowPayment = false;

      try {
        final asciiData =
            String.fromCharCodes(rawData.where((b) => b >= 32 && b <= 126));

        // Check payment type
        isQrPayment = asciiData.contains(' QR ');
        isDuitNowPayment = asciiData.contains('DevN5');

        // Extract invoice number
        final invoiceMatch = RegExp(r'INV(\d{9})').firstMatch(asciiData);
        if (invoiceMatch != null) {
          invoiceNumber = invoiceMatch.group(1)!;
          transactionId = 'INV$invoiceNumber';
        }

        // Extract reference number based on payment type
        if (isDuitNowPayment) {
          posInvoiceNumber = _extractDuitNowReferenceId(asciiData);
        } else if (isQrPayment) {
          posInvoiceNumber = _extractQrReferenceId(asciiData);
        } else {
          // Card Payment
          posInvoiceNumber = _extractPosInvoiceNumber(asciiData);
        }

        // Check approval status
        if (asciiData.contains('APPROVED')) {
          status = 'success';
          responseText = 'APPROVED';
        }
      } catch (e) {
        debugPrint('ASCII parsing failed: $e');
      }

      return {
        'invoice_number': invoiceNumber,
        'pos_invoice_number': posInvoiceNumber,
        'response_text': responseText,
        'status': status,
        'transaction_id': transactionId,
        'is_qr_payment': isQrPayment,
        'is_duitnow_payment': isDuitNowPayment,
      };
    } catch (e) {
      debugPrint('Decode error: $e');
      return {
        'invoice_number': '000000',
        'pos_invoice_number': '000000',
        'response_text': 'Decode error: ${e.toString()}',
        'status': 'error',
        'transaction_id': 'ERROR_${DateTime.now().millisecondsSinceEpoch}',
        'is_qr_payment': false,
        'is_duitnow_payment': false,
      };
    }
  }

  String _extractQrReferenceId(String asciiData) {
    try {
      final yymmMatch = RegExp(r'E6600325(\d{4})04').firstMatch(asciiData);
      final timeMatch = RegExp(r'E6600325\d{4}04(\d{6})').firstMatch(asciiData);
      final paymentRefMatch = RegExp(r'65(\d{6})64').firstMatch(asciiData);

      if (yymmMatch != null && timeMatch != null && paymentRefMatch != null) {
        final yymm = yymmMatch.group(1)!;
        final timeStr = timeMatch.group(1)!;
        final middleRef = paymentRefMatch.group(1)!;

        int hh = int.parse(timeStr.substring(0, 2));
        int mm = int.parse(timeStr.substring(2, 4));
        int ss = int.parse(timeStr.substring(4, 6));

        int totalSeconds = hh * 3600 + mm * 60 + ss - 2;
        if (totalSeconds < 0) totalSeconds = 0;

        final adjHH = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
        final adjMM = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
        final adjSS = (totalSeconds % 60).toString().padLeft(2, '0');

        final adjustedTime = '$adjHH$adjMM$adjSS';
        return '$yymm$adjustedTime$middleRef';
      }
    } catch (e) {
      debugPrint('Error extracting QR reference: $e');
    }

    return '000000000000000000';
  }

  String _extractDuitNowReferenceId(String asciiData) {
    try {
      final match = RegExp(r'DevN5(\d{16})').firstMatch(asciiData);
      if (match != null) {
        return match.group(1)!;
      }
    } catch (e) {
      debugPrint('Error extracting DuitNow reference: $e');
    }
    return '000000000000000000';
  }

  String _extractPosInvoiceNumber(String asciiData) {
    try {
      final index = asciiData.indexOf('6400');
      if (index != -1 && index >= 6) {
        return asciiData.substring(index - 6, index);
      }
    } catch (e) {
      debugPrint('Error extracting POS invoice number: $e');
    }
    return '000000';
  }

  List<int> _hexStringToBytes(String hexString) {
    return hexString
        .split(' ')
        .map((hex) => int.parse(hex, radix: 16))
        .toList();
  }

  Future<bool> _showPrintReceiptDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text(
                'Print Receipt?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: const Text(
                'Would you like to print the receipt for this transaction?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'No',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE732A0),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text(
                    'Yes',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
  }
}
