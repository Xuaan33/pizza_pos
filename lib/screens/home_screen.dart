import 'package:flutter/material.dart';
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
  int _selectedFoodType = 0;
  List<Map<String, dynamic>> foodTypes = [
    {
      'name': 'Food',
      'image': 'assets/img-main-food.png'
    },
    {
      'name': 'Drinks',
      'image': 'assets/img-main-drinks.png'
    },
  ];

  // Menu Items Data
  List<Map<String, dynamic>> foodItems = [
    {'name': 'Pepperoni Pizza', 'price': 70.25, 'image': 'assets/pizza.png', 'soldOut': false},
    {'name': 'Margherita Pizza', 'price': 65.50, 'image': 'assets/pizza.png', 'soldOut': false},
    {'name': 'Hawaiian Pizza', 'price': 75.80, 'image': 'assets/pizza.png', 'soldOut': false},
    {'name': 'Veggie Pizza', 'price': 68.90, 'image': 'assets/pizza.png', 'soldOut': true},
    {'name': 'BBQ Chicken Pizza', 'price': 80.00, 'image': 'assets/pizza.png', 'soldOut': false},
    {'name': 'Meat Lovers Pizza', 'price': 85.50, 'image': 'assets/pizza.png', 'soldOut': false},
    {'name': 'Supreme Pizza', 'price': 82.75, 'image': 'assets/pizza.png', 'soldOut': false},
    {'name': 'Cheese Pizza', 'price': 60.00, 'image': 'assets/pizza.png', 'soldOut': false},
    {'name': 'Burger', 'price': 21.98, 'image': 'assets/burger.png', 'soldOut': false},
    {'name': 'Fries', 'price': 16.00, 'image': 'assets/fries.png', 'soldOut': false},
  ];

  List<Map<String, dynamic>> drinkItems = [
    {'name': 'Coca Cola', 'price': 5.50, 'image': 'assets/drinks.jpg', 'soldOut': false},
    {'name': 'Sprite', 'price': 5.50, 'image': 'assets/drinks.jpg', 'soldOut': false},
    {'name': 'Lemon Tea', 'price': 6.00, 'image': 'assets/drinks.jpg', 'soldOut': false},
    {'name': 'Ice Coffee', 'price': 8.50, 'image': 'assets/drinks.jpg', 'soldOut': false},
    {'name': 'Orange Juice', 'price': 7.00, 'image': 'assets/drinks.jpg', 'soldOut': false},
    {'name': 'Mineral Water', 'price': 3.00, 'image': 'assets/drinks.jpg', 'soldOut': true},
    {'name': 'Hot Tea', 'price': 4.50, 'image': 'assets/drinks.jpg', 'soldOut': false},
    {'name': 'Milkshake', 'price': 12.00, 'image': 'assets/drinks.jpg', 'soldOut': false},
  ];

  // Current Order Items
  late List<Map<String, dynamic>> currentOrderItems;

  // Search functionality
  String searchQuery = '';
  TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Initialize order items with existing order if provided
    if (widget.existingOrder != null && widget.existingOrder!.isNotEmpty) {
      currentOrderItems = List.from(widget.existingOrder!);
    } else {
      currentOrderItems = [];
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get the correct items list based on selection
    List<Map<String, dynamic>> displayedItems = _selectedFoodType == 0 ? foodItems : drinkItems;
    
    // Filter by search if needed
    if (searchQuery.isNotEmpty) {
      displayedItems = displayedItems.where((item) => 
        item['name'].toLowerCase().contains(searchQuery.toLowerCase())
      ).toList();
    }

    return Scaffold(
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
                                  Navigator.pop(context);
                                },
                              ),
                              const SizedBox(width: 8),
                              Image.asset('assets/logo-shiokpos.png', height: 40),
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        children: List.generate(foodTypes.length, (index) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _selectedFoodType = index;
                                  // Clear search when switching categories
                                  searchController.clear();
                                  searchQuery = '';
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _selectedFoodType == index
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
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset(
                                    foodTypes[index]['image'],
                                    width: 24,
                                    height: 24,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(foodTypes[index]['name']),
                                ],
                              ),
                            ),
                          );
                        }),
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
        
            // Current Order Section - Only show if there are items in the order
            if (currentOrderItems.isNotEmpty)
              Container(
                width: 300,
                color: Colors.white,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Table ${widget.tableNumber} Order',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setState(() {
                                // Clear the order instead of going back
                                currentOrderItems.clear();
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: currentOrderItems.length,
                        itemBuilder: (context, index) {
                          return _buildOrderItem(currentOrderItems[index], index);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          _buildOrderSummaryRow('Sub Total', 'RM ${_calculateSubtotal().toStringAsFixed(2)}'),
                          _buildOrderSummaryRow('Service Charge (10%)', 'RM ${_calculateServiceCharge().toStringAsFixed(2)}'),
                          _buildOrderSummaryRow('GST (6%)', 'RM ${_calculateGST().toStringAsFixed(2)}'),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed: () {
                              // Navigate to checkout screen
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CheckoutScreen(
                                    tableNumber: widget.tableNumber,
                                    orderItems: currentOrderItems,
                                  ),
                                ),
                              ).then((orderCompleted) {
                                // If order was completed, return to previous screen
                                if (orderCompleted == true) {
                                  // Return current order items to previous screen (if coming from checkout)
                                  Navigator.pop(context, currentOrderItems);
                                }
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.pink,
                              minimumSize: const Size.fromHeight(50),
                            ),
                            child: Text(
                              'Order Total RM ${_calculateTotal().toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
    );
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text('RM ${item['price'].toStringAsFixed(2)}'),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: () {
                  _decreaseQuantity(index);
                },
              ),
              Text('${item['quantity']}'),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () {
                  _increaseQuantity(index);
                },
              ),
            ],
          ),
        ],
      ),
    );
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
      int existingIndex = currentOrderItems.indexWhere((orderItem) => 
        orderItem['name'] == item['name']
      );
      
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