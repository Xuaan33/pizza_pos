import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

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

  const RefundDialog({
    Key? key,
    required this.order,
    required this.paymentMethods,
    required this.onRefund,
    this.onExchange,
  }) : super(key: key);

  @override
  _RefundDialogState createState() => _RefundDialogState();
}

class _RefundDialogState extends State<RefundDialog> {
  RefundType _selectedType = RefundType.full;
  List<Map<String, dynamic>> _selectedItems = [];
  double _totalRefundAmount = 0.0;

  @override
  void initState() {
    super.initState();
    _calculateRefundAmount();
  }

  void _calculateRefundAmount() {
    double amount = 0.0;

    if (_selectedType == RefundType.full) {
      // Full refund - use the order total
      amount = _calculateOrderTotal(widget.order);
    } else if (_selectedType == RefundType.itemized) {
      // Calculate based on selected items
      for (var item in _selectedItems) {
        final quantity = (item['quantity'] as num).toDouble().abs();
        final price = (item['price'] as num).toDouble();
        final variantCost = _calculateVariantCost(item['custom_variant_info']);
        final totalPrice = price + variantCost;
        amount += totalPrice * quantity;
      }
    } else if (_selectedType == RefundType.exchange) {
      // Calculate exchange amount for selected items
      for (var item in _selectedItems) {
        final quantity = (item['quantity'] as num).toDouble().abs();
        final price = (item['price'] as num).toDouble();
        final variantCost = _calculateVariantCost(item['custom_variant_info']);
        final totalPrice = price + variantCost;
        amount += totalPrice * quantity;
      }
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

  void _onItemSelectionChanged(Map<String, dynamic> item, bool selected) {
    setState(() {
      if (selected) {
        _selectedItems.add(item);
      } else {
        _selectedItems.removeWhere((i) => i['name'] == item['name']);
      }
      _calculateRefundAmount();
    });
  }

  void _onRefundTypeChanged(RefundType? type) {
    if (type != null) {
      setState(() {
        _selectedType = type;
        if (type == RefundType.full) {
          _selectedItems.clear();
        } else if (type == RefundType.exchange) {
          _selectedItems.clear();
        }
        _calculateRefundAmount();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = (widget.order['items'] as List?) ?? [];
    final screenHeight = MediaQuery.of(context).size.height;

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
              child: Text(
                'Select Refund Type',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // Content - Use Expanded for scrollable area
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: CustomScrollView(
                  slivers: [
                    // Refund Type Selection
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          _buildRefundTypeTile(
                            type: RefundType.full,
                            title: 'Full Refund',
                            subtitle: 'Refund the entire order amount',
                          ),
                          _buildRefundTypeTile(
                            type: RefundType.itemized,
                            title: 'Itemised Refund',
                            subtitle: 'Select specific items to refund',
                          ),
                          _buildRefundTypeTile(
                            type: RefundType.exchange,
                            title: 'Exchange Item',
                            subtitle: 'Replace items with new ones',
                            enabled: true,
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
                            ],
                          ),
                        ),
                      ),

                    if (_selectedType == RefundType.itemized ||
                        _selectedType == RefundType.exchange)
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = items[index];
                            final isSelected = _selectedItems
                                .any((i) => i['name'] == item['name']);
                            final quantity =
                                (item['qty'] ?? item['quantity'] ?? 1)
                                    .toDouble();
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
                              child: CheckboxListTile(
                                value: isSelected,
                                onChanged: (value) {
                                  _onItemSelectionChanged(
                                    {
                                      'name': item['name'] ?? '',
                                      'item_name': itemName,
                                      'item_code': item['item_code'] ?? '',
                                      'quantity': quantity,
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
                                        '(RM ${totalPrice.toStringAsFixed(2)} x $quantity)',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                          childCount: items.length,
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
                                    _selectedItems.isNotEmpty)
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
                        ? (_selectedItems.isNotEmpty
                            ? () {
                                // Handle exchange - pass selected items to callback
                                if (widget.onExchange != null) {
                                  widget.onExchange!(_selectedItems);
                                }
                              }
                            : null)
                        : (_totalRefundAmount > 0
                            ? () {
                                final items =
                                    (widget.order['items'] as List?) ?? [];

                                // Check if all items are selected
                                final bool isFullRefund = _selectedType ==
                                        RefundType.full ||
                                    (_selectedType == RefundType.itemized &&
                                        _selectedItems.length == items.length);
                                // Prepare items for refund API
                                List<Map<String, dynamic>>? refundItems;

                                if (!isFullRefund &&
                                    _selectedType == RefundType.itemized &&
                                    _selectedItems.isNotEmpty) {
                                  refundItems = _selectedItems.map((item) {
                                    return {
                                      'name': item['name'], // RowID of the item
                                      'qty': -(item['quantity'] as num)
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

  Widget _buildRefundTypeTile({
    required RefundType type,
    required String title,
    required String subtitle,
    bool enabled = true,
  }) {
    final isSelected = _selectedType == type;

    return Card(
      elevation: 0,
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
                if (type == RefundType.exchange) {
                  _onRefundTypeChanged(type);
                } else {
                  _onRefundTypeChanged(type);
                }
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
                        if (type == RefundType.exchange) {
                          _onRefundTypeChanged(value);
                        } else {
                          _onRefundTypeChanged(value);
                        }
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
