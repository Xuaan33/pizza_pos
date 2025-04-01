import 'package:flutter/material.dart';
import 'home_screen.dart';

class TableScreen extends StatefulWidget {
  const TableScreen({Key? key}) : super(key: key);

  @override
  _TableScreenState createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  String _selectedFloor = 'Ground Floor';
  
  // Define the tables for each floor
  final Map<String, List<int>> _floorTables = {
    'Ground Floor': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
    '2nd Floor': [13, 14, 15, 16, 17, 18, 19, 20],
    'Rooftop': [21, 22, 23, 24, 25, 26],
  };
  
  // Track tables with completed orders
  Set<int> _tablesWithOrders = {};

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Container(
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
      ),
    );
  }

  Widget _buildTopSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Left side - Logo and welcome message
        Row(
          children: [
            const Text(
              'Welcome back, ABC',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        
        // Right side - Statistics pills
        Row(
          children: [
            _buildStatPill('Revenue', 'RM 888.88', Colors.black),
            const SizedBox(width: 10),
            _buildStatPill('Unpaid Orders', 'RM 258.88', Colors.black),
            const SizedBox(width: 10),
            _buildStatPill('Tables Free', '${_floorTables[_selectedFloor]!.length - _getTablesWithOrdersForCurrentFloor().length}', Colors.black),
          ],
        ),
      ],
    );
  }

  // Get tables with orders for current floor
  Set<int> _getTablesWithOrdersForCurrentFloor() {
    List<int> currentFloorTables = _floorTables[_selectedFloor] ?? [];
    return _tablesWithOrders.where((tableNum) => currentFloorTables.contains(tableNum)).toSet();
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
              fontWeight: FontWeight.w500,
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
    
    // Set up table positions based on the image
    // For Ground Floor, create a specific layout matching the image
    if (_selectedFloor == 'Ground Floor') {
      return Stack(
        children: [
          // Tables 1-5 (top row)
          Positioned(
            top: 20,
            left: 100,
            child: _buildTableRow([1, 2, 3, 4, 5]),
          ),
          
          // Tables 6-10 (bottom row)
          Positioned(
            top: 150,
            left: 100,
            child: _buildTableRow([6, 7, 8, 9, 10]),
          ),
          
          // Table 11 (large table on right)
          Positioned(
            top: 20,
            right: 100,
            child: _buildTable(11, isLarge: true),
          ),
          
          // Table 12 (bottom right)
          Positioned(
            top: 200,
            right: 100,
            child: _buildTable(12),
          ),
        ],
      );
    } else {
      // For other floors, create a more generic layout
      return GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          crossAxisSpacing: 20,
          mainAxisSpacing: 20,
        ),
        itemCount: tables.length,
        itemBuilder: (context, index) {
          return _buildTable(tables[index]);
        },
      );
    }
  }

  Widget _buildTableRow(List<int> tableNumbers) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: tableNumbers.map((tableNum) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: _buildTable(tableNum),
        );
      }).toList(),
    );
  }

  Widget _buildTable(int tableNumber, {bool isLarge = false}) {
    // Check if this table has completed orders
    bool hasOrder = _tablesWithOrders.contains(tableNumber);
    
    return GestureDetector(
      onTap: () {
        // Navigate to HomeScreen with the selected table number
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(tableNumber: tableNumber),
          ),
        ).then((result) {
          // When returning from HomeScreen, check if order was completed
          if (result == true) {
            setState(() {
              _tablesWithOrders.add(tableNumber);
            });
          }
        });
      },
      child: Container(
        width: isLarge ? 100 : 80,
        height: isLarge ? 160 : 80,
        decoration: BoxDecoration(
          color: hasOrder ? Colors.green[100] : Colors.white,
          border: Border.all(color: hasOrder ? Colors.green : Colors.grey[400]!),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          children: [
            // Table border decorations (corners)
            Positioned(
              top: 0,
              left: 0,
              child: _buildTableCorner(hasOrder),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: _buildTableCorner(hasOrder),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              child: _buildTableCorner(hasOrder),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: _buildTableCorner(hasOrder),
            ),
            
            // Table number
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tableNumber.toString(),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: hasOrder ? Colors.green[800] : Colors.black,
                    ),
                  ),
                  if (hasOrder)
                    Text(
                      'Ordered',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[800],
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

  Widget _buildTableCorner(bool hasOrder) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: hasOrder ? Colors.green : Colors.white,
        shape: BoxShape.circle,
      ),
    );
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
}