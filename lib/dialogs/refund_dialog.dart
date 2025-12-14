import 'dart:convert';
import 'package:flutter/material.dart';

enum RefundType {
  full,
  itemized,
  exchange,
}

class RefundDialog extends StatefulWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> paymentMethods;
  final Function(String, List<Map<String, dynamic>>?) onRefund;
  final Function(List<Map<String, dynamic>>)? onExchange;
  final List<Map<String, dynamic>>? availableItems;
  const RefundDialog({
    Key? key,
    required this.order,
    required this.paymentMethods,
    required this.onRefund,
    this.onExchange,
    this.availableItems,
  }) : super(key: key);

  @override
  _RefundDialogState createState() => _RefundDialogState();
}

class _RefundDialogState extends State<RefundDialog> {
  RefundType _selectedType = RefundType.full;
  // Changed to store item with selected quantity
  Map<String, Map<String, dynamic>> _selectedItemsWithQuantity = {};
  double _totalRefundAmount = 0.0;
  bool _isCashPayment = true; // Track if payment is cash/offline
  List<Map<String, dynamic>> _availableItems = []; // Store available items

  @override
  void initState() {
    super.initState();
    _checkPaymentMethod();
    _initializeAvailableItems();
    _calculateRefundAmount();
  }

  void _checkPaymentMethod() {
    // Get the payment method from the order
    final paymentMethod = widget.order['paymentMethod']?.toString() ?? 'Cash';

    // Find the corresponding payment method to check if it's cash
    final paymentMethodData = widget.paymentMethods.firstWhere(
      (method) => method['name'] == paymentMethod,
      orElse: () => {'name': 'Cash', 'custom_fiuu_m1_value': '-1'},
    );

    final m1Value =
        paymentMethodData['custom_fiuu_m1_value']?.toString() ?? '-1';

    // Determine if it's cash/offline payment
    _isCashPayment = m1Value == '-1' || paymentMethod.toLowerCase() == 'cash';

    // If not cash payment and user somehow selected itemized/exchange, reset to full
    if (!_isCashPayment &&
        (_selectedType == RefundType.itemized ||
            _selectedType == RefundType.exchange)) {
      _selectedType = RefundType.full;
    }
  }

  void _initializeAvailableItems() {
    if (widget.availableItems != null && widget.availableItems!.isNotEmpty) {
      // Use available items from API response
      _availableItems = widget.availableItems!;
    } else {
      // Fallback to all order items (for backward compatibility)
      final items = (widget.order['items'] as List?) ?? [];
      _availableItems = items.map((item) {
        return {
          'name': item['name'] ?? '',
          'item_name': item['item_name'] ?? item['name'] ?? '',
          'item_code': item['item_code'] ?? '',
          'quantity': (item['quantity'] ?? item['qty'] ?? 0).toDouble(),
          'price': (item['price'] ?? 0).toDouble(),
          'custom_variant_info': item['custom_variant_info'],
          'max_available_qty':
              (item['quantity'] ?? item['qty'] ?? 0).toDouble(),
        };
      }).toList();
    }
  }

  void _calculateRefundAmount() {
    double amount = 0.0;

    if (_selectedType == RefundType.full) {
      // Full refund - calculate from available items
      for (var item in _availableItems) {
        final quantity = (item['quantity'] as num).toDouble();
        final price = (item['price'] as num).toDouble();
        final variantCost = _calculateVariantCost(item['custom_variant_info']);
        final totalPrice = price + variantCost;
        amount += totalPrice * quantity;
      }
    } else if (_selectedType == RefundType.itemized ||
        _selectedType == RefundType.exchange) {
      // Calculate based on selected items with their quantities
      _selectedItemsWithQuantity.forEach((key, itemData) {
        final quantity = (itemData['selectedQuantity'] as num).toDouble();
        final price = (itemData['price'] as num).toDouble();
        final variantCost =
            _calculateVariantCost(itemData['custom_variant_info']);
        final totalPrice = price + variantCost;
        amount += totalPrice * quantity;
      });
    }

    setState(() {
      _totalRefundAmount = amount;
    });
  }

  double _calculateOrderTotal(Map<String, dynamic> order) {
    if (order['total'] != null) {
      double total = (order['total'] as num).toDouble();
      return total < 0 ? 0.00 : total;
    }

    final items = (order['items'] as List?) ?? [];
    double total = 0.0;

    for (var item in items) {
      final quantity = (item['quantity'] as num).toDouble();
      final price = (item['price'] as num).toDouble();
      final variantCost = _calculateVariantCost(item['custom_variant_info']);
      final totalPrice = price + variantCost;
      total += totalPrice * quantity;
    }

    return total;
  }

