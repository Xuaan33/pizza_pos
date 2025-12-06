import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shiok_pos_android_app/components/image_url_helper.dart';
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
  String baseImageUrl = '';
  bool _isDeletingOrder = false;
  bool _isLoading = true;
  Map<String, dynamic> _orderDetails = {};
  String _voucherCode = '';
  double _discountAmount = 0.0;
  bool _isValidatingVoucher = false;
  bool _isRemovingDiscount = false;
  TextInputFormatter get _uppercaseFormatter =>
      FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9]'));

  @override
  void initState() {
    super.initState();
    _fetchOrderDetails();
    _loadBaseUrl();
  }

  Future<void> _loadBaseUrl() async {
    baseImageUrl = await ImageUrlHelper.getBaseImageUrl();
    setState(() {}); // Refresh UI
  }

  Future<void> _fetchOrderDetails() async {
    try {
      final response = await PosService().getOrders(
        posProfile: ref.read(authProvider).maybeWhen(
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

            // Initialize discount values from order details
            _discountAmount =
                (_orderDetails['discount_amount'] ?? 0).toDouble();
            _voucherCode = _orderDetails['user_voucher_code'] ?? '';
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

    final items = List<Map<String, dynamic>>.from(_orderDetails['items'] ?? []);

    final isCashPayment = _selectedPaymentMethod == 'Cash';
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
                children: [
                  const Icon(Icons.receipt, size: 30, color: Color(0xFFE732A0)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Split Order Payment',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE732A0),
                      ),
                    ),
                  ),
                  // Apply Discount Button
                  GestureDetector(
                    onTap: _isProcessingPayment ? null : _showVoucherDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _discountAmount > 0 ? Colors.red : Colors.blue,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _discountAmount > 0
                            ? 'Remove Discount'
                            : 'Apply Discount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                          final basePrice = (item['rate'] ??
                                  item['price'] ??
                                  item['price_list_rate'] ??
                                  0)
                              .toDouble();
                          final quantity =
                              (item['quantity'] ?? item['qty'] ?? 1).toDouble();
                          final discountAmount =
                              (item['discount_amount'] ?? 0).toDouble();
                          final discountPercentage =
                              (item['discount_percentage'] ?? 0).toDouble();

                          // Calculate variant cost
                          final variantCost = _calculateVariantCost(
                              item['custom_variant_info']);
                          final totalItemPrice = basePrice + variantCost;

                          // Calculate actual discount applied
                          double actualDiscount = 0;
                          if (discountAmount > 0) {
                            actualDiscount = discountAmount;
                          } else if (discountPercentage > 0) {
                            actualDiscount =
                                (totalItemPrice * discountPercentage / 100) *
                                    quantity;
                          }

                          final finalPricePerItem =
                              totalItemPrice - (actualDiscount / quantity);
                          final totalFinalPrice = finalPricePerItem * quantity;
                          final originalTotalPrice = totalItemPrice * quantity;

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
                                        item['item_name'] ?? 'Unknown Item',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      // Existing variant info rendering (if any) is here
                                      const SizedBox(height: 5),

                                      // Price Display Row (Modified for strikethrough/discount)
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          // Price per item and quantity
                                          Row(
                                            children: [
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  if (actualDiscount > 0)
                                                    Text(
                                                      'RM${(totalItemPrice + discountAmount).toStringAsFixed(2)}', // Original price (per item)
                                                      style: TextStyle(
                                                        color: Colors
                                                            .grey.shade600,
                                                        decoration: TextDecoration
                                                            .lineThrough, // Strikethrough
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  if (actualDiscount > 0)
                                                    Text(
                                                      '- RM${discountAmount.toStringAsFixed(2)}', // Discounted amount
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors
                                                            .green.shade700,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              if (actualDiscount > 0)
                                                const SizedBox(width: 8),
                                              Text(
                                                'RM${totalItemPrice.toStringAsFixed(2)}', // Final price (per item)
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                  color: actualDiscount > 0
                                                      ? const Color(0xFFE732A0)
                                                      : Colors.black,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'x${quantity.toStringAsFixed(0)}',
                                                style: TextStyle(
                                                    color:
                                                        Colors.grey.shade600),
                                              ),
                                            ],
                                          ),
                                          // Total Price and Discount Amount
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                'RM${(totalItemPrice * quantity).toStringAsFixed(2)}', // Total final price
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                  color: Color(0xFFE732A0),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
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
                            if (_discountAmount > 0)
                              _buildSummaryRow(
                                _getDiscountDisplayText(),
                                -_discountAmount,
                              ),
                            _buildSummaryRow(
                                'Rounding',
                                (_orderDetails['base_rounding_adjustment'] ?? 0)
                                    .toDouble()),
                            if (_getGSTRate() != '0')
                              _buildSummaryRow(
                                  'GST (${_getGSTRate()}%)',
                                  ((_orderDetails['total_taxes_and_charges'] ??
                                          0))
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

  // Add variant cost calculation method
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
        // Old format might not have additional cost info
        debugPrint('Old variant format detected: $parsedVariant');
      }
    } catch (e) {
      debugPrint('Error calculating variant cost: $e');
    }

    return totalVariantCost;
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
      final total = (_orderDetails['rounded_total'] ?? 0).toDouble();
      final selectedMethod = widget.paymentMethods.firstWhere(
        (method) => method['name'] == _selectedPaymentMethod,
        orElse: () => {'custom_fiuu_m1_value': '01'},
      );
      final m1Value =
          selectedMethod['custom_fiuu_m1_value']?.toString() ?? '01';

      final shouldPrintKitchenOrder = ref.read(authProvider).maybeWhen(
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
              return printKitchenOrder == 1;
            },
            orElse: () => false,
          );

      final isOfflinePayment = ref.read(authProvider).maybeWhen(
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
              return m1Value == '-1';
            },
            orElse: () => false,
          );


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
      if (!_isCashPayment && !isOfflinePayment) {
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
        if (_selectedPaymentMethod == 'Cash') {
          // Open cash drawer for cash payments
          try {
            await ReceiptPrinter.openCashDrawer();
          } catch (e) {
            debugPrint('⚠️ Cash drawer error: $e');
            // Continue with payment even if cash drawer fails
          }
        }
        if (shouldPrintKitchenOrder) {
          await _printKitchenOrderOnly(widget.order['name']);
        }

        

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

  String _getGSTRate() {
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
            final gstTax = taxes.firstWhere(
              (tax) => tax['description']?.contains('GST') ?? false,
              orElse: () => {'rate': 0.0},
            );
            return (gstTax['rate'] ?? 0.0).toStringAsFixed(0);
          },
        ) ??
        '0';
  }

  // Discount-related methods
  Future<void> _showVoucherDialog() async {
    final hasDiscount = _discountAmount > 0 ||
        _orderDetails['coupon_code'] != null ||
        _orderDetails['custom_user_voucher'] != null;

    if (_discountAmount > 0) {
      final shouldRemove = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Remove Discount',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'Are you sure you want to remove the current discount?',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            TextButton(
              child: const Text(
                'CANCEL',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE732A0),
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'REMOVE',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );

      if (shouldRemove == true) {
        _isRemovingDiscount = true;
        await _removeDiscount();
        _isRemovingDiscount = false;
      }
      return;
    }

    final voucherController = TextEditingController();
    final discountPercentageController = TextEditingController();
    final discountAmountController = TextEditingController();
    int selectedDiscountType = 0; // 0 = voucher, 1 = percentage, 2 = amount

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text(
                'Apply Discount',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Discount type selector
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(
                            'Voucher',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          selected: selectedDiscountType == 0,
                          onSelected: (selected) {
                            setState(() {
                              selectedDiscountType =
                                  selected ? 0 : selectedDiscountType;
                            });
                          },
                        ),
                        ChoiceChip(
                          label: Text(
                            'Percentage',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          selected: selectedDiscountType == 1,
                          onSelected: (selected) {
                            setState(() {
                              selectedDiscountType =
                                  selected ? 1 : selectedDiscountType;
                              if (selected) {
                                voucherController.clear();
                                discountAmountController.clear();
                              }
                            });
                          },
                        ),
                        ChoiceChip(
                          label: Text(
                            'Amount',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          selected: selectedDiscountType == 2,
                          onSelected: (selected) {
                            setState(() {
                              selectedDiscountType =
                                  selected ? 2 : selectedDiscountType;
                              if (selected) {
                                voucherController.clear();
                                discountPercentageController.clear();
                              }
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text(
                            'Itemized',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          selected: selectedDiscountType == 3,
                          onSelected: (selected) {
                            if (selected) {
                              // Close the current dialog temporarily
                              Navigator.of(context).pop(false);

                              Future.microtask(() async {
                                final itemsWithDiscounts =
                                    await _showItemizedDiscountDialog();
                                if (itemsWithDiscounts != null) {
                                  // Call the method to apply the itemized discount
                                  await _applyItemizedDiscount(
                                      itemsWithDiscounts);
                                }
                              });
                              return; // Exit _showVoucherDialog
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Voucher code field (only visible when voucher is selected)
                    if (selectedDiscountType == 0)
                      TextField(
                        controller: voucherController,
                        decoration: const InputDecoration(
                          labelText: 'Voucher Code',
                          border: OutlineInputBorder(),
                        ),
                        inputFormatters: [_uppercaseFormatter],
                        textCapitalization: TextCapitalization.characters,
                        onChanged: (value) {
                          // Convert to uppercase and update cursor position
                          if (value != value.toUpperCase()) {
                            final cursorPosition =
                                voucherController.selection.base.offset;
                            voucherController.value =
                                voucherController.value.copyWith(
                              text: value.toUpperCase(),
                              selection: TextSelection.collapsed(
                                  offset: cursorPosition),
                            );
                          }
                        },
                      ),

                    // Percentage field (only visible when percentage is selected)
                    if (selectedDiscountType == 1)
                      TextField(
                        controller: discountPercentageController,
                        decoration: const InputDecoration(
                          labelText: 'Discount Percentage (%)',
                          border: OutlineInputBorder(),
                          suffixText: '%',
                        ),
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true),
                        onChanged: (value) {
                          if (value.isNotEmpty) {
                            final percentage = double.tryParse(value) ?? 0;
                            final amount =
                                _calculateSubtotal() * percentage / 100;
                            discountAmountController.text =
                                amount.toStringAsFixed(2);
                          } else {
                            discountAmountController.clear();
                          }
                        },
                      ),

                    // Amount field (only visible when amount is selected)
                    if (selectedDiscountType == 2)
                      TextField(
                        controller: discountAmountController,
                        decoration: const InputDecoration(
                          labelText: 'Discount Amount (RM)',
                          border: OutlineInputBorder(),
                          prefixText: 'RM ',
                        ),
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true),
                        onChanged: (value) {
                          if (value.isNotEmpty) {
                            final amount = double.tryParse(value) ?? 0;
                            final percentage =
                                (amount / _calculateSubtotal()) * 100;
                            discountPercentageController.text =
                                percentage.toStringAsFixed(2);
                          } else {
                            discountPercentageController.clear();
                          }
                        },
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
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE732A0),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    'Apply',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    if (selectedDiscountType == 0 &&
                        voucherController.text.isEmpty) {
                      Fluttertoast.showToast(
                        msg: "Please enter a voucher code",
                        gravity: ToastGravity.BOTTOM,
                        backgroundColor: Colors.red,
                        textColor: Colors.white,
                      );
                      return;
                    } else if (selectedDiscountType == 1 &&
                        discountPercentageController.text.isEmpty) {
                      Fluttertoast.showToast(
                        msg: "Please enter a discount percentage",
                        gravity: ToastGravity.BOTTOM,
                        backgroundColor: Colors.red,
                        textColor: Colors.white,
                      );
                      return;
                    } else if (selectedDiscountType == 2 &&
                        discountAmountController.text.isEmpty) {
                      Fluttertoast.showToast(
                        msg: "Please enter a discount amount",
                        gravity: ToastGravity.BOTTOM,
                        backgroundColor: Colors.red,
                        textColor: Colors.white,
                      );
                      return;
                    }
                    Navigator.of(context).pop(true);
                  },
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      if (selectedDiscountType == 0) {
        // Voucher code
        _validateVoucher(voucherController.text);
      } else if (selectedDiscountType == 1) {
        // Percentage discount
        final percentage =
            double.tryParse(discountPercentageController.text) ?? 0;
        final amount = _calculateSubtotal() * percentage / 100;
        await _applyManualDiscount(amount);
      } else if (selectedDiscountType == 2) {
        // Fixed amount discount
        final amount = double.tryParse(discountAmountController.text) ?? 0;
        await _applyManualDiscount(amount);
      }
    }
  }

  Future<void> _validateVoucher(String voucherCode) async {
    _showLoadingOverlay(true);

    try {
      // Convert user input to uppercase
      final uppercaseVoucherCode = voucherCode.toUpperCase();

      final response = await PosService().validateVoucher(uppercaseVoucherCode);

      if (response['success'] == true) {
        final voucherData = response['message'];
        final couponCode = voucherData['coupon_code'];

        setState(() {
          _voucherCode = uppercaseVoucherCode; // Use the uppercase user input
        });

        // Update the order with the voucher using the user's input (uppercase)
        await _updateOrderWithVoucher(uppercaseVoucherCode, couponCode);

        Fluttertoast.showToast(
          msg: "Voucher applied successfully",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      } else {
        Fluttertoast.showToast(
          msg: "Voucher code is invalid or redeemed",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Error validating voucher: ${e.toString()}",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      _showLoadingOverlay(false);
    }
  }

  Future<void> _updateOrderWithVoucher(
      String voucherName, String couponCode) async {
    try {
      final orderName = widget.order['name'];
      if (orderName == null) return;

      // Update local state immediately
      setState(() {
        _voucherCode = voucherName;
      });

      final response = await PosService().submitOrder(
          name: orderName,
          posProfile: ref.read(authProvider).maybeWhen(
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
                      return posProfile;
                    },
                    orElse: () => null,
                  ) ??
              '',
          customer: 'Guest',
          table: _orderDetails['table'],
          orderChannel: 'Dine In',
          items: List<Map<String, dynamic>>.from(_orderDetails['items'] ?? [])
              .map((item) {
            return {
              'item_code': item['item_code'] ?? '',
              'qty': item['quantity'] ?? item['qty'] ?? 1,
              'price_list_rate': (item['rate'] ??
                          item['price'] ??
                          item['price_list_rate'] ??
                          0)
                      .toDouble() +
                  _calculateVariantCost(item['custom_variant_info']),
              'custom_item_remarks': item['custom_item_remarks'] ?? '',
              'custom_serve_later': item['custom_serve_later'] == true ? 1 : 0,
              if (item['custom_variant_info'] != null)
                'custom_variant_info': item['custom_variant_info'],
            };
          }).toList(),
          couponCode: couponCode,
          custom_user_voucher: voucherName,
          remarks: _orderDetails['remarks'] ?? "N/A");

      if (response['success'] == true) {
        // Update the order details with new amounts from server
        await _fetchOrderDetails();
      }
    } catch (e) {
      debugPrint('Error updating order with voucher: $e');
      // Revert local changes on error
      setState(() {
        _voucherCode = '';
      });
    }
  }

  Future<void> _applyManualDiscount(double amount) async {
    _showLoadingOverlay(true);

    try {
      final orderName = widget.order['name'];
      if (orderName == null) return;

      // Update local state immediately
      setState(() {
        _discountAmount = amount;
      });

      final response = await PosService().submitOrder(
        name: orderName,
        posProfile: ref.read(authProvider).maybeWhen(
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
                    return posProfile;
                  },
                  orElse: () => null,
                ) ??
            '',
        customer: 'Guest',
        table: _orderDetails['table'],
        orderChannel: 'Dine In',
        items: List<Map<String, dynamic>>.from(_orderDetails['items'] ?? [])
            .map((item) {
          return {
            'item_code': item['item_code'] ?? '',
            'qty': item['quantity'] ?? item['qty'] ?? 1,
            'price_list_rate':
                (item['rate'] ?? item['price'] ?? item['price_list_rate'] ?? 0)
                        .toDouble() +
                    _calculateVariantCost(item['custom_variant_info']),
            'custom_item_remarks': item['custom_item_remarks'] ?? '',
            'custom_serve_later': item['custom_serve_later'] == true ? 1 : 0,
            if (item['custom_variant_info'] != null)
              'custom_variant_info': item['custom_variant_info'],
          };
        }).toList(),
        remarks: _orderDetails['remarks'] ?? "N/A",
        discountAmount: amount, // Pass the discount amount directly
      );

      if (response['success'] == true) {
        // Update the order details with new amounts from server
        await _fetchOrderDetails();
        Fluttertoast.showToast(
          msg: "Discount applied successfully",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Error applying discount: ${e.toString()}",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      // Revert local changes on error
      setState(() {
        _discountAmount = 0;
      });
    } finally {
      _showLoadingOverlay(false);
    }
  }

  Future<void> _removeDiscount() async {
    _showLoadingOverlay(true);

    try {
      final orderName = widget.order['name'];
      if (orderName == null) return;

      // Update local state immediately
      setState(() {
        _discountAmount = 0;
        _voucherCode = '';
      });

      final response = await PosService().submitOrder(
        name: orderName,
        posProfile: ref.read(authProvider).maybeWhen(
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
                  ) =>
                      posProfile,
                  orElse: () => null,
                ) ??
            '',
        customer: 'Guest',
        table: _orderDetails['table'],
        orderChannel: 'Dine In',
        items: List<Map<String, dynamic>>.from(_orderDetails['items'] ?? [])
            .map((item) {
          return {
            'item_code': item['item_code'] ?? '',
            'qty': item['quantity'] ?? item['qty'] ?? 1,
            'price_list_rate':
                (item['rate'] ?? item['price'] ?? item['price_list_rate'] ?? 0)
                        .toDouble() +
                    _calculateVariantCost(item['custom_variant_info']),
            'custom_item_remarks': item['custom_item_remarks'] ?? '',
            'custom_serve_later': item['custom_serve_later'] == true ? 1 : 0,
            if (item['custom_variant_info'] != null)
              'custom_variant_info': item['custom_variant_info'],
          };
        }).toList(),
        couponCode: null, // Set to null to remove
        custom_user_voucher: null, // Set to null to remove
        discountAmount: 0, // Set to 0 to remove
        remarks: _orderDetails['remarks'] ?? "N/A",
      );

      if (response['success'] == true) {
        // Force a complete refresh of order details
        await _fetchOrderDetails();

        // Double-check and force clear any discount values that might have persisted
        setState(() {
          if (_discountAmount > 0) _discountAmount = 0;
          if (_voucherCode?.isNotEmpty == true) _voucherCode = '';
        });

        Fluttertoast.showToast(
          msg: "Discount removed successfully",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Error removing discount: ${e.toString()}",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      _showLoadingOverlay(false);
    }
  }

  Future<void> _applyItemizedDiscount(
      List<Map<String, dynamic>> itemsWithDiscounts) async {
    _showLoadingOverlay(true);

    try {
      final authState = ref.read(authProvider);
      final posProfile = authState.maybeWhen(
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
          return posProfile;
        },
        orElse: () => null,
      );

      if (posProfile == null) {
        throw Exception('User not authenticated.');
      }

      // Prepare items for submission: use existing fields, but override discount
      final itemsToSubmit = itemsWithDiscounts.map((item) {
        final itemData = {
          'item_code': item['item_code'] ?? '',
          'qty': item['quantity'] ?? item['qty'] ?? 1,
          'price_list_rate':
              (item['rate'] ?? item['price'] ?? item['price_list_rate'] ?? 0)
                      .toDouble() +
                  _calculateVariantCost(item['custom_variant_info']),
          "custom_item_remarks": item['custom_item_remarks'],
          "custom_serve_later": item['custom_serve_later'] == true ? 1 : 0,
          if (item['custom_variant_info'] != null)
            'custom_variant_info': item['custom_variant_info'],
        };

        // Add only one discount field - prioritize amount over percentage
        if ((item['discount_amount'] as double?)!.toDouble() > 0) {
          itemData['discount_amount'] = item['discount_amount'];
          itemData['discount_percentage'] = 0.0;
        } else if ((item['discount_percentage'] as double?)!.toDouble() > 0) {
          itemData['discount_percentage'] = item['discount_percentage'];
          itemData['discount_amount'] = 0.0;
        } else {
          itemData['discount_percentage'] = 0.0;
          itemData['discount_amount'] = 0.0;
        }

        return itemData;
      }).toList();

      final response = await PosService().submitOrder(
        name: _orderDetails['name'],
        posProfile: posProfile,
        customer: _orderDetails['customer'] ?? 'Guest',
        table: _orderDetails['table'],
        orderChannel: _orderDetails['order_type'] ?? 'Dine In',
        items: itemsToSubmit,
        // Ensure global discount is 0 when applying itemized
        discountAmount: 0.0,
        couponCode: null,
        custom_user_voucher: null,
        remarks: _orderDetails['remarks'],
      );

      if (response['success'] == true ||
          response['message']?['success'] == true) {
        // Update the order details with new amounts from server
        await _fetchOrderDetails();
        Fluttertoast.showToast(
          msg: "Itemized discount applied successfully",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      } else {
        throw Exception(response['message']?['message'] ??
            'Failed to apply itemized discount.');
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Error applying itemized discount: ${e.toString()}",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      _showLoadingOverlay(false);
    }
  }

  // New Helper Method: Show Itemized Discount Dialog (UI for selecting discounts)
  Future<List<Map<String, dynamic>>?> _showItemizedDiscountDialog() async {
    final originalItems =
        List<Map<String, dynamic>>.from(_orderDetails['items'] ?? []);
    List<Map<String, dynamic>> itemsWithDiscounts = originalItems.map((item) {
      final basePrice =
          (item['rate'] ?? item['price'] ?? item['price_list_rate'] ?? 0)
              .toDouble();
      final quantity = (item['quantity'] ?? item['qty'] ?? 1).toDouble();
      final variantCost = _calculateVariantCost(item['custom_variant_info']);
      final itemTotal = (basePrice + variantCost) * quantity;

      final initialDiscountAmount = (item['discount_amount'] ?? 0.0).toDouble();
      final initialDiscountPercentage =
          (item['discount_percentage'] ?? 0.0).toDouble();

      int initialDiscountType = 0; // 0 = None, 1 = Percentage, 2 = Amount

      if (initialDiscountAmount > 0) {
        initialDiscountType = 2;
      } else if (initialDiscountPercentage > 0) {
        initialDiscountType = 1;
      }

      return {
        ...item,
        'selected_discount_type': initialDiscountType,
        'discount_percentage_controller': TextEditingController(
          text: initialDiscountPercentage > 0 && initialDiscountType == 1
              ? initialDiscountPercentage.toStringAsFixed(2)
              : '',
        ),
        'discount_amount_controller': TextEditingController(
          text: initialDiscountAmount > 0 && initialDiscountType == 2
              ? initialDiscountAmount.toStringAsFixed(2)
              : '',
        ),
        'current_discount_amount': initialDiscountAmount,
        'current_discount_percentage': initialDiscountPercentage,
        'item_total_price': itemTotal,
        'item_price_per_unit': basePrice + variantCost,
      };
    }).toList();

    return showDialog<List<Map<String, dynamic>>?>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            void updateItemDiscount(int index) {
              final item = itemsWithDiscounts[index];
              final type = item['selected_discount_type'] as int;
              final percentageController =
                  item['discount_percentage_controller']
                      as TextEditingController;
              final amountController =
                  item['discount_amount_controller'] as TextEditingController;
              final itemTotal = item['item_total_price'] as double;

              double newDiscountAmount = 0.0;
              double newDiscountPercentage = 0.0;

              if (type == 1) {
                // Percentage
                final percentage =
                    double.tryParse(percentageController.text) ?? 0.0;
                newDiscountPercentage = percentage.clamp(0.0, 100.0);
                newDiscountAmount = itemTotal * newDiscountPercentage / 100.0;
              } else if (type == 2) {
                // Amount
                final amount = double.tryParse(amountController.text) ?? 0.0;
                newDiscountAmount = amount.clamp(0.0, itemTotal);
                if (itemTotal > 0) {
                  newDiscountPercentage =
                      (newDiscountAmount / itemTotal) * 100.0;
                }
              }

              item['current_discount_amount'] = newDiscountAmount;
              item['current_discount_percentage'] = newDiscountPercentage;
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text(
                'Apply Itemized Discount',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 600, // Constrain width
                child: Scrollbar(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Apply discounts to individual items.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFFE732A0),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: itemsWithDiscounts.length,
                          itemBuilder: (context, index) {
                            final item = itemsWithDiscounts[index];
                            final quantity =
                                (item['quantity'] ?? item['qty'] ?? 1)
                                    .toDouble();
                            final itemTotal =
                                item['item_total_price'] as double;
                            final currentDiscountAmount =
                                item['current_discount_amount'] as double;
                            final currentDiscountPercentage =
                                item['current_discount_percentage'] as double;
                            int selectedDiscountType =
                                item['selected_discount_type'] as int;
                            final percentageController =
                                item['discount_percentage_controller']
                                    as TextEditingController;
                            final amountController =
                                item['discount_amount_controller']
                                    as TextEditingController;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${item['item_name'] ?? 'Unknown Item'} (x${quantity.toStringAsFixed(0)})',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        ChoiceChip(
                                          label: const Text('None'),
                                          selected: selectedDiscountType == 0,
                                          onSelected: (selected) {
                                            if (selected) {
                                              setState(() {
                                                item['selected_discount_type'] =
                                                    0;
                                                percentageController.clear();
                                                amountController.clear();
                                                updateItemDiscount(index);
                                              });
                                            }
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        ChoiceChip(
                                          label: const Text('%'),
                                          selected: selectedDiscountType == 1,
                                          onSelected: (selected) {
                                            if (selected) {
                                              setState(() {
                                                item['selected_discount_type'] =
                                                    1;
                                                amountController.clear();
                                                updateItemDiscount(index);
                                              });
                                            }
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        ChoiceChip(
                                          label: const Text('RM'),
                                          selected: selectedDiscountType == 2,
                                          onSelected: (selected) {
                                            if (selected) {
                                              setState(() {
                                                item['selected_discount_type'] =
                                                    2;
                                                percentageController.clear();
                                                updateItemDiscount(index);
                                              });
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    if (selectedDiscountType == 1)
                                      TextField(
                                        controller: percentageController,
                                        decoration: const InputDecoration(
                                          labelText:
                                              'Discount Percentage (Max 100)',
                                          border: OutlineInputBorder(),
                                          suffixText: '%',
                                        ),
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        onChanged: (value) {
                                          setState(
                                              () => updateItemDiscount(index));
                                        },
                                      ),
                                    if (selectedDiscountType == 2)
                                      TextField(
                                        controller: amountController,
                                        decoration: InputDecoration(
                                          labelText:
                                              'Discount Amount (Max RM${itemTotal.toStringAsFixed(2)})',
                                          border: const OutlineInputBorder(),
                                          prefixText: 'RM ',
                                        ),
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        onChanged: (value) {
                                          setState(
                                              () => updateItemDiscount(index));
                                        },
                                      ),
                                    if (selectedDiscountType != 0)
                                      const SizedBox(height: 10),

                                    // Price summary display
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Original: RM${itemTotal.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                            decoration:
                                                TextDecoration.lineThrough,
                                          ),
                                        ),
                                        if (currentDiscountAmount > 0) ...[
                                          Text(
                                            'Discount: ${currentDiscountPercentage.toStringAsFixed(1)}% = RM${currentDiscountAmount.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.orange.shade700,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                        Text(
                                          'Final Amount: RM${(itemTotal - currentDiscountAmount).toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: currentDiscountAmount > 0
                                                ? Colors.green.shade700
                                                : Colors.black,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    // Dispose of controllers on cancel
                    for (var item in itemsWithDiscounts) {
                      (item['discount_percentage_controller']
                              as TextEditingController)
                          .dispose();
                      (item['discount_amount_controller']
                              as TextEditingController)
                          .dispose();
                    }
                    Navigator.of(context).pop(null);
                  },
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE732A0),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    'Apply',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    // Collect final items data and dispose of controllers
                    final List<Map<String, dynamic>> finalItems =
                        itemsWithDiscounts.map((item) {
                      final itemData = {
                        ...item,
                        'discount_amount': item['selected_discount_type'] == 2
                            ? item['current_discount_amount']
                            : 0.0,
                        'discount_percentage':
                            item['selected_discount_type'] == 1
                                ? item['current_discount_percentage']
                                : 0.0,
                      };
                      (item['discount_percentage_controller']
                              as TextEditingController)
                          .dispose();
                      (item['discount_amount_controller']
                              as TextEditingController)
                          .dispose();
                      return itemData;
                    }).toList();
                    Navigator.of(context).pop(finalItems);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showLoadingOverlay(bool show) {
    if (show) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return WillPopScope(
            onWillPop: () async => false,
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        },
      );
    } else {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _printKitchenOrderOnly(
    String orderName,
  ) async {
    try {
      await ReceiptPrinter.printKitchenOrderOnly(orderName);
    } catch (e) {
      debugPrint('Failed to print kitchen order: $e');
      // Don't show error toast for kitchen order failure as it's non-critical
    }
  }

  double _calculateSubtotal() {
    // Use server value if available, otherwise calculate from items
    final serverSubtotal = (_orderDetails['total'] as num?)?.toDouble();

    if (serverSubtotal != null) {
      debugPrint('Using server subtotal: RM$serverSubtotal');
      return serverSubtotal;
    }

    // Calculate local subtotal including variant costs
    final items = List<Map<String, dynamic>>.from(_orderDetails['items'] ?? []);
    double localSubtotal = items.fold(0.0, (sum, item) {
      final basePrice =
          (item['rate'] ?? item['price'] ?? item['price_list_rate'] ?? 0)
              .toDouble();
      final variantCost = _calculateVariantCost(item['custom_variant_info']);
      final totalPrice = basePrice + variantCost;
      final quantity = (item['quantity'] ?? item['qty'] ?? 1).toDouble();
      final itemTotal = totalPrice * quantity;

      return sum + itemTotal;
    });

    return localSubtotal;
  }

  String _getDiscountDisplayText() {
    if (_voucherCode.isNotEmpty) {
      return 'Discount ($_voucherCode)';
    }

    // Calculate discount percentage when no voucher name is available
    final subtotal = _calculateSubtotal();
    if (subtotal > 0) {
      final discountPercentage = (_discountAmount / subtotal * 100).toDouble();
      return 'Discount (${discountPercentage.toStringAsFixed(1)}%)';
    }

    return 'Discount';
  }
}
