import 'package:flutter/material.dart';
import 'package:shiok_pos_android_app/screens/checkout_screen.dart';
import 'home_screen.dart';

class TableScreen extends StatefulWidget {
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
  _TableScreenState createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  String _selectedFloor = 'Ground Floor';
  List<Map<String, dynamic>> _activeOrders = [];

  // Define the tables for each floor
  final Map<String, List<int>> _floorTables = {
    'Ground Floor': [1, 2, 3, 4, 5, 6, 7],
    '2nd Floor': [8, 9, 10, 11, 12, 13, 14, 15],
    'Rooftop': [16, 17, 18, 19, 20, 21],
  };

  // Track tables with submitted but unpaid orders
  Set<int> _tablesWithSubmittedOrders = {};

  void _addNewOrder(int tableNumber, List<Map<String, dynamic>> orderItems) {
    setState(() {
      _activeOrders.add({
        'tableNumber': tableNumber,
        'items': List<Map<String, dynamic>>.from(orderItems),
        'submittedTime': DateTime.now(),
        'isPaid': false, // Add this field
      });
      _tablesWithSubmittedOrders.add(tableNumber);
    });
  }

// Update the _handleTableTap method to properly pass the existing order
  void _handleTableTap(int tableNumber) {
    // Find the existing unpaid order for this table
    var existingOrder = widget.activeOrders.firstWhere(
      (order) => order['tableNumber'] == tableNumber && !order['isPaid'],
      orElse: () => {},
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HomeScreen(
          tableNumber: tableNumber,
          existingOrder: existingOrder.isNotEmpty
              ? List<Map<String, dynamic>>.from(existingOrder['items'])
              : null,
        ),
      ),
    ).then((result) {
      if (result != null) {
        _handleOrderResult(tableNumber, result);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
  }

  Widget _buildTopSection() {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Welcome back, Administrator',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w600,
          ),
        ),

        // Right side - Statistics pills
        Row(
          children: [
            _buildStatPill('Revenue', 'RM ${_getTotalRevenue().toStringAsFixed(2)}', Colors.black),
          const SizedBox(width: 10),
          _buildStatPill('Unpaid Orders', '${widget.tablesWithSubmittedOrders.length}', Colors.black),
          const SizedBox(width: 10),
          _buildStatPill('Tables Free', '${_getTotalTables() - widget.tablesWithSubmittedOrders.length}', Colors.black), // Updated
          ],
        ),
      ],)
    );
  }

  // Get tables with orders for current floor
  // Get total number of tables across all floors
int _getTotalTables() {
  return _floorTables.values.fold(0, (sum, floorTables) => sum + floorTables.length);
}

// Get tables with orders for CURRENT floor (keep your existing method)
Set<int> _getTablesWithOrdersForCurrentFloor() {
  List<int> currentFloorTables = _floorTables[_selectedFloor] ?? [];
  return widget.tablesWithSubmittedOrders
      .where((tableNum) => currentFloorTables.contains(tableNum))
      .toSet();
}

double _getTotalRevenue() {
  return widget.activeOrders
      .where((order) => !order['isPaid'])
      .fold(0.0, (sum, order) {
        double subtotal = order['items'].fold(0.0, 
          (s, item) => s + (item['price'] * item['quantity']));
        return sum + subtotal + (subtotal * 0.16); // 10% service + 6% GST
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
  List<int> tables = _floorTables[_selectedFloor] ?? [];
  
  return GridView.builder(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 6,
      crossAxisSpacing: 5,
      mainAxisSpacing: 5,
      childAspectRatio: 0.85, // Adjusted for better proportions
    ),
    itemCount: tables.length,
    itemBuilder: (context, index) {
      return _buildTableIcon(tables[index]);
    },
  );
}

Widget _buildTableIcon(int tableNumber) {
  bool hasOrder = widget.tablesWithSubmittedOrders.contains(tableNumber);
  double revenue = _getTableRevenue(tableNumber);

  return GestureDetector(
    onTap: () => _handleTableTap(tableNumber),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Table Icon
        Image.asset(
          hasOrder 
            ? 'assets/icon-table-with-order.png' 
            : 'assets/icon-table-empty.png',
          width: 120, // Exact size from reference
          height: 120,
        ),
        const SizedBox(height: 8),
        // Table Info
        Column(
          children: [
            Text(
              'Table $tableNumber',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Max Capacity: 4 Pax',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w600
              ),
            ),
            const SizedBox(height: 4),
            Text(
              revenue > 0 ? 'RM ${revenue.toStringAsFixed(2)}' : 'RM 0',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: hasOrder ? Colors.pink : Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

  Widget _buildTable(int tableNumber) {
  bool hasOrder = widget.tablesWithSubmittedOrders.contains(tableNumber);
  double tableRevenue = _getTableRevenue(tableNumber); // Implement this

  return Card(
    elevation: 2,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Table icon (occupied or empty)
          Image.asset(
            hasOrder 
              ? 'assets/icon-table-with-order.png' 
              : 'assets/icon-table-empty.png',
            width: 40,
            height: 40,
          ),
          SizedBox(height: 8),
          // Table number
          Text(
            'Table $tableNumber',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          // Max capacity
          Text(
            'Max Capacity: 4 Pax',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          // Revenue (RM 0 if empty)
          Text(
            'RM ${tableRevenue.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: hasOrder ? Colors.pink : Colors.grey,
            ),
          ),
        ],
      ),
    ),
  );
}

// Helper to calculate revenue for a table
double _getTableRevenue(int tableNumber) {
  var order = widget.activeOrders.firstWhere(
    (o) => o['tableNumber'] == tableNumber && !o['isPaid'],
    orElse: () => {},
  );
  if (order.isEmpty) return 0.0;
  
  // Calculate subtotal (same as before)
  double subtotal = 0;
  for (var item in order['items']) {
    subtotal += item['price'] * item['quantity'];
  }

  // Add taxes and service charge (matching CheckoutScreen logic)
  double serviceCharge = subtotal * 0.10; // 10% service charge
  double gst = subtotal * 0.06;          // 6% GST
  double total = subtotal + serviceCharge + gst;

  return total; // Now returns the final amount customer pays
}

  Widget _buildFloorSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _floorTables.keys.map((floor) {
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
              backgroundColor: isSelected ? Colors.pink : Colors.white,
              foregroundColor: isSelected ? Colors.white : Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 10,
              ),
            ),
            child: Text(floor),
          ),
        );
      }).toList(),
    );
  }

  // In the _TableScreenState class, add this method:
  void _handleOrderResult(int tableNumber, dynamic result) {
    if (result == null) return;

    if (result['action'] == 'submitted' || result['action'] == 'updated') {
      widget.onOrderSubmitted({
        'tableNumber': tableNumber,
        'items': result['items'],
        'replaceExisting': result['replaceExisting'] ?? false,
      });
    } else if (result['action'] == 'paid') {
      widget.onOrderPaid(tableNumber);
    }
  }
}