  double _calculateVariantCost(dynamic variantInfo) {
    if (variantInfo == null) return 0.0;
    double totalVariantCost = 0.0;

    try {
      dynamic parsedVariant = variantInfo;
      if (variantInfo is String) {
        try {
          parsedVariant = jsonDecode(variantInfo);
        } catch (e) {
          return 0.0;
        }
      }

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
    } catch (e) {
      debugPrint('Error calculating variant cost: $e');
    }

    return totalVariantCost;
  }

  void _onItemSelectionChanged(
      String itemKey, Map<String, dynamic> item, bool selected) {
    setState(() {
      if (selected) {
        // Initialize with quantity 1 when first selected
        _selectedItemsWithQuantity[itemKey] = {
          ...item,
          'selectedQuantity': 1.0, // Start with 1
          'maxQuantity': item['quantity'], // Store max available quantity
        };
      } else {
        _selectedItemsWithQuantity.remove(itemKey);
      }
      _calculateRefundAmount();
    });
  }

  void _onQuantityChanged(String itemKey, double newQuantity) {
    setState(() {
      if (_selectedItemsWithQuantity.containsKey(itemKey)) {
        final maxQty =
            (_selectedItemsWithQuantity[itemKey]!['maxQuantity'] as num)
                .toDouble();
        // Ensure quantity is between 1 and max
        final clampedQty = newQuantity.clamp(1.0, maxQty);
        _selectedItemsWithQuantity[itemKey]!['selectedQuantity'] = clampedQty;
        _calculateRefundAmount();
      }
    });
  }

