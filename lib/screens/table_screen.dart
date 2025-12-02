import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    // Refresh when the screen is focused
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
      final response = await posService.getFloorsAndTables(branch);

      if (response['success'] == true) {
        final floorsData = response['message'];
        final floorTables = <String, List<Map<String, dynamic>>>{};
        final floors = <String>[];

        Map<String, dynamic>? defaultTable;

        for (var floor in floorsData) {
          final floorName = floor['floor'];
          List<Map<String, dynamic>> tables = [];

          // Handle both cases where tables is a Map or List
          if (floor['tables'] is Map) {
            tables.add(Map<String, dynamic>.from(floor['tables']));
          } else if (floor['tables'] is List) {
            tables = List<Map<String, dynamic>>.from(floor['tables']);
          }

          // Check for default table
          for (var table in tables) {
            if (table['is_default'] == 1) {
              defaultTable = table;
              break;
            }
          }

          // Filter out default table from display
          tables = tables.where((table) => table['is_default'] != 1).toList();

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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load tables: $e')),
          );
        }
      }
    }
  }

  Future<void> _loadTodayInfo() async {
    try {
      final response = await PosService().getTodayInfo();

      if (response['success'] == true) {
        setState(() {
          // Ensure we handle both int and double values
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load today info: $e')),
        );
      }
    }
  }

  void _handleTableTap(Map<String, dynamic> table) {
    final authState = ref.read(authProvider);

    authState.when(
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
      ) {
        if (!hasOpening) {
          // Show dialog if no opening entry exists
          _showOpeningRequiredDialog();
          return;
        }

        // Proceed with normal table tap handling
        var existingOrder = widget.activeOrders.firstWhere(
          (order) =>
              order['tableNumber'] ==
                  int.parse(table['title'].split(' ').last) &&
              !order['isPaid'],
          orElse: () => {},
        );

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(
              tableNumber:
                  "int.parse(table['title'].split(' ').last)", // TO FIX
              existingOrder: existingOrder.isNotEmpty ? existingOrder : null,
            ),
          ),
        ).then((result) {
          if (result != null) {
            _handleOrderResult(
                int.parse(table['title'].split(' ').last), result);
          }
        });
      },
      unauthenticated: () {
        // Handle unauthenticated state if needed
      },
      initial: () {
        // Handle initial state if needed
      },
    );
  }

  void _showOpeningRequiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // User must tap button to close
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
              Navigator.pop(dialogContext); // Close the dialog
              // Use the original context (not dialogContext) to find MainLayout
              final mainLayout = MainLayout.of(context);
              if (mainLayout != null) {
                mainLayout.setSelectedTabIndex(3);
              } else {
                print('MainLayout.of(context) returned null');
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final authState = ref.watch(authProvider);

    return authState.when(
        initial: () => const Center(child: CircularProgressIndicator()),
        unauthenticated: () => const Center(child: Text('Unauthorized')),
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
        ) {
          return Container(
            color: Colors.grey[100],
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top section with logo, welcome message and stats
                _buildTopSection(),

                const SizedBox(height: 30),

                // Tables area
                Expanded(
                  child: Column(
                    children: [
                      // Tables grid
                      Expanded(
                        child: _buildTablesGrid(),
                      ),

                      // Floor selector
                      const SizedBox(height: 20),
                      _buildFloorSelector(),
                    ],
                  ),
                ),
              ],
            ),
          );
        });
  }

  Widget _buildTopSection() {
    final authState = ref.read(authProvider);

    return authState.when(
      initial: () => const Center(child: CircularProgressIndicator()),
      unauthenticated: () => const Center(child: Text('Unauthorized')),
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
      ) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Welcome back, $username',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (tier.toLowerCase() == 'tier 3') ...[
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
            ],
          ),
        );
      },
      // ... other cases
    );
  }

  int _getAvailableTablesCount() {
    if (_floorTables.isEmpty) return 0;
    final currentFloorTables = _floorTables[_selectedFloor] ?? [];
    final occupiedTables =
        currentFloorTables.where((table) => table['active'] == 1).length;
    return currentFloorTables.length - occupiedTables;
  }

  double _getTotalRevenue() {
    return widget.activeOrders.where((order) => !order['isPaid']).fold(0.0,
        (sum, order) {
      return sum + _calculateOrderTotal(order);
    });
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
    final tableNumber = table['title'];
    final tableNum = int.parse(table['title'].split(' ').last);
    final hasOrder = table['active'] == 0 ||
        widget.tablesWithSubmittedOrders.contains(tableNum);

    // Calculate unpaid amount for this table
    final unpaidOrder = widget.activeOrders.firstWhere(
      (order) => order['tableNumber'] == tableNum && !order['isPaid'],
      orElse: () => {},
    );

    final unpaidAmount = table['unpaid_order']?.toDouble();

    final capacity = table['capacity'] ?? 4;

    return GestureDetector(
      onTap: () => _handleTableTap(table),
      child: Column(
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
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Max Capacity: $capacity Pax',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 4),
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
              tableNumber: "tableNumber", //TO FIX;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing order: $e')),
        );
      }
    }
  }

  double _calculateOrderSubtotal(Map<String, dynamic> order) {
    return (order['items'] as List).fold(0.0, (sum, item) {
      return sum + (item['price'] ?? 0) * (item['quantity'] ?? 1);
    });
  }

  double _calculateOrderTax(Map<String, dynamic> order) {
    return _calculateOrderSubtotal(order) * 0.06; // 6% GST
  }

  double _calculateOrderTotal(Map<String, dynamic> order) {
    return _calculateOrderSubtotal(order) + _calculateOrderTax(order);
  }
}
