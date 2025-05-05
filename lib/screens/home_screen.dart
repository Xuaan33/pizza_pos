import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  List<Map<String, dynamic>> availableItems = [];
  String _selectedItemGroup = 'All';
  bool _isLoadingItemGroups = true;
  bool _isLoadingItems = true;
  List<TextEditingController> _itemRemarkControllers = [];

  @override
  void initState() {
    super.initState();
    _loadItemGroups();
    _loadAvailableItems();
    currentOrderItems =
        widget.existingOrder != null ? List.from(widget.existingOrder!) : [];
    _itemRemarkControllers = currentOrderItems
        .map((item) => TextEditingController(text: item['remarks'] ?? ''))
        .toList();
  }

  @override
  void dispose() {
    // Dispose all remark controllers
    for (var controller in _itemRemarkControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadItemGroups() async {
    try {
      final posService = PosService();
      final response = await posService.getItemGroups();

      if (response['success'] == true) {
        setState(() {
          itemGroups = List<Map<String, dynamic>>.from(
              response['message']['item_groups']);
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

  Future<void> _loadAvailableItems() async {
    try {
      final posService = PosService();
      final response = await posService.getAvailableItems();

      if (response['success'] == true) {
        setState(() {
          availableItems =
              List<Map<String, dynamic>>.from(response['message']['items']);
          _isLoadingItems = false;
        });
      } else {
        throw Exception('Failed to load available items');
      }
    } catch (e) {
      setState(() => _isLoadingItems = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading available items: $e')),
      );
    }
  }

  // Current Order Items
  late List<Map<String, dynamic>> currentOrderItems;

  // Search functionality
  String searchQuery = '';
  TextEditingController searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    // Get the correct items list based on selection
    List<Map<String, dynamic>> displayedItems = _getFilteredItems();
    return FutureBuilder(
        future: SharedPreferences.getInstance(),
        builder: (context, snapshot) {
          final username = snapshot.hasData
              ? snapshot.data!.getString('username') ?? 'Administrator'
              : 'Administrator';

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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
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
                                        'Welcome back, $username - Table ${widget.tableNumber}',
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

                            // Item Groups Selector
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16.0),
                              child: _isLoadingItemGroups
                                  ? CircularProgressIndicator()
                                  : SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: List.generate(
                                            itemGroups.length, (index) {
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                                right: 8.0),
                                            child: ElevatedButton(
                                              onPressed: () {
                                                setState(() {
                                                  _selectedItemGroupIndex =
                                                      index;
                                                  _selectedItemGroup =
                                                      itemGroups[index]
                                                          ['value'];
                                                  searchController.clear();
                                                  searchQuery = '';
                                                });
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    _selectedItemGroupIndex ==
                                                            index
                                                        ? Colors.yellow
                                                        : Colors.white,
                                                foregroundColor: Colors.black,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 12,
                                                ),
                                              ),
                                              child: Text(
                                                  itemGroups[index]['name']),
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
                              child: _isLoadingItems
                                  ? Center(child: CircularProgressIndicator())
                                  : GridView.builder(
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
                                        return _buildMenuItem(
                                            displayedItems[index], index);
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

                    // Current Order Section
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
                                  color: const Color(0xFFE732A0),
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
                                Column(
                                  children: [
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: _submitOrder,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          minimumSize:
                                              const Size.fromHeight(50),
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
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: _goToCheckout,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFFE732A0),
                                          minimumSize:
                                              const Size.fromHeight(50),
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
        });
  }

  List<Map<String, dynamic>> _getFilteredItems() {
    String selectedGroup = itemGroups.isNotEmpty
        ? itemGroups[_selectedItemGroupIndex]['value']
        : 'All';

    List<Map<String, dynamic>> filteredItems = availableItems.where((item) {
      bool groupMatch =
          selectedGroup == 'All' || item['item_group'] == selectedGroup;
      bool searchMatch = searchQuery.isEmpty ||
          item['item_name'].toLowerCase().contains(searchQuery.toLowerCase());
      return groupMatch && searchMatch;
    }).toList();

    return filteredItems;
  }

  Future<void> _showItemOptionsDialog(Map<String, dynamic> item) async {
    List<Map<String, dynamic>> variants =
        List.from(item['structured_variant_info'] ?? []);
    Map<String, String?> selectedOptions = {};

    return showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: Text(
                item['item_name'],
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item['image'] != null)
                      Container(
                        height: 150,
                        width: double.infinity,
                        margin: EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          image: DecorationImage(
                            image: NetworkImage(
                                'https://shiokpos.byondwave.com${item['image']}'),
                            fit: BoxFit.cover,
                            onError: (_, __) => AssetImage('assets/pizza.png'),
                          ),
                        ),
                      ),
                    Text(
                      'RM ${(item['price_list_rate'] ?? 0).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFFE732A0),
                      ),
                    ),
                    SizedBox(height: 16),
                    ...variants.map((variant) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            variant['variant_group'],
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (variant['required'] == 1)
                            Text(
                              '(Required)',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          SizedBox(height: 8),
                          ...(variant['options'] as List).map((option) {
                            return Container(
                              margin: EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: selectedOptions[
                                              variant['variant_group']] ==
                                          option['option']
                                      ? Color(0xFFE732A0)
                                      : Colors.grey.shade300,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: RadioListTile<String>(
                                title: Text(
                                  option['option'],
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: option['additional_cost'] > 0
                                    ? Text(
                                        '+RM${option['additional_cost'].toStringAsFixed(2)}',
                                        style: TextStyle(
                                          color: Color(0xFFE732A0),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : null,
                                value: option['option'],
                                groupValue:
                                    selectedOptions[variant['variant_group']],
                                activeColor: Color(0xFFE732A0),
                                onChanged: (value) {
                                  setState(() {
                                    selectedOptions[variant['variant_group']] =
                                        value;
                                  });
                                },
                                dense: true,
                              ),
                            );
                          }).toList(),
                          SizedBox(height: 16),
                        ],
                      );
                    }).toList(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Validate required options
                    bool allRequiredSelected = true;
                    for (var variant in variants) {
                      if (variant['required'] == 1 &&
                          (selectedOptions[variant['variant_group']] == null ||
                              selectedOptions[variant['variant_group']]!
                                  .isEmpty)) {
                        allRequiredSelected = false;
                        break;
                      }
                    }

                    if (allRequiredSelected || variants.isEmpty) {
                      _addToOrderWithOptions(item, selectedOptions);
                      Navigator.pop(context);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Please select all required options',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFE732A0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  child: Text(
                    'Add to Order',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
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

  void _addToOrderWithOptions(
    Map<String, dynamic> item,
    Map<String, String?> selectedOptions,
  ) {
    double additionalCost = 0;
    List<String> optionTexts = [];

    selectedOptions.forEach((group, option) {
      if (option != null) {
        var variant = (item['structured_variant_info'] as List).firstWhere(
          (v) => v['variant_group'] == group,
          orElse: () => null,
        );

        if (variant != null) {
          var optionData = (variant['options'] as List).firstWhere(
            (o) => o['option'] == option,
            orElse: () => null,
          );

          if (optionData != null) {
            additionalCost += optionData['additional_cost'] ?? 0;
            optionTexts.add('$group: $option');
          }
        }
      }
    });

    setState(() {
      int existingIndex = currentOrderItems.indexWhere((orderItem) =>
          orderItem['item_code'] == item['item_code'] &&
          _compareOptions(orderItem['options'], selectedOptions));

      if (existingIndex != -1) {
        currentOrderItems[existingIndex]['quantity']++;
      } else {
        Map<String, dynamic> newOrderItem = {
          'item_code': item['item_code'],
          'name': item['item_name'],
          'price': (item['price_list_rate'] ?? 0) + additionalCost,
          'image': item['image'] ?? 'assets/pizza.png',
          'quantity': 1,
          'options': selectedOptions,
          'option_text': optionTexts.join(', '),
        };
        currentOrderItems.add(newOrderItem);
      }
    });
  }

  bool _compareOptions(dynamic options1, Map<String, String?> options2) {
    if (options1 == null || options2 == null) return false;
    if (options1 is! Map || options2 is! Map) return false;

    var map1 = Map<String, String?>.from(options1);
    var map2 = Map<String, String?>.from(options2);

    if (map1.length != map2.length) return false;

    for (var key in map1.keys) {
      if (map1[key] != map2[key]) return false;
    }

    return true;
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        title: const Text(
          'Discard Order?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        content: const Text(
          'Are you sure you want to discard this order and go back?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'CANCEL',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFE732A0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: Text(
              'DISCARD',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
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
    bool hasExistingOrder =
        widget.existingOrder != null && widget.existingOrder!.isNotEmpty;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        title: Text(
          hasExistingOrder ? 'Update Order' : 'Submit Order',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        content: Text(
          hasExistingOrder
              ? 'Are you sure you want to update this order?'
              : 'Are you sure you want to submit this order to kitchen?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'CANCEL',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context, {
                'action': hasExistingOrder ? 'updated' : 'submitted',
                'items': currentOrderItems,
                'replaceExisting': hasExistingOrder,
                'entryTime': DateTime.now(),
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFE732A0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: Text(
              hasExistingOrder ? 'UPDATE' : 'SUBMIT',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
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
        _showItemOptionsDialog(item);
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
                    child: item['image'] != null
                        ? Image.network(
                            'https://shiokpos.byondwave.com${item['image']}',
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (context, error, stackTrace) =>
                                Image.asset(
                              'assets/pizza.png',
                              fit: BoxFit.cover,
                            ),
                          )
                        : Image.asset(
                            'assets/pizza.png',
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    children: [
                      Text(
                        item['item_name'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'RM ${(item['price_list_rate'] ?? 0).toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFE732A0),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
    // Ensure we have a controller for this item
    if (index >= _itemRemarkControllers.length) {
      _itemRemarkControllers
          .add(TextEditingController(text: item['remarks'] ?? ''));
    } else {
      _itemRemarkControllers[index].text = item['remarks'] ?? '';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: item['image'] != null
                    ? Image.network(
                        'https://shiokpos.byondwave.com${item['image']}',
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            Image.asset(
                          'assets/pizza.png',
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Image.asset(
                        'assets/pizza.png',
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
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (item['option_text'] != null &&
                        item['option_text'].isNotEmpty)
                      Text(
                        item['option_text'],
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    Text(
                      'RM ${(item['price'] * item['quantity']).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE732A0),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              // Quantity controls
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, size: 16),
                      onPressed: () => _decreaseQuantity(index),
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(minWidth: 30, minHeight: 30),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '${item['quantity']}',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 16),
                      onPressed: () => _increaseQuantity(index),
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(minWidth: 30, minHeight: 30),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: Colors.red),
                onPressed: () => _removeItem(index),
              ),
            ],
          ),
          // Enhanced remarks field for this item
          Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 70, bottom: 8.0),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey.shade50,
              ),
              child: TextField(
                controller: _itemRemarkControllers[index],
                decoration: InputDecoration(
                  hintText: 'Add remarks...',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Color(0xFFE732A0)),
                  ),
                  suffixIcon: Container(
                    margin: EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Color(0xFFE732A0),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.check, size: 16, color: Colors.white),
                      onPressed: () {
                        _saveRemarks(index);
                        FocusScope.of(context).unfocus();
                      },
                      constraints: BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),
                style: TextStyle(fontSize: 13),
                onSubmitted: (_) => _saveRemarks(index),
              ),
            ),
          ),
          Divider(color: Colors.grey.shade200),
        ],
      ),
    );
  }

  void _saveRemarks(int index) {
    setState(() {
      currentOrderItems[index]['remarks'] = _itemRemarkControllers[index].text;
    });
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
          Text(
            amount,
            style: TextStyle(
                fontWeight: FontWeight.bold, color: const Color(0xFFE732A0)),
          ),
        ],
      ),
    );
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
