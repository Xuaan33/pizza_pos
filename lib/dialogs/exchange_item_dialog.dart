import 'dart:convert';
import 'package:flutter/material.dart';

class ExchangeItemsDialog extends StatefulWidget {
  final Map<String, dynamic> order;
  final Function(List<Map<String, dynamic>>) onItemsSelected;

  const ExchangeItemsDialog({
    Key? key,
    required this.order,
    required this.onItemsSelected,
  }) : super(key: key);

  @override
  _ExchangeItemsDialogState createState() => _ExchangeItemsDialogState();
}

class _ExchangeItemsDialogState extends State<ExchangeItemsDialog> {
  List<Map<String, dynamic>> _selectedItems = [];
  double _totalExchangeAmount = 0.0;

  @override
  void initState() {
    super.initState();
  }

  void _calculateExchangeAmount() {
    double amount = 0.0;

    for (var item in _selectedItems) {
      final quantity = (item['quantity'] as num).toDouble().abs();
      final price = (item['price'] as num).toDouble();
      final variantCost = _calculateVariantCost(item['custom_variant_info']);
      final totalPrice = price + variantCost;
      amount += totalPrice * quantity;
    }

    setState(() {
      _totalExchangeAmount = amount;
    });
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
      _calculateExchangeAmount();
    });
  }

  List<Widget> _buildVariantText(Map<String, dynamic> item) {
    dynamic variantInfo = item['custom_variant_info'];

    if (variantInfo == null) return [];

    while (variantInfo is String) {
      try {
        variantInfo = jsonDecode(variantInfo);
      } catch (e) {
        debugPrint('Error parsing variant info: $e');
        return [];
      }
    }

    if (variantInfo is List) {
      return variantInfo.expand((variant) {
        if (variant is Map && variant['options'] is List) {
          return (variant['options'] as List).map((option) {
            return Text(
              '• ${variant['variant_group']}: ${option['option']}'
              '${option['additional_cost'] > 0 ? ' (+RM${option['additional_cost'].toStringAsFixed(2)})' : ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            );
          }).toList();
        }
        return <Widget>[];
      }).toList();
    }

    return [];
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
                'Select Items to Exchange',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 12),
                        child: Text(
                          'Select the items you want to exchange:',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ),

                    // Item Selection List
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final item = items[index];
                          final isSelected = _selectedItems
                              .any((i) => i['name'] == item['name']);
                          final quantity =
                              (item['qty'] ?? item['quantity'] ?? 1).toDouble();
                          final price = (item['price'] ??
                                  item['rate'] ??
                                  item['price_list_rate'] ??
                                  0)
                              .toDouble();
                          final variantCost =
                              _calculateVariantCost(item['custom_variant_info']);
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
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    itemName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  ..._buildVariantText(item),
                                ],
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
                                      '(RM ${totalPrice.toStringAsFixed(2)} x ${quantity.toStringAsFixed(0)})',
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

                    // Total Exchange Amount
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(top: 16, bottom: 8),
                        child: Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange[300]!),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Exchange Amount:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                'RM ${_totalExchangeAmount.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Colors.orange[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

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
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding:
                          EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    onPressed: _selectedItems.isNotEmpty
                        ? () {
                            widget.onItemsSelected(_selectedItems);
                            Navigator.pop(context);
                          }
                        : null,
                    child: Text(
                      'Continue',
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
}