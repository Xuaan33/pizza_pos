import 'package:flutter/material.dart';
import 'package:shiok_pos_android_app/components/nav_side.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedFoodType = 0;
  List<Map<String, dynamic>> foodTypes = [
    {
      'name': 'Food',
      'image': 'assets/img-main-food.png' // Update with your actual image path
    },
    {
      'name': 'Drinks',
      'image':
          'assets/img-main-drinks.png' // Update with your actual image path
    },
  ];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Side Navigation Bar
          NavigationSidebar(),

          // Main Content
          Expanded(
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  // Top Bar
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Image.asset('assets/logo-shiokpos.png', height: 40),
                            const SizedBox(width: 10),
                            const Text(
                              'Welcome back, Clarence',
                              style: TextStyle(
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
                          child: const Text(
                            'Revenue RM 888.88',
                            style: TextStyle(
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
                      decoration: InputDecoration(
                        hintText: 'Search for food, drinks, etc',
                        prefixIcon: Icon(Icons.search),
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
                      itemCount: 8,
                      itemBuilder: (context, index) {
                        return _buildMenuItem(index);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Current Order Section
          Container(
            width: 300,
            color: Colors.white,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Current Order',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: 3,
                    itemBuilder: (context, index) {
                      return _buildOrderItem();
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      _buildOrderSummaryRow('Sub Total', 'RM70.25'),
                      _buildOrderSummaryRow('Service Charge (10%)', 'RM70.25'),
                      _buildOrderSummaryRow('GST (6%)', 'RM70.25'),
                      ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.pink,
                          minimumSize: const Size.fromHeight(50),
                        ),
                        child: const Text(
                          'Order Total RM 888.88',
                          style: TextStyle(
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
    );
  }

  Widget _buildMenuItem(int index) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
              child: Image.asset(
                'assets/pizza.png', // Replace with actual image
                fit: BoxFit.cover,
                width: double.infinity,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                const Text(
                  'Pepperoni Pizza',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'RM 70.25',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                  ),
                ),
                index == 3 ? _buildSoldOutOverlay() : const SizedBox(),
              ],
            ),
          ),
        ],
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

  Widget _buildOrderItem() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/pizza.png', // Replace with actual image
              width: 60,
              height: 60,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Pepperoni Pizza',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('RM 70.25'),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.remove),
                onPressed: () {},
              ),
              const Text('1'),
              IconButton(
                icon: Icon(Icons.add),
                onPressed: () {},
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
}
