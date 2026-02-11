import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';
import 'package:shiok_pos_android_app/components/main_layout.dart';
import 'package:shiok_pos_android_app/screens/checkout_screen.dart';
import 'home_screen.dart';

class TableScreen extends ConsumerStatefulWidget {
  final Set<int> tablesWithSubmittedOrders;
  final Function(Map<String, dynamic>) onOrderSubmitted;
  final Function(int) onOrderPaid;
  final List<Map<String, dynamic>> activeOrders;

  const TableScreen({
    Key? key,
    required this.tablesWithSubmittedOrders,
    required this.onOrderSubmitted,
    required this.onOrderPaid,
    required this.activeOrders,
  }) : super(key: key);

  @override
  ConsumerState<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends ConsumerState<TableScreen>
    with WidgetsBindingObserver {
  String _selectedFloor = '';
  List<String> _floors = [];
  Map<String, List<Map<String, dynamic>>> _floorTables = {};
  bool _isLoading = true;
  bool _isDisposed = false;
  double _totalRevenue = 0.0;
  double _totalUnpaidOrders = 0;
  int _totalTablesFree = 0;
  
  // Track recently merged tables: tableName -> mainTableTitle
  Map<String, String> _mergedTables = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFloorsAndTables();
    _loadTodayInfo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isDisposed = true;
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      _refreshData();
    }
  }

  @override
  void didUpdateWidget(TableScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeOrders != oldWidget.activeOrders) {
      _refreshData();
    }
  }

  Future<void> _refreshData() async {
    await _loadFloorsAndTables();
    await _loadTodayInfo();
  }

  Future<void> _loadFloorsAndTables() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final branch = prefs.getString('branch');
      if (branch == null) throw Exception('Branch not set');

      final posService = PosService();
      final response =
          await _safeApiCall(() => posService.getFloorsAndTables(branch));

      if (response['success'] == true) {
        final floorsData = response['message'];
        print('🚪 Floors Data: $floorsData');
        final floorTables = <String, List<Map<String, dynamic>>>{};
        final floors = <String>[];

        for (var floor in floorsData) {
          final floorName = floor['floor'];
          List<Map<String, dynamic>> tables = [];

          if (floor['tables'] is Map) {
            tables.add(Map<String, dynamic>.from(floor['tables']));
          } else if (floor['tables'] is List) {
            tables = List<Map<String, dynamic>>.from(floor['tables']);
          }

          tables = tables.where((table) {
            final isDefault = (table['is_default'] ?? 0) == 1;
            return !isDefault;
          }).toList();

          if (tables.isNotEmpty) {
            floorTables[floorName] = tables;
            floors.add(floorName);
          }
        }

        if (!_isDisposed) {
          setState(() {
            _floorTables = floorTables;
            _floors = floors;
            _selectedFloor = floors.isNotEmpty ? floors.first : '';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (!_isDisposed) {
        setState(() => _isLoading = false);
        if (mounted && ref.read(authProvider) is AsyncData) {
          Fluttertoast.showToast(
            msg: "Failed to load tables: $e",
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.red,
            textColor: Colors.white,
          );
        }
      }
    }
  }

  Future<void> _loadTodayInfo() async {
    try {
      final response = await _safeApiCall(() => PosService().getTodayInfo());

      if (response['success'] == true) {
        setState(() {
          _totalRevenue = (response['data']['total_revenue'] is int
              ? (response['data']['total_revenue'] as int).toDouble()
              : (response['data']['total_revenue'] ?? 0).toDouble());

          _totalUnpaidOrders = (response['data']['total_unpaid_orders'] is int
              ? (response['data']['total_unpaid_orders'] as int).toDouble()
              : (response['data']['total_unpaid_orders'] ?? 0).toDouble());

          _totalTablesFree = (response['data']['total_table_free'] is double
              ? (response['data']['total_table_free'] as double).toInt()
              : (response['data']['total_table_free'] ?? 0));
        });
      }
    } catch (e) {
      if (!_isDisposed && mounted && ref.read(authProvider) is AsyncData) {
        Fluttertoast.showToast(
          msg: "Failed to load today info: $e",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    }
  }

  void _handleTableTap(Map<String, dynamic> table) async {
    final tableName = table['name']?.toString() ?? '';
    
    // Check if this table was recently merged
    if (_mergedTables.containsKey(tableName)) {
      final mainTableTitle = _mergedTables[tableName];
      Fluttertoast.showToast(
        msg: 'This table has been merged with $mainTableTitle',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.orange,
        textColor: Colors.white,
        toastLength: Toast.LENGTH_LONG,
      );
      return; // Don't allow tapping on merged tables
    }

    final authState = ref.read(authProvider);

    await authState.when(
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
        baseUrl,
        merchantId,
        printMerchantReceiptCopy,
        enableFiuu,
        cashDrawerPinNeeded,
        cashDrawerPin,
      ) async {
        if (!hasOpening) {
          _showOpeningRequiredDialog();
          return;
        }

        final tableNumber = table['title']?.toString() ?? 'Table';
        final tableNum = int.tryParse(tableNumber.split(' ').last) ?? 0;

        Map<String, dynamic>? existingOrder;

        // Check if table has unpaid_order and pos_invoice_name
        final unpaidAmount = table['unpaid_order']?.toDouble() ?? 0.0;
        final posInvoiceName = table['pos_invoice_name']?.toString();

        if (unpaidAmount > 0 &&
            posInvoiceName != null &&
            posInvoiceName.isNotEmpty) {
          try {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => const Center(
                child: CircularProgressIndicator(color: Color(0xFFE732A0)),
              ),
            );

            final ordersResponse =
                await _safeApiCall(() => PosService().getOrders(
                      posProfile: posProfile,
                      search: posInvoiceName,
                      status: 'Draft',
                      pageLength: 1,
                    ));

            if (mounted) Navigator.pop(context);

            // The response structure is: {message: {success: true, message: [orders]}}
            final innerResponse = ordersResponse['message'];

            if (innerResponse != null &&
                innerResponse['success'] == true &&
                innerResponse['message'] != null &&
                innerResponse['message'].isNotEmpty) {
              final orderData = innerResponse['message'][0];

              // Map to HomeScreen format - matching the expected field names
              existingOrder = {
                'orderId': orderData['name'],
                'tableNumber': tableNum,
                'items': (orderData['items'] as List).map((item) {
                  print('   Item: ${item['item_name']} x ${item['qty']}');
                  return {
                    'item_code': item['item_code'],
                    'item_name':
                        item['item_name'], // HomeScreen expects 'item_name'
                    'name':
                        item['item_name'], // Also provide 'name' as fallback
                    'price': (item['rate'] as num).toDouble(),
                    'qty': (item['qty'] as num).toDouble(),
                    'quantity': (item['qty'] as num)
                        .toDouble(), // Also provide 'quantity'
                    'custom_item_remarks': item['custom_item_remarks'] ?? '',
                    'custom_serve_later': item['custom_serve_later'] ?? 0,
                    'custom_variant_info': item['custom_variant_info'],
                    'options': {},
                    'option_text': '',
                    'image': item['image'] ?? '',
                  };
                }).toList(),
                'customerName': orderData['customer_name'] ?? 'Guest',
                'customer_name': orderData['customer_name'] ?? 'Guest',
                'isPaid': false,
                'status': orderData['status'],
                'remarks': orderData['remarks'] ?? '',
              };

            } else {
              print('⚠️ No order found in API response');
            }
          } catch (e) {
            print('❌ Error fetching order: $e');
            if (mounted) {
              if (Navigator.canPop(context)) Navigator.pop(context);
              Fluttertoast.showToast(
                msg: "Failed to load order: $e",
                gravity: ToastGravity.BOTTOM,
                backgroundColor: Colors.red,
                textColor: Colors.white,
              );
            }
          }
        }

        // Fallback to activeOrders
        if (existingOrder == null) {
          final orderFromList = widget.activeOrders.firstWhere(
            (order) => order['tableNumber'] == tableNum && !order['isPaid'],
            orElse: () => {},
          );
          if (orderFromList.isNotEmpty) {
            existingOrder = orderFromList;
          } else {
            print('⚠️ No order in activeOrders either');
          }
        }

        if (mounted) {
          print(
              '🚀 Navigating to HomeScreen with existingOrder: ${existingOrder != null ? 'YES (${existingOrder['items']?.length ?? 0} items)' : 'NO'}');

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => HomeScreen(
                tableNumber: tableNumber,
                existingOrder: existingOrder,
                isTier1: false,
                isDefaultTable: false,
              ),
            ),
          ).then((result) {
            if (result != null) {
              _handleOrderResult(tableNum, result);
            }
          });
        }
      },
      unauthenticated: () async {},
      initial: () async {},
    );
  }

  void _handleTableLongPress(Map<String, dynamic> table) {
    final tableNumber = table['title']?.toString() ?? 'Table';
    final tableNum = int.tryParse(tableNumber.split(' ').last) ?? 0;
    final hasOrder = table['active'] == 1 ||
        table['unpaid_order'] > 0 ||
        widget.tablesWithSubmittedOrders.contains(tableNum);

    if (!hasOrder) {
      Fluttertoast.showToast(
        msg: "This table has no active orders",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    _showTableOptionsDialog(table);
  }

  void _showTableOptionsDialog(Map<String, dynamic> table) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Text(
            table['title']?.toString() ?? 'Table',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.swap_horiz, color: Color(0xFFE732A0)),
                title: const Text(
                  'Transfer Table',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showTransferTableDialog(table);
                },
              ),
              ListTile(
                leading: const Icon(Icons.merge, color: Color(0xFFE732A0)),
                title: const Text(
                  'Merge Table',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showMergeTableDialog(table);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showTransferTableDialog(Map<String, dynamic> sourceTable) {
    final sourceTableTitle = sourceTable['title']?.toString() ?? 'Table';
    final sourceTableNum = int.tryParse(sourceTableTitle.split(' ').last) ?? 0;

    List<Map<String, dynamic>> availableTables = [];
    _floorTables.forEach((floor, tables) {
      for (var table in tables) {
        final tableTitle = table['title']?.toString() ?? '';
        final tableNum = int.tryParse(tableTitle.split(' ').last) ?? 0;
        final hasOrder = table['active'] == 1 ||
            table['unpaid_order'] > 0 ||
            widget.tablesWithSubmittedOrders.contains(tableNum);

        if (tableNum != sourceTableNum) {
          availableTables.add({
            ...table,
            'floor': floor,
            'hasOrder': hasOrder,
          });
        }
      }
    });

    availableTables.sort((a, b) {
      if (a['hasOrder'] != b['hasOrder']) {
        return a['hasOrder'] ? 1 : -1;
      }
      final aNum = int.tryParse(a['title'].toString().split(' ').last) ?? 0;
      final bNum = int.tryParse(b['title'].toString().split(' ').last) ?? 0;
      return aNum.compareTo(bNum);
    });

    Map<String, dynamic>? selectedTable;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text(
                'Transfer Table',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'From: $sourceTableTitle',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'To:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<Map<String, dynamic>>(
                          value: selectedTable,
                          hint: const Text(
                            'Select a table',
                            style: TextStyle(fontSize: 16),
                          ),
                          isExpanded: true,
                          items: availableTables.map((table) {
                            final tableTitle = table['title']?.toString() ?? '';
                            final floor = table['floor']?.toString() ?? '';
                            final hasOrder = table['hasOrder'] ?? false;

                            return DropdownMenuItem<Map<String, dynamic>>(
                              value: table,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '$tableTitle ($floor)',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color:
                                          hasOrder ? Colors.grey : Colors.black,
                                    ),
                                  ),
                                  if (hasOrder)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'Active',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedTable = value;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (selectedTable != null && selectedTable!['hasOrder'])
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Colors.orange),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Warning: This table already has an active order',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: selectedTable == null
                      ? null
                      : () {
                          Navigator.pop(dialogContext);
                          _confirmTransferTable(sourceTable, selectedTable!);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE732A0),
                    disabledBackgroundColor: Colors.grey.shade300,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: const Text(
                    'Confirm',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmTransferTable(
    Map<String, dynamic> sourceTable,
    Map<String, dynamic> targetTable,
  ) {
    final sourceTitle = sourceTable['title']?.toString() ?? 'Table';
    final targetTitle = targetTable['title']?.toString() ?? 'Table';

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Confirm Transfer',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Transfer order from $sourceTitle to $targetTitle?',
            style: const TextStyle(fontSize: 18),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Cancel',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _performTransferTable(sourceTable, targetTable);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE732A0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'Transfer',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performTransferTable(
    Map<String, dynamic> sourceTable,
    Map<String, dynamic> targetTable,
  ) async {
    try {
      final authState = ref.read(authProvider);

      await authState.when(
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
          baseUrl,
          merchantId,
          printMerchantReceiptCopy,
          enableFiuu,
          cashDrawerPinNeeded,
          cashDrawerPin,
        ) async {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const Center(
              child: CircularProgressIndicator(color: Color(0xFFE732A0)),
            ),
          );

          final sourceTableTitle = sourceTable['title']?.toString() ?? 'Table';
          final sourceTableNum =
              int.tryParse(sourceTableTitle.split(' ').last) ?? 0;
          final targetTableFullName = targetTable['name']?.toString() ?? '';
          final posInvoiceName = sourceTable['pos_invoice_name']?.toString();

          Map<String, dynamic>? existingOrder;

          if (posInvoiceName != null && posInvoiceName.isNotEmpty) {
            try {
              final ordersResponse =
                  await _safeApiCall(() => PosService().getOrders(
                        posProfile: posProfile,
                        search: posInvoiceName,
                        status: 'Draft',
                        pageLength: 1,
                      ));

              final innerResponse = ordersResponse['message'];

              if (innerResponse != null &&
                  innerResponse['success'] == true &&
                  innerResponse['message'] != null &&
                  innerResponse['message'].isNotEmpty) {
                final orderData = innerResponse['message'][0];

                existingOrder = {
                  'orderId': orderData['name'],
                  'items': (orderData['items'] as List).map((item) {
                    return {
                      'item_code': item['item_code'],
                      'item_name': item['item_name'],
                      'name': item['item_name'],
                      'price': (item['rate'] as num).toDouble(),
                      'qty': (item['qty'] as num).toDouble(),
                      'quantity': (item['qty'] as num).toDouble(),
                      'custom_item_remarks': item['custom_item_remarks'] ?? '',
                      'custom_serve_later': item['custom_serve_later'] ?? 0,
                      'custom_variant_info': item['custom_variant_info'],
                    };
                  }).toList(),
                  'customerName': orderData['customer_name'] ?? 'Guest',
                  'remarks': orderData['remarks'] ?? '',
                };
              }
            } catch (e) {
              print('❌ Error fetching order from API: $e');
            }
          }

          // Fallback to activeOrders if API fetch failed
          if (existingOrder == null) {
            print('🔄 Trying fallback to activeOrders...');
            final orderFromList = widget.activeOrders.firstWhere(
              (order) =>
                  order['tableNumber'] == sourceTableNum && !order['isPaid'],
              orElse: () => {},
            );
            if (orderFromList.isNotEmpty) {
              existingOrder = orderFromList;
              print('✅ Found order in activeOrders');
            }
          }

          if (mounted) Navigator.pop(context); // Close loading dialog

          if (existingOrder == null || existingOrder.isEmpty) {
            throw Exception('No active order found for source table');
          }

          final orderId = existingOrder['orderId']?.toString();

          if (orderId == null) {
            throw Exception('Order ID not found');
          }

          final items = (existingOrder['items'] as List<dynamic>).map((item) {
            return {
              'item_code': item['item_code'] ?? '',
              'qty': (item['quantity'] ?? item['qty'] ?? 1).toDouble(),
              'price_list_rate': (item['price'] ?? 0).toDouble(),
              'custom_item_remarks': item['custom_item_remarks'] ?? '',
              'custom_serve_later':
                  (item['custom_serve_later'] ?? 0) == 1 ? 1 : 0,
              if (item['custom_variant_info'] != null &&
                  item['custom_variant_info'].toString().isNotEmpty)
                'custom_variant_info': item['custom_variant_info'],
            };
          }).toList();

          final response = await _safeApiCall(() => PosService().submitOrder(
                posProfile: posProfile,
                customer: existingOrder?['customer'] ?? 'Guest',
                items: items,
                table: targetTableFullName,
                orderChannel: 'Dine In',
                name: orderId,
                remarks: existingOrder?['remarks'],
              ));

          if (response['success'] == true) {
            await _refreshData();

            if (mounted) {
              Fluttertoast.showToast(
                msg:
                    'Table transferred successfully from ${sourceTable['title']} to ${targetTable['title']}',
                gravity: ToastGravity.BOTTOM,
                backgroundColor: Colors.green,
                textColor: Colors.white,
              );
            }
          } else {
            throw Exception(response['message'] ?? 'Transfer failed');
          }
        },
        unauthenticated: () async {
          throw Exception('User not authenticated');
        },
        initial: () async {
          throw Exception('Authentication not initialized');
        },
      );
    } catch (e) {
      print('❌ Transfer Error: $e');
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Failed to transfer table: $e',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    }
  }

  // Show merge table dialog - select multiple tables to merge
  void _showMergeTableDialog(Map<String, dynamic> sourceTable) {
    final sourceTableTitle = sourceTable['title']?.toString() ?? 'Table';
    final sourceTableNum = int.tryParse(sourceTableTitle.split(' ').last) ?? 0;

    // Get all tables with active orders from all floors (excluding the source table)
    List<Map<String, dynamic>> tablesWithOrders = [];
    _floorTables.forEach((floor, tables) {
      for (var table in tables) {
        final tableTitle = table['title']?.toString() ?? '';
        final tableNum = int.tryParse(tableTitle.split(' ').last) ?? 0;
        final unpaidAmount = table['unpaid_order']?.toDouble() ?? 0.0;
        final hasOrder = table['active'] == 1 || unpaidAmount > 0;
        
        // Only include tables with orders, excluding the source table
        if (hasOrder && tableNum != sourceTableNum) {
          tablesWithOrders.add({
            ...table,
            'floor': floor,
          });
        }
      }
    });

    if (tablesWithOrders.isEmpty) {
      Fluttertoast.showToast(
        msg: 'No other tables with orders to merge',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.orange,
        textColor: Colors.white,
      );
      return;
    }

    // Sort by table number
    tablesWithOrders.sort((a, b) {
      final aNum = int.tryParse(a['title'].toString().split(' ').last) ?? 0;
      final bNum = int.tryParse(b['title'].toString().split(' ').last) ?? 0;
      return aNum.compareTo(bNum);
    });

    // Track selected tables
    Set<String> selectedTableNames = {sourceTable['name'].toString()};
    List<Map<String, dynamic>> selectedTables = [sourceTable];

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text(
                'Merge Tables',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Main Table: $sourceTableTitle',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFE732A0),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Select tables to merge:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: SingleChildScrollView(
                        child: Column(
                          children: tablesWithOrders.map((table) {
                            final tableName = table['name'].toString();
                            final tableTitle = table['title']?.toString() ?? '';
                            final floor = table['floor']?.toString() ?? '';
                            final unpaidAmount = table['unpaid_order']?.toDouble() ?? 0.0;
                            final isSelected = selectedTableNames.contains(tableName);

                            return CheckboxListTile(
                              title: Text(
                                '$tableTitle (Floor $floor)',
                                style: const TextStyle(fontSize: 16),
                              ),
                              subtitle: Text(
                                'RM ${unpaidAmount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFFE732A0),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              value: isSelected,
                              activeColor: const Color(0xFFE732A0),
                              onChanged: (bool? value) {
                                setDialogState(() {
                                  if (value == true) {
                                    selectedTableNames.add(tableName);
                                    selectedTables.add(table);
                                  } else {
                                    selectedTableNames.remove(tableName);
                                    selectedTables.removeWhere((t) => t['name'] == tableName);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Selected: ${selectedTables.length} table${selectedTables.length > 1 ? 's' : ''}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.blue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: selectedTables.length < 2
                      ? null
                      : () {
                          Navigator.pop(dialogContext);
                          _confirmMergeTables(selectedTables);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE732A0),
                    disabledBackgroundColor: Colors.grey.shade300,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: const Text(
                    'Merge',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Confirm merge tables
  void _confirmMergeTables(List<Map<String, dynamic>> selectedTables) {
    final tableNames = selectedTables.map((t) => t['title'].toString()).join(', ');
    final mainTable = selectedTables.first;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Confirm Merge',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Merge ${selectedTables.length} tables into ${mainTable['title']}?',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 12),
              Text(
                'Tables: $tableNames',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'All orders will be combined into one bill',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Cancel',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _performMergeTables(selectedTables);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE732A0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'Merge',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Perform the actual merge operation
  Future<void> _performMergeTables(List<Map<String, dynamic>> selectedTables) async {
    try {
      final authState = ref.read(authProvider);
      
      await authState.when(
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
          baseUrl,
          merchantId,
          printMerchantReceiptCopy,
          enableFiuu,
          cashDrawerPinNeeded,
          cashDrawerPin,
        ) async {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const Center(
              child: CircularProgressIndicator(color: Color(0xFFE732A0)),
            ),
          );

          print('🔀 MERGE TABLES DEBUG:');
          print('   Tables to merge: ${selectedTables.length}');

          // Collect all POS invoice names
          List<String> posInvoices = [];
          for (var table in selectedTables) {
            final posInvoiceName = table['pos_invoice_name']?.toString();
            if (posInvoiceName != null && posInvoiceName.isNotEmpty) {
              posInvoices.add(posInvoiceName);
              print('   - ${table['title']}: $posInvoiceName');
            }
          }

          if (posInvoices.length < 2) {
            throw Exception('Need at least 2 valid invoices to merge');
          }

          print('📦 Calling merge API with ${posInvoices.length} invoices...');

          final response = await _safeApiCall(() => PosService().mergeOrders(
                posInvoices: posInvoices,
              ));

          if (mounted) Navigator.pop(context); // Close loading dialog

          print('📨 Merge Response: ${response['success']}');

          if (response['success'] == true) {
            // Track merged tables
            final mainTable = selectedTables.first;
            final mainTableTitle = mainTable['title']?.toString() ?? '';
            
            // Mark all other tables as merged (except the main table)
            for (int i = 1; i < selectedTables.length; i++) {
              final tableName = selectedTables[i]['name']?.toString() ?? '';
              if (tableName.isNotEmpty) {
                _mergedTables[tableName] = mainTableTitle;
              }
            }
            
            // Clear merged table markers after 10 seconds
            Future.delayed(const Duration(seconds: 10), () {
              if (mounted) {
                setState(() {
                  for (int i = 1; i < selectedTables.length; i++) {
                    final tableName = selectedTables[i]['name']?.toString() ?? '';
                    _mergedTables.remove(tableName);
                  }
                });
              }
            });

            await _refreshData();

            if (mounted) {
              Fluttertoast.showToast(
                msg: 'Tables merged successfully into ${selectedTables.first['title']}',
                gravity: ToastGravity.BOTTOM,
                backgroundColor: Colors.green,
                textColor: Colors.white,
              );
            }
          } else {
            throw Exception(response['message'] ?? 'Merge failed');
          }
        },
        unauthenticated: () async {
          throw Exception('User not authenticated');
        },
        initial: () async {
          throw Exception('Authentication not initialized');
        },
      );
    } catch (e) {
      print('❌ Merge Error: $e');
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Failed to merge tables: $e',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    }
  }

  void _showOpeningRequiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Opening Entry Required',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Please create an opening entry before taking any orders. '
          'You can create one in the Settings screen.',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              final mainLayout = MainLayout.of(context);
              if (mainLayout != null) {
                mainLayout.setSelectedTabIndex(3);
              }
            },
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFE732A0),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text(
              'Go to Settings',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return authState.when(
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
        baseUrl,
        merchantId,
        printMerchantReceiptCopy,
        enableFiuu,
        cashDrawerPinNeeded,
        cashDrawerPin,
      ) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFE732A0)))
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildFloorSelector(),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _buildStatPill(
                                'Revenue',
                                'RM ${_totalRevenue.toStringAsFixed(2)}',
                                Colors.black,
                              ),
                              const SizedBox(width: 10),
                              _buildStatPill(
                                'Unpaid Orders',
                                '${(_totalUnpaidOrders).toStringAsFixed(2)}',
                                Colors.black,
                              ),
                              const SizedBox(width: 10),
                              _buildStatPill(
                                'Tables Free',
                                '$_totalTablesFree',
                                Colors.black,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: _buildTablesGrid()),
                  ],
                ),
        );
      },
      unauthenticated: () => const Center(
        child: Text('Please log in to view tables'),
      ),
      initial: () => const Center(
        child: CircularProgressIndicator(color: Color(0xFFE732A0)),
      ),
    );
  }

  Widget _buildStatPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTablesGrid() {
    final tables = _floorTables[_selectedFloor] ?? [];

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 5,
        mainAxisSpacing: 5,
        childAspectRatio: 0.85,
      ),
      itemCount: tables.length,
      itemBuilder: (context, index) {
        return _buildTableIcon(tables[index]);
      },
    );
  }

  Widget _buildTableIcon(Map<String, dynamic> table) {
    final tableNumber = table['title']?.toString() ?? 'Table';
    final tableName = table['name']?.toString() ?? '';
    final tableNum = int.tryParse(tableNumber.split(' ').last) ?? 0;
    final hasOrder = table['active'] == 1 ||
        table['unpaid_order'] > 0 ||
        widget.tablesWithSubmittedOrders.contains(tableNum);

    final unpaidAmount = table['unpaid_order']?.toDouble() ?? 0.0;
    final capacity = table['capacity'] ?? 4;
    
    // Check if this table was merged
    final isMerged = _mergedTables.containsKey(tableName);
    final mergedWithTable = _mergedTables[tableName];

    return GestureDetector(
      onTap: () => _handleTableTap(table),
      onLongPress: () => _handleTableLongPress(table),
      child: Opacity(
        opacity: isMerged ? 0.5 : 1.0, // Fade merged tables
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  hasOrder
                      ? 'assets/icon-table-with-order.png'
                      : 'assets/icon-table-empty.png',
                  width: 120,
                  height: 120,
                ),
                SizedBox(height: 8),
                Column(
                  children: [
                    Text(
                      tableNumber,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        decoration: isMerged ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    SizedBox(height: 2),
                    if (isMerged)
                      Text(
                        'Merged with $mergedWithTable',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      )
                    else
                      Text(
                        'Max Capacity: $capacity Pax',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    SizedBox(height: 4),
                    if (!isMerged)
                      Text(
                        'RM ${unpaidAmount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: hasOrder ? const Color(0xFFE732A0) : Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (isMerged)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.orange.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloorSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _floors.map((floor) {
          bool isSelected = _selectedFloor == floor;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedFloor = floor;
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color:
                      isSelected ? const Color(0xFFE732A0) : Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  'Floor ${floor.split(' ').last}',
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _handleOrderResult(int tableNumber, dynamic result) async {
    if (result == null) return;

    try {
      if (result['action'] == 'submitted' || result['action'] == 'updated') {
        widget.onOrderSubmitted({
          'tableNumber': tableNumber,
          'items': result['items'] ?? [],
          'invoice': result['invoice'] ?? {},
          'action': result['action'],
          'entryTime': result['entryTime'] ?? DateTime.now(),
        });
      } else if (result['action'] == 'paid') {
        widget.onOrderPaid(tableNumber);
      } else if (result['action'] == 'deleted') {
        widget.onOrderPaid(tableNumber);
      } else if (result['action'] == 'edit') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(
              tableNumber: "tableNumber",
              existingOrder: result['order'],
            ),
          ),
        );
      }

      await _loadFloorsAndTables();
      await _loadTodayInfo();

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Error handling order result: $e');
      if (mounted) {
        Fluttertoast.showToast(
          msg: "Error processing order: $e",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    }
  }

  Future<T> _safeApiCall<T>(Future<T> Function() apiCall) async {
    try {
      final mainLayout = MainLayout.of(context);
      if (mainLayout != null) {
        return await mainLayout.safeExecuteAPICall(apiCall);
      }
    } catch (e) {
      debugPrint('MainLayout not available: $e');
    }
    return await apiCall();
  }
}