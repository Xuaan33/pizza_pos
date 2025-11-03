import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';
import 'package:fluttertoast/fluttertoast.dart';

class KitchenScreen extends ConsumerStatefulWidget {
  const KitchenScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends ConsumerState<KitchenScreen> {
  List<Map<String, dynamic>> _kitchenStations = [];
  List<Map<String, dynamic>> _kitchenOrders = [];
  String? _selectedKitchenStation;
  bool _isLoadingStations = true;
  bool _isLoadingOrders = false;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadKitchenStations();
  }

  @override
  void dispose() {
    // Clear any potential pending operations
    super.dispose();
  }

  Future<void> _loadKitchenStations() async {
    if (!mounted) return;

    setState(() => _isLoadingStations = true);

    final authState = ref.read(authProvider);
    await authState.whenOrNull(
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
      ) async {
        try {
          final response = await PosService().getKitchenStations(
            posProfile: posProfile,
          );

          if (!mounted) return;

          if (response['success'] == true) {
            final stations = (response['message'] as List?) ?? [];
            setState(() {
              _kitchenStations = stations.cast<Map<String, dynamic>>();
              if (_kitchenStations.isNotEmpty) {
                _selectedKitchenStation = _kitchenStations.first['name'];
                _loadKitchenOrders();
              }
            });
          }
        } catch (e) {
          print('Error loading kitchen stations: $e');
        }
      },
    );
    if (mounted) {
      // Check before setState
      setState(() => _isLoadingStations = false);
    }
  }

  Future<void> _loadKitchenOrders() async {
    if (_selectedKitchenStation == null || !mounted) return;

    if (mounted) {
      setState(() => _isLoadingOrders = true);
    }

    final authState = ref.read(authProvider);
    await authState.whenOrNull(
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
      ) async {
        try {
          final fromDate = DateFormat('yyyy-MM-dd').format(_selectedDate);
          final toDate = DateFormat('yyyy-MM-dd').format(_selectedDate);

          final response = await PosService().getKitchenOrders(
            posProfile: posProfile,
            kitchenStation: _selectedKitchenStation!,
            fromDate: fromDate,
            toDate: toDate,
          );

          if (!mounted) return;

          if (response['success'] == true) {
            final orders = (response['message'] as List?) ?? [];
            if (mounted) {
              setState(() {
                _kitchenOrders = orders.cast<Map<String, dynamic>>();
              });
            }
          }
        } catch (e) {
          print('Error loading kitchen orders: $e');
        }
      },
    );

    if (mounted) {
      setState(() => _isLoadingOrders = false);
    }
  }

  Future<void> _fulfillItem(String posInvoiceItem, bool fulfilled) async {
    try {
      final response = await PosService().fulfillKitchenItem(
        posInvoiceItem: posInvoiceItem,
        fulfilled: fulfilled ? 1 : 0,
      );
      if (!mounted) return;

      if (response['success'] == true) {
        _loadKitchenOrders();

        if (mounted) {
          Fluttertoast.showToast(
            msg: fulfilled ? 'Item marked as fulfilled' : 'Item unmarked',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.green,
            textColor: Colors.white,
            fontSize: 16.0,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Error updating item: $e',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
          fontSize: 16.0,
        );
      }
    }
  }

  Future<void> _fulfillOrder(String posInvoice, bool fulfilled) async {
    if (_selectedKitchenStation == null || !mounted)
      return; // Add mounted check

    try {
      final response = await PosService().fulfillKitchenOrder(
        posInvoice: posInvoice,
        kitchenStation: _selectedKitchenStation!,
        fulfilled: fulfilled ? 1 : 0,
      );

      if (!mounted) return; // Check after async operation

      if (response['success'] == true) {
        _loadKitchenOrders(); // This will have its own mounted checks

        if (mounted) {
          // Check before showing toast
          Fluttertoast.showToast(
            msg: fulfilled ? 'Order marked as fulfilled' : 'Order unmarked',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.green,
            textColor: Colors.white,
            fontSize: 16.0,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        // Check before showing toast
        Fluttertoast.showToast(
          msg: 'Error updating order: $e',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
          fontSize: 16.0,
        );
      }
    }
  }

  Widget _buildVariantInfo(Map<String, dynamic> item) {
    final variantInfo = item['custom_variant_info'];
    if (variantInfo == null) return SizedBox();

    try {
      dynamic parsed =
          variantInfo is String ? jsonDecode(variantInfo) : variantInfo;

      if (parsed is List && parsed.isNotEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: parsed.expand((variant) {
            if (variant is Map && variant['options'] is List) {
              return (variant['options'] as List).take(3).map((option) {
                return Padding(
                  padding: const EdgeInsets.only(left: 4.0, top: 2.0),
                  child: Text(
                    '• ${variant['variant_group']}: ${option['option']}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList();
            }
            return <Widget>[];
          }).toList(),
        );
      }
    } catch (e) {
      print('Error parsing variant info: $e');
    }

    return SizedBox();
  }

  String _getElapsedTime(String? orderTime) {
    if (orderTime == null) return '';
    try {
      final time = DateTime.parse(orderTime);
      final diff = DateTime.now().difference(time);
      if (diff.inMinutes < 60) {
        return '${diff.inMinutes}m';
      }
      return '${diff.inHours}h ${diff.inMinutes % 60}m';
    } catch (e) {
      return '';
    }
  }

  Color _getUrgencyColor(String? orderTime) {
    if (orderTime == null) return Colors.grey;
    try {
      final time = DateTime.parse(orderTime);
      final minutes = DateTime.now().difference(time).inMinutes;
      if (minutes > 30) return Colors.red;
      if (minutes > 15) return Colors.orange;
      return Colors.green;
    } catch (e) {
      return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Kitchen Orders",
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                // Date selector
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.grey.shade300, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextButton.icon(
                    onPressed: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(Duration(days: 365)),
                      );
                      if (picked != null && picked != _selectedDate) {
                        setState(() => _selectedDate = picked);
                        _loadKitchenOrders();
                      }
                    },
                    icon: Icon(Icons.calendar_today, size: 20),
                    label: Text(
                      DateFormat('dd MMM yyyy').format(_selectedDate),
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding:
                          EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),

            // Kitchen Station Pill Buttons
            _isLoadingStations
                ? Center(child: CircularProgressIndicator())
                : _kitchenStations.isEmpty
                    ? Center(
                        child: Text(
                          'No kitchen stations available',
                          style: TextStyle(fontSize: 16),
                        ),
                      )
                    : Container(
                        height: 60,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _kitchenStations.length,
                          itemBuilder: (context, index) {
                            final station = _kitchenStations[index];
                            final isSelected =
                                _selectedKitchenStation == station['name'];

                            return Container(
                              margin: EdgeInsets.only(right: 12),
                              child: ChoiceChip(
                                label: Text(
                                  station['title'] ?? station['name'],
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() {
                                    _selectedKitchenStation = station['name'];
                                  });
                                  _loadKitchenOrders();
                                },
                                selectedColor: Color(0xFFE732A0),
                                backgroundColor: Colors.white,
                                side: BorderSide(
                                  color: isSelected
                                      ? Color(0xFFE732A0)
                                      : Colors.grey.shade300,
                                  width: 2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                              ),
                            );
                          },
                        ),
                      ),

            SizedBox(height: 1),

            // Orders Grid
            Expanded(
              child: _isLoadingOrders
                  ? Center(child: CircularProgressIndicator())
                  : _kitchenOrders.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.restaurant_menu,
                                  size: 80, color: Colors.grey[400]),
                              SizedBox(height: 20),
                              Text(
                                'No orders found for selected date',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount:
                                3, // Changed from 3 to 2 for larger cards
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.75,
                          ),
                          itemCount: _kitchenOrders.length,
                          itemBuilder: (context, index) {
                            final order = _kitchenOrders[index];
                            final items = (order['items'] as List?) ?? [];
                            final isOrderFulfilled =
                                order['custom_fulfilled'] == 1;
                            final unfulfilledItems = items
                                .where((item) => item['custom_fulfilled'] != 1)
                                .length;

                            return _buildOrderCard(
                              order: order,
                              items: items,
                              isOrderFulfilled: isOrderFulfilled,
                              unfulfilledItems: unfulfilledItems,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard({
    required Map<String, dynamic> order,
    required List<dynamic> items,
    required bool isOrderFulfilled,
    required int unfulfilledItems,
  }) {
    final elapsedTime = _getElapsedTime(order['order_time']);
    final urgencyColor = _getUrgencyColor(order['order_time']);

    return Card(
      elevation: isOrderFulfilled ? 1 : 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isOrderFulfilled ? Colors.green : urgencyColor,
          width: 3,
        ),
      ),
      color: isOrderFulfilled ? Colors.green[50] : Colors.white,
      child: Container(
        constraints: BoxConstraints(minHeight: 75, maxHeight: 75),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Order Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'ORDER',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 2),
                        Text(
                          '#${order['name']?.toString().split('-').last ?? 'N/A'}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 24,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 2),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Color(0xFFE732A0).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Color(0xFFE732A0),
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            'TABLE ${order['table']?.toString() ?? 'N/A'}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFE732A0),
                            ),
                          ),
                        ),
                        if (order['order_time'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _formatTime(order['order_time']),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Print Order Button
                  Container(
                    width: 60,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      onPressed: () => _showPrintSelectionDialog(order),
                      icon: Text(
                        'PRINT',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 10),

              // Progress indicator
              if (!isOrderFulfilled)
                Column(
                  children: [
                    LinearProgressIndicator(
                      value: (items.length - unfulfilledItems) / items.length,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(urgencyColor),
                      minHeight: 6,
                    ),
                    SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${items.length - unfulfilledItems}/${items.length} completed',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

              SizedBox(height: 10),

              // Items List (Scrollable)
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!, width: 2),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey[50],
                  ),
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      scrollbars: false,
                    ),
                    child: ListView.builder(
                      physics: BouncingScrollPhysics(),
                      padding: EdgeInsets.all(8),
                      itemCount: items.length,
                      itemBuilder: (context, itemIndex) {
                        final item = items[itemIndex];
                        final isItemFulfilled = item['custom_fulfilled'] == 1;

                        return Container(
                          margin: EdgeInsets.only(bottom: 8),
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isItemFulfilled
                                ? Colors.green[100]
                                : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isItemFulfilled
                                  ? Colors.green
                                  : Colors.grey[300]!,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Checkbox for item fulfillment
                              InkWell(
                                onTap: () {
                                  _showFulfillItemDialog(
                                      item, !isItemFulfilled);
                                },
                                child: Container(
                                  width: 32,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isItemFulfilled
                                        ? Colors.green
                                        : Colors.white,
                                    border: Border.all(
                                      color: isItemFulfilled
                                          ? Colors.green
                                          : Colors.grey.shade400,
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.check,
                                    color: isItemFulfilled
                                        ? Colors.white
                                        : Colors.transparent,
                                    size: 20,
                                  ),
                                ),
                              ),
                              SizedBox(width: 12),
                              // Item details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.orange,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'x${(item['qty'] as num?)?.toStringAsFixed(0) ?? '1'}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            item['item_name']?.toString() ??
                                                'Unknown',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              decoration: isItemFulfilled
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                              color: Colors.black87,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (item['custom_item_remarks'] != null &&
                                        item['custom_item_remarks']
                                            .toString()
                                            .isNotEmpty)
                                      Container(
                                        margin: EdgeInsets.only(top: 6),
                                        padding: EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.orange[50],
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                            color: Colors.orange[200]!,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.comment,
                                              size: 14,
                                              color: Colors.orange[700],
                                            ),
                                            SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                item['custom_item_remarks'],
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.orange[900],
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    _buildVariantInfo(item),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              SizedBox(height: 12),

              // Order Remarks
              if (order['remarks'] != null &&
                  order['remarks'].toString().isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[300]!, width: 2),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 18, color: Colors.orange[800]),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Order Notes: ${order['remarks']}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange[900],
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

              // Status and Action
              SizedBox(height: 12),
              if (!isOrderFulfilled)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => _showFulfillOrderDialog(order, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: Text(
                      'MARK AS COMPLETE',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green, width: 2),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 24),
                      SizedBox(width: 8),
                      Text(
                        'COMPLETED',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[800],
                          letterSpacing: 0.5,
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

  void _showFulfillItemDialog(Map<String, dynamic> item, bool fulfilled) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          fulfilled ? 'Mark Item as Fulfilled?' : 'Unmark Item?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          fulfilled
              ? 'Are you sure you want to mark "${item['item_name']}" as fulfilled?'
              : 'Are you sure you want to unmark "${item['item_name']}"?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _fulfillItem(item['name']?.toString() ?? '', fulfilled);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: fulfilled ? Colors.green : Colors.orange,
            ),
            child: Text(
              fulfilled ? 'Mark Fulfilled' : 'Unmark',
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showFulfillOrderDialog(Map<String, dynamic> order, bool fulfilled) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          fulfilled ? 'Mark Order as Fulfilled?' : 'Unmark Order?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          fulfilled
              ? 'Are you sure you want to mark order ${order['name']} as fulfilled?'
              : 'Are you sure you want to unmark order ${order['name']}?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _fulfillOrder(order['name']?.toString() ?? '', fulfilled);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: fulfilled ? Colors.green : Colors.orange,
            ),
            child: Text(
              fulfilled ? 'Mark Fulfilled' : 'Unmark',
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printSelectedKitchenOrder(
      String posInvoice, List<String> selectedItems) async {
    if (_selectedKitchenStation == null || !mounted) return;

    try {
      final response = await PosService().printSelectedKitchenOrder(
        posInvoice: posInvoice,
        items: selectedItems,
      );

      if (!mounted) return;

      if (response['success'] == true) {
        if (mounted) {
          Fluttertoast.showToast(
            msg: 'Kitchen order sent to printer',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.green,
            textColor: Colors.white,
            fontSize: 16.0,
          );
        }
      } else {
        throw Exception(response['message'] ?? 'Failed to print kitchen order');
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Error printing kitchen order: $e',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
          fontSize: 16.0,
        );
      }
    }
  }

  void _showPrintSelectionDialog(Map<String, dynamic> order) {
    final items = (order['items'] as List?) ?? [];
    final List<bool> selectedItems =
        List.generate(items.length, (index) => false);
    bool selectAll = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            title: Text(
              'Select Items to Print',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Container(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Select All checkbox
                  Container(
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: selectAll,
                          onChanged: (value) {
                            setDialogState(() {
                              selectAll = value ?? false;
                              for (int i = 0; i < selectedItems.length; i++) {
                                selectedItems[i] = selectAll;
                              }
                            });
                          },
                          activeColor: Colors.blue,
                        ),
                        Text(
                          'Select All Items',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12),
                  // Items list
                  Container(
                    constraints: BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final isItemFulfilled = item['custom_fulfilled'] == 1;

                        return Container(
                          margin: EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(8),
                            color: isItemFulfilled
                                ? Colors.green[50]
                                : Colors.white,
                          ),
                          child: CheckboxListTile(
                            value: selectedItems[index],
                            onChanged: (value) {
                              setDialogState(() {
                                selectedItems[index] = value ?? false;
                                // Update selectAll if all items are selected/deselected
                                selectAll = selectedItems.every((item) => item);
                              });
                            },
                            title: Text(
                              item['item_name']?.toString() ?? 'Unknown Item',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                decoration: isItemFulfilled
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: isItemFulfilled
                                    ? Colors.grey[600]
                                    : Colors.black87,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Qty: ${item['qty'] ?? '1'}'),
                                if (item['custom_item_remarks'] != null &&
                                    item['custom_item_remarks']
                                        .toString()
                                        .isNotEmpty)
                                  Text(
                                    'Remarks: ${item['custom_item_remarks']}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange[700],
                                      fontStyle: FontStyle.italic,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                            secondary: Container(
                              padding: EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'x${(item['qty'] as num?)?.toStringAsFixed(0) ?? '1'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: Colors.blue,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.black),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  final selectedItemNames = <String>[];
                  for (int i = 0; i < items.length; i++) {
                    if (selectedItems[i]) {
                      selectedItemNames.add(items[i]['name']?.toString() ?? '');
                    }
                  }

                  if (selectedItemNames.isEmpty) {
                    Fluttertoast.showToast(
                      msg: 'Please select at least one item to print',
                      toastLength: Toast.LENGTH_SHORT,
                      gravity: ToastGravity.BOTTOM,
                      backgroundColor: Colors.orange,
                      textColor: Colors.white,
                      fontSize: 16.0,
                    );
                    return;
                  }

                  Navigator.pop(context);
                  _printSelectedKitchenOrder(
                    order['name']?.toString() ?? '',
                    selectedItemNames,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                ),
                child: Text(
                  'Print Selected',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatTime(String? timeString) {
    if (timeString == null) return 'N/A';
    try {
      final time = DateTime.parse(timeString);
      return DateFormat('HH:mm').format(time);
    } catch (e) {
      return timeString;
    }
  }
}
