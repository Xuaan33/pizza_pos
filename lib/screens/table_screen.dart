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

class _TableScreenState extends ConsumerState<TableScreen> {
  String _selectedFloor = '';
  List<String> _floors = [];
  Map<String, List<Map<String, dynamic>>> _floorTables = {};
  bool _isLoading = true;
  bool _isDisposed = false;
  double _totalRevenue = 0.0;
  int _totalUnpaidOrders = 0;
  int _totalTablesFree = 0;

  @override
  void initState() {
    super.initState();
    _loadFloorsAndTables();
    _loadTodayInfo();
  }

  @override
  void dispose() {
    _isDisposed = true; // Mark as disposed
    super.dispose();
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

        for (var floor in floorsData) {
          final floorName = floor['floor'];
          final tables = List<Map<String, dynamic>>.from(floor['tables']);
          floorTables[floorName] = tables;
          floors.add(floorName);
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
        // Only show error if we're still mounted and authenticated
        if (mounted && ref.read(authProvider) is AsyncData) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load tables: $e')),
          );
        }
      }
    }
  }

  Future<void> _loadTodayInfo() async {
    // Check auth state before loading
    final authState = ref.read(authProvider);
    if (authState is! AsyncData) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final branch = prefs.getString('branch');

      // Only proceed if we're authenticated and have branch information
      if (branch == null || _isDisposed) return;

      final posService = PosService();
      final response = await posService.getTodayInfo();

      if (_isDisposed) return; // Check again before setState

      if (response['success'] == true) {
        if (!_isDisposed) {
          // Final check before setState
          setState(() {
            _totalRevenue = (response['data']['total_revenue'] ?? 0).toDouble();
            _totalUnpaidOrders = response['data']['total_unpaid_orders'] ?? 0;
            _totalTablesFree = response['data']['total_table_free'] ?? 0;
          });
        }
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
    // Find the existing unpaid order for this table
    var existingOrder = widget.activeOrders.firstWhere(
      (order) =>
          order['tableNumber'] == int.parse(table['title'].split(' ').last) &&
          !order['isPaid'],
      orElse: () => {},
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HomeScreen(
          tableNumber: int.parse(table['title'].split(' ').last),
          existingOrder: existingOrder.isNotEmpty
              ? List<Map<String, dynamic>>.from(existingOrder['items'])
              : null,
        ),
      ),
    ).then((result) {
      if (result != null) {
        _handleOrderResult(int.parse(table['title'].split(' ').last), result);
      }
    });
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
        authenticated: (sid, apiKey, apiSecret, username, email, fullName,
            posProfile, branch) {
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
    return FutureBuilder(
      future: SharedPreferences.getInstance(),
      builder: (context, snapshot) {
        final username = snapshot.hasData
            ? snapshot.data!.getString('username') ?? 'Administrator'
            : 'Administrator';

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
                    '$_totalUnpaidOrders',
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
        );
      },
    );
  }

  int _getAvailableTablesCount() {
    if (_floorTables.isEmpty) return 0;
    final currentFloorTables = _floorTables[_selectedFloor] ?? [];
    final occupiedTables =
        currentFloorTables.where((table) => table['active'] == 1).length;
    return currentFloorTables.length - occupiedTables;
  }

  // Update the _getTotalRevenue method in table_screen.dart
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

  // In table_screen.dart, modify _buildTableIcon
// Update the _buildTableIcon method in table_screen.dart
  Widget _buildTableIcon(Map<String, dynamic> table) {
    final tableNumber = table['title'];
    final tableNum = int.parse(table['title'].split(' ').last);
    final hasOrder = table['active'] == 1 ||
        widget.tablesWithSubmittedOrders.contains(tableNum);

    // Calculate unpaid amount for this table
    final unpaidOrder = widget.activeOrders.firstWhere(
      (order) => order['tableNumber'] == tableNum && !order['isPaid'],
      orElse: () => {},
    );

    final unpaidAmount = unpaidOrder.isNotEmpty
        ? _calculateOrderTotal(unpaidOrder)
        : table['unpaid_order']?.toDouble();

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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _floors.map((floor) {
        bool isSelected = _selectedFloor == floor;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _selectedFloor = floor;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isSelected ? const Color(0xFFE732A0) : Colors.white,
                foregroundColor: isSelected ? Colors.white : Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
              ),
              child: Text(
                floor,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              )),
        );
      }).toList(),
    );
  }

  // In table_screen.dart, modify the _handleOrderResult method
  void _handleOrderResult(int tableNumber, dynamic result) {
    if (result == null) return;

    if (result['action'] == 'submitted' || result['action'] == 'updated') {
      widget.onOrderSubmitted({
        'tableNumber': tableNumber,
        'items': result['items'],
        'action': result['action'],
        'replaceExisting': result['replaceExisting'] ?? false,
        'entryTime': result['entryTime'] ?? DateTime.now(),
      });
    } else if (result['action'] == 'paid') {
      widget.onOrderPaid(tableNumber);
    }

    // Always refresh table data
    _loadFloorsAndTables();
  }

// In table_screen.dart, add these methods to _TableScreenState
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
