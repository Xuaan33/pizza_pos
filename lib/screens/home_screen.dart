import 'package:flutter/material.dart';
import 'package:shiok_pos_android_app/components/main_layout.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';
import 'checkout_screen.dart';

class HomeScreen extends StatefulWidget {
  final int tableNumber;
  final List<Map<String, dynamic>>? existingOrder;

  const HomeScreen({
    Key? key,
    required this.tableNumber,
    this.existingOrder,
  }) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedItemGroupIndex = 0;
  List<Map<String, dynamic>> itemGroups = [];
  String _selectedItemGroup = 'All';
  bool _isLoadingItemGroups = true;

  @override
  void initState() {
    super.initState();
    _loadItemGroups();
    currentOrderItems =
        widget.existingOrder != null ? List.from(widget.existingOrder!) : [];
  }

  Future<void> _loadItemGroups() async {
    try {
      final posService = PosService();
      final response = await posService.getItemGroups();
      
      if (response['success'] == true) {
        setState(() {
          itemGroups = List<Map<String, dynamic>>.from(
            response['message']['item_groups']
          );
          _isLoadingItemGroups = false;
        });
      } else {
        throw Exception('Failed to load item groups');
      }
    } catch (e) {
      setState(() => _isLoadingItemGroups = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading item groups: $e')),
      );
    }
  }


  // Menu Items Data
  List<Map<String, dynamic>> foodItems = [
    {
      'name': 'Pepperoni Pizza',
      'price': 70.25,
      'image': 'assets/pizza.png',
      'soldOut': false
    },
    {
      'name': 'Margherita Pizza',
      'price': 65.50,
      'image': 'assets/pizza.png',
      'soldOut': false
    },
    {
      'name': 'Hawaiian Pizza',
      'price': 75.80,
      'image': 'assets/pizza.png',
      'soldOut': false
    },
    {
      'name': 'Veggie Pizza',
      'price': 68.90,
      'image': 'assets/pizza.png',
      'soldOut': true
    },
    {
      'name': 'BBQ Chicken Pizza',
      'price': 80.00,
      'image': 'assets/pizza.png',
      'soldOut': false
    },
    {
      'name': 'Meat Lovers Pizza',
      'price': 85.50,
      'image': 'assets/pizza.png',
      'soldOut': false
    },
    {
      'name': 'Supreme Pizza',
      'price': 82.75,
      'image': 'assets/pizza.png',
      'soldOut': false
    },
    {
      'name': 'Cheese Pizza',
      'price': 60.00,
      'image': 'assets/pizza.png',
      'soldOut': false
    }
  ];

  List<Map<String, dynamic>> drinkItems = [
    {
      'name': 'Coca Cola',
      'price': 5.50,
      'image': 'assets/drinks.jpg',
      'soldOut': false
    },
    {
      'name': 'Sprite',
      'price': 5.50,
      'image': 'assets/drinks.jpg',
      'soldOut': false
    },
    {
      'name': 'Lemon Tea',
      'price': 6.00,
      'image': 'assets/drinks.jpg',
      'soldOut': false
    },
    {
      'name': 'Ice Coffee',
      'price': 8.50,
      'image': 'assets/drinks.jpg',
      'soldOut': false
    },
    {
      'name': 'Orange Juice',
      'price': 7.00,
      'image': 'assets/drinks.jpg',
      'soldOut': false
    },
    {
      'name': 'Mineral Water',
      'price': 3.00,
      'image': 'assets/drinks.jpg',
      'soldOut': true
    },
    {
      'name': 'Hot Tea',
      'price': 4.50,
      'image': 'assets/drinks.jpg',
      'soldOut': false
    },
    {
      'name': 'Milkshake',
      'price': 12.00,
      'image': 'assets/drinks.jpg',
      'soldOut': false
    },
  ];

  // Current Order Items
  late List<Map<String, dynamic>> currentOrderItems;

  // Search functionality
  String searchQuery = '';
  TextEditingController searchController = TextEditingController();