  void _onRefundTypeChanged(RefundType? type) {
    if (type != null) {
      setState(() {
        _selectedType = type;
        if (type == RefundType.full) {
          _selectedItemsWithQuantity.clear();
        } else if (type == RefundType.exchange) {
          _selectedItemsWithQuantity.clear();
        } else if (type == RefundType.itemized) {
          _selectedItemsWithQuantity.clear();
        }
        _calculateRefundAmount();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = (widget.order['items'] as List?) ?? [];
    final screenHeight = MediaQuery.of(context).size.height;
    final paymentMethod = widget.order['paymentMethod']?.toString() ?? 'Cash';

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.8,
          minWidth: 400,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select Refund Type',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Payment Method: $paymentMethod',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (_availableItems.isNotEmpty &&
                          _availableItems.length <
                              ((widget.order['items'] as List?)?.length ?? 0))
                    Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        '${_availableItems.length} item(s) available for refund',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Content - Use Expanded for scrollable area
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: CustomScrollView(
                  slivers: [
                    // // Warning message for non-cash payments
                    // if (!_isCashPayment)
                    //   SliverToBoxAdapter(
                    //     child: Container(
                    //       margin: EdgeInsets.only(bottom: 12),
                    //       padding: EdgeInsets.all(12),
                    //       decoration: BoxDecoration(
                    //         color: Colors.orange[50],
                    //         borderRadius: BorderRadius.circular(8),
                    //         border: Border.all(color: Colors.orange[300]!),
                    //       ),
                    //       child: Row(
                    //         children: [
                    //           Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                    //           SizedBox(width: 8),
                    //           Expanded(
                    //             child: Text(
                    //               'Only full refunds are available.',
                    //               style: TextStyle(
                    //                 fontSize: 12,
                    //                 color: Colors.orange[900],
                    //                 fontWeight: FontWeight.w600,
                    //               ),
                    //             ),
                    //           ),
                    //         ],
                    //       ),
                    //     ),
                    //   ),

                    // Refund Type Selection
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          _buildRefundTypeTile(
                            type: RefundType.full,
                            title: 'Full Refund',
                            subtitle: 'Refund the entire order amount',
                            enabled: true,
                          ),
                          _buildRefundTypeTile(
                            type: RefundType.itemized,
                            title: 'Itemized Refund',
                            subtitle: _isCashPayment
                                ? 'Select specific items and quantities to refund'
                                : 'Only available for cash/non-fiuu payments',
                            enabled: true,
                          ),
                          _buildRefundTypeTile(
                            type: RefundType.exchange,
                            title: 'Exchange Item',
                            subtitle: _isCashPayment
                                ? 'Replace items with new ones'
                                : 'Only available for cash payments',
                            enabled: false,
                          ),
                        ],
                      ),
                    ),

                    // Item Selection for Itemized Refund or Exchange
                    if (_selectedType == RefundType.itemized ||
                        _selectedType == RefundType.exchange)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedType == RefundType.exchange
                                    ? 'Select items to exchange:'
                                    : 'Select items to refund:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 8),
                              if (_availableItems.isEmpty)
                                Padding(
                                  padding: EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    'No items available for refund',
                                    style: TextStyle(
                                      color: Colors.orange[700],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                    if (_selectedType == RefundType.itemized ||
                        _selectedType == RefundType.exchange &&
                            _availableItems.isNotEmpty)
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = _availableItems[index];
                            final itemKey = item['name'] ?? index.toString();
                            final isSelected =
                                _selectedItemsWithQuantity.containsKey(itemKey);
                            final maxQuantity =
                                (item['qty'] ?? item['quantity'] ?? 1)
                                    .toDouble();
                            final selectedQuantity = isSelected
                                ? (_selectedItemsWithQuantity[itemKey]![
                                        'selectedQuantity'] as num)
                                    .toDouble()
                                : 1.0;
                            final price = (item['price'] ??
                                    item['rate'] ??
                                    item['price_list_rate'] ??
                                    0)
                                .toDouble();
                            final variantCost = _calculateVariantCost(
                                item['custom_variant_info']);
                            final totalPrice = price + variantCost;
                            final itemName =
                                item['item_name'] ?? item['name'] ?? '';

                            return Card(
                              elevation: 0,
                              margin: EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: isSelected
                                      ? Colors.blue
                                      : Colors.grey[300]!,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  CheckboxListTile(
                                    value: isSelected,
                                    onChanged: (value) {
                                      _onItemSelectionChanged(
                                        itemKey,
                                        {
                                          'name': item['name'] ?? '',
                                          'item_name': itemName,
                                          'item_code': item['item_code'] ?? '',
                                          'quantity': maxQuantity,
                                          'price': price,
                                          'custom_variant_info':
                                              item['custom_variant_info'],
                                        },
                                        value ?? false,
                                      );
                                    },
                                    title: Text(
                                      itemName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    subtitle: Padding(
                                      padding: EdgeInsets.only(top: 4),
                                      child: Row(
                                        children: [
                                          Text(
                                            'RM ${totalPrice.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: Color(0xFFE732A0),
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            '(Max qty: ${maxQuantity.toInt()})',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // Quantity selector - only show when item is selected
                                  if (isSelected)
                                    Padding(
                                      padding:
                                          EdgeInsets.fromLTRB(16, 0, 16, 12),
                                      child: Container(
                                        padding: EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.blue[50],
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          children: [
                                            Text(
                                              'Quantity to ${_selectedType == RefundType.exchange ? "exchange" : "refund"}:',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.grey[700],
                                              ),
                                            ),
                                            Spacer(),
                                            // Decrease button
                                            InkWell(
                                              onTap: selectedQuantity > 1
                                                  ? () => _onQuantityChanged(
                                                      itemKey,
                                                      selectedQuantity - 1)
                                                  : null,
                                              child: Container(
                                                width: 32,
                                                height: 32,
                                                decoration: BoxDecoration(
                                                  color: selectedQuantity > 1
                                                      ? Colors.white
                                                      : Colors.grey[300],
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: selectedQuantity > 1
                                                        ? Colors.blue
                                                        : Colors.grey[400]!,
                                                  ),
                                                ),
                                                child: Icon(
                                                  Icons.remove,
                                                  size: 18,
                                                  color: selectedQuantity > 1
                                                      ? Colors.blue
                                                      : Colors.grey[600],
                                                ),
                                              ),
                                            ),
                                            SizedBox(width: 12),
                                            // Quantity display
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                  horizontal: 16, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                    color: Colors.blue),
                                              ),
                                              child: Text(
                                                selectedQuantity
                                                    .toInt()
                                                    .toString(),
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.blue[700],
                                                ),
                                              ),
                                            ),
                                            SizedBox(width: 12),
                                            // Increase button
                                            InkWell(
                                              onTap: selectedQuantity <
                                                      maxQuantity
                                                  ? () => _onQuantityChanged(
                                                      itemKey,
                                                      selectedQuantity + 1)
                                                  : null,
                                              child: Container(
                                                width: 32,
                                                height: 32,
                                                decoration: BoxDecoration(
                                                  color: selectedQuantity <
                                                          maxQuantity
                                                      ? Colors.white
                                                      : Colors.grey[300],
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: selectedQuantity <
                                                            maxQuantity
                                                        ? Colors.blue
                                                        : Colors.grey[400]!,
                                                  ),
                                                ),
                                                child: Icon(
                                                  Icons.add,
                                                  size: 18,
                                                  color: selectedQuantity <
                                                          maxQuantity
                                                      ? Colors.blue
                                                      : Colors.grey[600],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                          childCount: _availableItems.length,
                        ),
                      ),

                    // Total Refund/Exchange Amount
                    if (_selectedType != RefundType.full)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(top: 16, bottom: 8),
                          child: Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _selectedType == RefundType.exchange
                                  ? Colors.orange[50]
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                              border: _selectedType == RefundType.exchange
                                  ? Border.all(color: Colors.orange[300]!)
                                  : null,
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _selectedType == RefundType.exchange
                                          ? 'Exchange Amount:'
                                          : 'Total Refund Amount:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      'RM ${_totalRefundAmount.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color:
                                            _selectedType == RefundType.exchange
                                                ? Colors.orange[700]
                                                : Color(0xFFE732A0),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_selectedType == RefundType.exchange &&
                                    _selectedItemsWithQuantity.isNotEmpty)
                                  Padding(
                                    padding: EdgeInsets.only(top: 8),
                                    child: Text(
                                      'You will select new items worth this amount in the next step',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Add some bottom padding
                    SliverToBoxAdapter(
                      child: SizedBox(height: 16),
                    ),
                  ],
                ),
              ),
            ),

            // Actions
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedType == RefundType.exchange
                          ? Colors.orange
                          : Colors.red,
                      foregroundColor: Colors.white,
                      padding:
                          EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    onPressed: _selectedType == RefundType.exchange
                        ? (_selectedItemsWithQuantity.isNotEmpty
                            ? () {
                                // Handle exchange - convert to list format
                                final selectedItemsList =
                                    _selectedItemsWithQuantity.values
                                        .map((item) => {
                                              'name': item['name'],
                                              'item_name': item['item_name'],
                                              'item_code': item['item_code'],
                                              'quantity':
                                                  item['selectedQuantity'],
                                              'price': item['price'],
                                              'custom_variant_info':
                                                  item['custom_variant_info'],
                                            })
                                        .toList();

                                if (widget.onExchange != null) {
                                  widget.onExchange!(selectedItemsList);
                                }
                              }
                            : null)
                        : (_totalRefundAmount > 0
                            ? () {
                                final items =
                                    (widget.order['items'] as List?) ?? [];

                                // Check if all items with full quantities are selected
                                final bool isFullRefund =
                                    _selectedType == RefundType.full;

                                // Prepare items for refund API
                                List<Map<String, dynamic>>? refundItems;

                                if (!isFullRefund &&
                                    _selectedType == RefundType.itemized &&
                                    _selectedItemsWithQuantity.isNotEmpty) {
                                  refundItems = _selectedItemsWithQuantity
                                      .values
                                      .map((item) {
                                    return {
                                      'name': item['name'], // RowID of the item
                                      'qty': -(item['selectedQuantity'] as num)
                                          .toDouble(), // Negative quantity for refund
                                    };
                                  }).toList();
                                }

                                // Return the result directly
                                Navigator.pop(context, {
                                  'orderId':
                                      widget.order['orderId']?.toString() ?? '',
                                  'items': refundItems,
                                });
                              }
                            : null),
                    child: Text(
                      _selectedType == RefundType.exchange
                          ? 'Continue to Exchange'
                          : 'Process Refund',
                      style: TextStyle(fontWeight: FontWeight.bold),
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

  // Helper method to check if all items with full quantities are selected
  bool _isFullOrderSelected(List items) {
    if (_selectedItemsWithQuantity.length != _availableItems.length)
      return false;

    for (var item in _availableItems) {
      final itemKey = item['name'] ?? _availableItems.indexOf(item).toString();
      if (!_selectedItemsWithQuantity.containsKey(itemKey)) return false;

      final maxQty = (item['qty'] ?? item['quantity'] ?? 1).toDouble();
      final selectedQty =
          (_selectedItemsWithQuantity[itemKey]!['selectedQuantity'] as num)
              .toDouble();

      if (selectedQty != maxQty) return false;
    }

    return true;
  }

  Widget _buildRefundTypeTile({
    required RefundType type,
    required String title,
    required String subtitle,
    bool enabled = true,
  }) {
    final isSelected = _selectedType == type;

    return Card(
      elevation: 0,
      margin: EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? Colors.blue : Colors.grey[300]!,
          width: isSelected ? 2 : 1,
        ),
      ),
      color: enabled ? Colors.white : Colors.grey[100],
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled
            ? () {
                _onRefundTypeChanged(type);
              }
            : null,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: [
              Radio<RefundType>(
                value: type,
                groupValue: _selectedType,
                onChanged: enabled
                    ? (value) {
                        _onRefundTypeChanged(value);
                      }
                    : null,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: enabled ? Colors.black : Colors.grey,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: enabled ? Colors.grey[600] : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