  @override
  Widget build(BuildContext context) {
    // Get the correct items list based on selection
    List<Map<String, dynamic>> displayedItems =
        _selectedItemGroupIndex == 0 ? foodItems : drinkItems;

    // Filter by search if needed
    if (searchQuery.isNotEmpty) {
      displayedItems = displayedItems
          .where((item) =>
              item['name'].toLowerCase().contains(searchQuery.toLowerCase()))
          .toList();
    }

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              // Main Content
              Expanded(
                child: Container(
                  color: Colors.white,
                  child: Column(
                    children: [
                      // Top Bar with Back Button
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                // Back Button
                                IconButton(
                                  icon: const Icon(Icons.arrow_back),
                                  onPressed: () {
                                    _onBackPressed();
                                  },
                                ),
                                const SizedBox(width: 8),
                                Image.asset('assets/logo-shiokpos.png',
                                    height: 40),
                                const SizedBox(width: 10),
                                Text(
                                  'Welcome back, ABC - Table ${widget.tableNumber}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Revenue RM ${_calculateTotalRevenue().toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Food/Drinks Selector with Images
                      // Item Groups Selector
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: _isLoadingItemGroups
                          ? CircularProgressIndicator()
                          : SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: List.generate(itemGroups.length, (index) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: ElevatedButton(
                                      onPressed: () {
                                        setState(() {
                                          _selectedItemGroupIndex = index;
                                          _selectedItemGroup = itemGroups[index]['value'];
                                          // Clear search when switching categories
                                          searchController.clear();
                                          searchQuery = '';
                                        });
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _selectedItemGroupIndex == index
                                            ? Colors.yellow
                                            : Colors.white,
                                        foregroundColor: Colors.black,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                      ),
                                      child: Text(itemGroups[index]['name']),
                                    ),
                                  );
                                }),
                              ),
                            ),
                    ),

                      // Search Bar
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: TextField(
                          controller: searchController,
                          onChanged: (value) {
                            setState(() {
                              searchQuery = value;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search for food, drinks, etc',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),

                      // Menu Grid
                      Expanded(
                        child: GridView.builder(
                          padding: const EdgeInsets.all(16.0),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.8,
                          ),
                          itemCount: displayedItems.length,
                          itemBuilder: (context, index) {
                            return _buildMenuItem(displayedItems[index], index);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Container(
      width: 1,
      height: double.infinity,
      color: Colors.grey[300],
    ),

              // Current Order Section - Only show if there are items in the order
                Container(
                  width: 400,
                  color: Colors.white,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Current Order',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: currentOrderItems.length,
                          itemBuilder: (context, index) {
                            return _buildOrderItem(
                                currentOrderItems[index], index);
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Divider(
                              color: const Color(0xFFE732A0), // Pink divider
                              thickness: 1,
                              height: 20,
                            ),
                            _buildOrderSummaryRow('Sub Total',
                                'RM ${_calculateSubtotal().toStringAsFixed(2)}'),
                            _buildOrderSummaryRow('Service Charge (10%)',
                                'RM ${_calculateServiceCharge().toStringAsFixed(2)}'),
                            _buildOrderSummaryRow('GST (6%)',
                                'RM ${_calculateGST().toStringAsFixed(2)}'),
                            const SizedBox(height: 10),
                            // Vertical buttons
                            Column(
                              children: [
                                // Submit Order Button
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _submitOrder,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      minimumSize: const Size.fromHeight(50),
                                    ),
                                    child: const Text(
                                      'Submit Order',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.black,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                // Checkout Button
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _goToCheckout,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE732A0),
                                      minimumSize: const Size.fromHeight(50),
                                    ),
                                    child: Text(
                                      'Checkout RM ${_calculateTotal().toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
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

  // Handle back button press with confirmation dialog
  Future<bool> _onWillPop() async {
    if (currentOrderItems.isEmpty) {
      return true;
    }
    return _onBackPressed();
  }

  Future<bool> _onBackPressed() async {
    if (currentOrderItems.isEmpty) {
      Navigator.pop(context);
      return true;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard Order?'),
        content: const Text(
            'Are you sure you want to discard this order and go back?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DISCARD'),
          ),
        ],
      ),
    );

    if (result ?? false) {
      if (!mounted) return false;
      Navigator.pop(context);
      return true;
    }
    return false;
  }

void _submitOrder() {
  bool hasExistingOrder = widget.existingOrder != null && widget.existingOrder!.isNotEmpty;

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(hasExistingOrder ? 'Update Order' : 'Submit Order'),
      content: Text(hasExistingOrder 
          ? 'Update this order?'
          : 'Submit this order to kitchen?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            Navigator.pop(context, {
              'action': hasExistingOrder ? 'updated' : 'submitted',
              'items': currentOrderItems,
              'replaceExisting': hasExistingOrder,
              'entryTime': DateTime.now(),
            });
          },
          child: Text(hasExistingOrder ? 'UPDATE' : 'SUBMIT'),
        ),
      ],
    ),
  );
}

 void _goToCheckout() {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => CheckoutScreen(
        order: {
          'tableNumber': widget.tableNumber,
          'items': List<Map<String, dynamic>>.from(currentOrderItems),
          'entryTime': DateTime.now(),
        },
      ),
    ),
  ).then((orderCompleted) {
    if (orderCompleted == true) {
      // No need to pop here - just select the Orders tab
      MainLayout.of(context)?.selectOrdersTab();
    }
  });
}

  Widget _buildMenuItem(Map<String, dynamic> item, int index) {
    return GestureDetector(
      onTap: () {
        if (!item['soldOut']) {
          _addToOrder(item);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(15)),
                    child: Image.asset(
                      item['image'],
                      fit: BoxFit.cover,
                      width: double.infinity,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    children: [
                      Text(
                        item['name'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'RM ${item['price'].toStringAsFixed(2)}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (item['soldOut']) _buildSoldOutOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildSoldOutOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(15),
        ),
        child: const Center(
          child: Text(
            'SOLD OUT',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOrderItem(Map<String, dynamic> item, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              item['image'],
              width: 60,
              height: 60,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (item['remarks'] != null && item['remarks'].isNotEmpty)
                  Text(
                    'Remarks: ${item['remarks']}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
              ],
            ),
          ),
          // Quantity controls
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove, size: 20),
                onPressed: () => _decreaseQuantity(index),
              ),
              Text('${item['quantity']}'),
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                onPressed: () => _increaseQuantity(index),
              ),
              // Cross icon to remove item
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => _removeItem(index),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _removeItem(int index) {
    setState(() {
      currentOrderItems.removeAt(index);
    });
  }

  Widget _buildOrderSummaryRow(String label, String amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(amount),
        ],
      ),
    );
  }

  // Logic functions
  void _addToOrder(Map<String, dynamic> item) {
    setState(() {
      int existingIndex = currentOrderItems
          .indexWhere((orderItem) => orderItem['name'] == item['name']);

      if (existingIndex != -1) {
        currentOrderItems[existingIndex]['quantity']++;
      } else {
        Map<String, dynamic> newOrderItem = Map.from(item);
        newOrderItem['quantity'] = 1;
        currentOrderItems.add(newOrderItem);
      }
    });
  }

  void _increaseQuantity(int index) {
    setState(() {
      currentOrderItems[index]['quantity']++;
    });
  }

  void _decreaseQuantity(int index) {
    setState(() {
      if (currentOrderItems[index]['quantity'] > 1) {
        currentOrderItems[index]['quantity']--;
      } else {
        // Remove item if quantity becomes 0
        currentOrderItems.removeAt(index);
      }
    });
  }

  double _calculateSubtotal() {
    double subtotal = 0;
    for (var item in currentOrderItems) {
      subtotal += (item['price'] * item['quantity']);
    }
    return subtotal;
  }

  double _calculateServiceCharge() {
    return _calculateSubtotal() * 0.10; // 10% of subtotal
  }

  double _calculateGST() {
    return _calculateSubtotal() * 0.06; // 6% of subtotal
  }

  double _calculateTotal() {
    return _calculateSubtotal() + _calculateServiceCharge() + _calculateGST();
  }

  double _calculateTotalRevenue() {
    // For demo purposes, just showing the current order total
    // In a real app, this would track all completed orders
    return _calculateTotal();
  }
}
