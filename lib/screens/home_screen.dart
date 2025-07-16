import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiok_pos_android_app/components/customer_display_controller.dart';
import 'package:shiok_pos_android_app/components/main_layout.dart';
import 'package:shiok_pos_android_app/components/no_stretch_scroll_behavior.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/screens/checkout_screen.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final int tableNumber;
  final Map<String, dynamic>? existingOrder;
  final bool isTier1;

  const HomeScreen({
    Key? key,
    required this.tableNumber,
    this.existingOrder,
    this.isTier1 = false, // Default to false
  }) : super(key: key);

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedItemGroupIndex = 0;
  List<Map<String, dynamic>> itemGroups = [];
  List<Map<String, dynamic>> availableItems = [];
  String _selectedItemGroup = 'All';
  bool _isLoadingItemGroups = true;
  bool _isLoadingItems = true;
  List<TextEditingController> _itemRemarkControllers = [];
  bool _isLoading = false;
  Map<String, dynamic>? _existingOrder;
  String baseImageUrl = 'http://shiokpos.byondwave.com';
  Map<String, int> _itemStockQuantities =
      {}; // key: item_code, value: available stock
  bool _isLoadingStock = false;

  @override
  void initState() {
    super.initState();
    _loadItemGroups();
    _loadAvailableItems();
    _initializeOrderItems();
  }

  void _initializeOrderItems() {
    if (widget.existingOrder != null &&
        widget.existingOrder!['items'] != null) {
      currentOrderItems = (widget.existingOrder!['items'] as List).map((item) {
        // Convert old format to new format if needed
        double additionalCost = _calculateAdditionalCost(item);
        double itemPrice = (item['price'] ?? 0) + additionalCost;

        String imageUrl = '';
      if (item['image'] != null) {
        imageUrl = item['image'].toString().startsWith('http')
            ? item['image'].toString()
            : '$baseImageUrl${item['image']}';
      }
        Map<String, dynamic> newItem = {
          'item_code': item['item_code'] ?? '',
          'name': item['item_name'] ?? item['name'] ?? '',
          'price': (itemPrice ?? item['price_list_rate'] ?? 0).toDouble(),
          'image': '$baseImageUrl${item['image']}' ?? 'assets/pizza.png',
          'quantity': (item['qty'] ?? item['quantity'] ?? 1).toDouble(),
          'options': item['options'] ?? {},
          'option_text': item['option_text'] ?? '',
          'custom_serve_later': item['custom_serve_later'] == 1,
          'custom_item_remarks': item['custom_item_remarks'] ?? '',
        };

        // Convert old variant format to new format if needed
        if (item['custom_variant_info'] != null) {
          try {
            dynamic variantInfo = item['custom_variant_info'] is String
                ? jsonDecode(item['custom_variant_info'])
                : item['custom_variant_info'];

            if (variantInfo is List) {
              newItem['custom_variant_info'] = variantInfo;
            } else if (variantInfo is Map) {
              // Convert old map format to new list format
              newItem['custom_variant_info'] = [
                {
                  'variant_group': 'Options',
                  'options': variantInfo.entries
                      .map((e) => {
                            'option': e.value,
                            'additional_cost': 0 // Default cost for old format
                          })
                      .toList()
                }
              ];
            }
          } catch (e) {
            debugPrint('Error parsing variant info: $e');
          }
        }

        return newItem;
      }).toList();
    } else {
      currentOrderItems = [];
    }

    _itemRemarkControllers = currentOrderItems
        .map((item) =>
            TextEditingController(text: item['custom_item_remarks'] ?? ''))
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
      Fluttertoast.showToast(
        msg: 'Error loading item groups: $e',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  Future<void> _loadAvailableItems() async {
    try {
      final posService = PosService();
      final response = await posService.getAvailableItems();
      print(response['message']['items']);

      if (response['success'] == true) {
        setState(() {
          availableItems =
              List<Map<String, dynamic>>.from(response['message']['items']);
          _isLoadingItems = false;
        });
        // Check stock after items are loaded
        _checkStockForItems();
      } else {
        throw Exception('Failed to load available items');
      }
    } catch (e) {
      setState(() => _isLoadingItems = false);
      Fluttertoast.showToast(
        msg: 'Error loading available items: $e',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  // Current Order Items
  late List<Map<String, dynamic>> currentOrderItems;

  // Search functionality
  String searchQuery = '';
  TextEditingController searchController = TextEditingController();

  void _autoSaveAllRemarks() {
    for (int i = 0;
        i < _itemRemarkControllers.length && i < currentOrderItems.length;
        i++) {
      if (_itemRemarkControllers[i].text !=
          currentOrderItems[i]['custom_item_remarks']) {
        currentOrderItems[i]['custom_item_remarks'] =
            _itemRemarkControllers[i].text;
      }
    }
  }

  Future<void> _checkStockForItems() async {
    if (_isLoadingStock) return;

    setState(() => _isLoadingStock = true);

    final authState = ref.read(authProvider);
    await authState.whenOrNull(
      authenticated: (sid, apiKey, apiSecret, username, email, fullName,
          posProfile, branch, paymentMethods, taxes, hasOpening, tier) async {
        try {
          final newStockQuantities = <String, int>{};

          for (var item in availableItems) {
            try {
              final response = await PosService().getStockQuantity(
                posProfile: posProfile,
                itemCode: item['item_code'],
              );

              if (response['success'] == true) {
                newStockQuantities[item['item_code']] =
                    (response['message']['qty'] as num?)?.toInt() ?? 0;
              } else {
                newStockQuantities[item['item_code']] =
                    999; // Assume unlimited if API fails
              }
            } catch (e) {
              debugPrint('Error checking stock for ${item['item_code']}: $e');
              newStockQuantities[item['item_code']] =
                  999; // Assume unlimited on error
            }
          }

          setState(() {
            _itemStockQuantities = newStockQuantities;
          });
        } catch (e) {
          debugPrint('Error checking stock: $e');
        } finally {
          setState(() => _isLoadingStock = false);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get the correct items list based on selection
    List<Map<String, dynamic>> displayedItems = _getFilteredItems();
    final authState = ref.watch(authProvider);

    return authState.when(
        initial: () => const Center(child: CircularProgressIndicator()),
        unauthenticated: () => const Center(child: Text('Unauthorized')),
        authenticated: (sid, apiKey, apiSecret, username, email, fullName,
            posProfile, branch, paymentMethods, taxes, hasOpening, tier) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            CustomerDisplayController.showCustomerScreen();
            CustomerDisplayController.updateOrderDisplay(
              items: currentOrderItems.map((item) {
                // Ensure quantity is converted to int for display
                final quantity = (item['quantity'] is double)
                    ? (item['quantity'] as double).toInt()
                    : item['quantity'] as int;

                // Ensure price is properly formatted
                final price = (item['price'] is int)
                    ? (item['price'] as int).toDouble()
                    : item['price'] as double;

                return {
                  'name': item['name'] ?? 'Unknown',
                  'price': price,
                  'quantity': quantity,
                };
              }).toList(),
              subtotal: _calculateSubtotal(),
              tax: _calculateGST(),
              total: _calculateTotal(),
            );
          });
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
                                            if (tier.toLowerCase() !=
                                                'tier1') ...[
                                              IconButton(
                                                icon: const Icon(
                                                    Icons.arrow_back),
                                                onPressed: () {
                                                  _onBackPressed();
                                                },
                                              ),
                                              const SizedBox(width: 8),
                                              Image.asset(
                                                  'assets/logo-shiokpos.png',
                                                  height: 40),
                                              const SizedBox(width: 10),
                                            ],
                                            Text(
                                              widget.isTier1
                                                  ? 'Instant Order'
                                                  : 'Table ${widget.tableNumber}',
                                              style: const TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (tier.toLowerCase() != 'tier1') ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: Colors.black,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              'Revenue RM ${_calculateTotalRevenue().toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ]
                                      ],
                                    ),
                                  ),

                                  // Item Groups Selector
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0),
                                    child: _isLoadingItemGroups
                                        ? CircularProgressIndicator()
                                        : ScrollConfiguration(
                                            behavior: NoStretchScrollBehavior(),
                                            child: SingleChildScrollView(
                                              scrollDirection: Axis.horizontal,
                                              child: Row(
                                                children: List.generate(
                                                    itemGroups.length, (index) {
                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            right: 8.0),
                                                    child: ElevatedButton(
                                                      onPressed: () {
                                                        setState(() {
                                                          _selectedItemGroupIndex =
                                                              index;
                                                          _selectedItemGroup =
                                                              itemGroups[index]
                                                                  ['value'];
                                                          searchController
                                                              .clear();
                                                          searchQuery = '';
                                                        });
                                                      },
                                                      style: ElevatedButton
                                                          .styleFrom(
                                                        backgroundColor:
                                                            _selectedItemGroupIndex ==
                                                                    index
                                                                ? Colors.yellow
                                                                : Colors.white,
                                                        foregroundColor:
                                                            Colors.black,
                                                        shape:
                                                            RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(20),
                                                        ),
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 16,
                                                          vertical: 12,
                                                        ),
                                                      ),
                                                      child: Text(
                                                          itemGroups[index]
                                                              ['name']),
                                                    ),
                                                  );
                                                }),
                                              ),
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
                                        hintText:
                                            'Search for food, drinks, etc',
                                        prefixIcon: const Icon(Icons.search),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Menu Grid
                                  Expanded(
                                    child: _isLoadingItems
                                        ? Center(
                                            child: CircularProgressIndicator())
                                        : ScrollConfiguration(
                                            behavior: NoStretchScrollBehavior(),
                                            child: GridView.builder(
                                              padding:
                                                  const EdgeInsets.all(16.0),
                                              gridDelegate:
                                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                                crossAxisCount: 5,
                                                crossAxisSpacing: 16,
                                                mainAxisSpacing: 16,
                                                childAspectRatio: 0.8,
                                              ),
                                              itemCount: displayedItems.length,
                                              itemBuilder: (context, index) {
                                                return _buildMenuItem(
                                                    displayedItems[index],
                                                    index);
                                              },
                                            ),
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
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Current Order',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (widget.existingOrder != null &&
                                              widget.existingOrder!.isNotEmpty)
                                            IconButton(
                                              icon: Icon(Icons.delete,
                                                  color: Colors.red),
                                              onPressed: _deleteOrder,
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                ScrollConfiguration(
                                  behavior: NoStretchScrollBehavior(),
                                  child: Expanded(
                                    child: ListView.builder(
                                      physics:
                                          ClampingScrollPhysics(), // still good to include
                                      itemCount: currentOrderItems.length,
                                      itemBuilder: (context, index) {
                                        return _buildOrderItem(
                                            currentOrderItems[index], index);
                                      },
                                    ),
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
                                      _buildOrderSummaryRow('GST (6%)',
                                          'RM ${_calculateGST().toStringAsFixed(2)}'),
                                      _buildOrderSummaryRow(
                                          'Rounding', _getRoundingLabel()),
                                      const SizedBox(height: 10),
                                      Column(
                                        children: [
                                          if (tier.toLowerCase() !=
                                              'tier1') ...[
                                            SizedBox(
                                              width: double.infinity,
                                              child: ElevatedButton(
                                                onPressed: _isLoading
                                                    ? null
                                                    : _submitOrder,
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.green,
                                                  minimumSize:
                                                      const Size.fromHeight(50),
                                                ),
                                                child: _isLoading
                                                    ? const CircularProgressIndicator(
                                                        color: Colors.white)
                                                    : const Text(
                                                        'Submit Order',
                                                        style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 20,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600),
                                                      ),
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                          ],
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
                                                'Checkout RM ${_getRoundedTotal().toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  fontSize: 20,
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
              content: ScrollConfiguration(
                behavior: NoStretchScrollBehavior(),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item['image'] != null)
                        Text(
                            'RM ${(item['price_list_rate'] ?? 0).toStringAsFixed(2)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Color(0xFFE732A0),
                            )),
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
                                      selectedOptions[
                                          variant['variant_group']] = value;
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
                      Fluttertoast.showToast(
                        msg: "Please select all required options",
                        gravity: ToastGravity.BOTTOM,
                        backgroundColor: Colors.red,
                        textColor: Colors.white,
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
    final itemCode = item['item_code'];
    final availableStock = _itemStockQuantities[itemCode] ?? 999;
    final isInStock = availableStock > 0;
    final isLoadingStock = _isLoadingStock;
    final canAddItem = !isLoadingStock && isInStock;
     if (!canAddItem) {
    Fluttertoast.showToast(
      msg: "Item is out of stock",
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.red,
      textColor: Colors.white,
    );
    return;
  }

  // Calculate total quantity of this item (all variants) in current order
  int totalQuantityOfItem = currentOrderItems
    .where((orderItem) => orderItem['item_code'] == itemCode)
    .fold(0, (sum, orderItem) => sum + (orderItem['quantity'] as num).toInt());



  if (totalQuantityOfItem >= availableStock) {
    Fluttertoast.showToast(
      msg: "Cannot add more than available stock ($availableStock)",
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.red,
      textColor: Colors.white,
    );
    return;
  }

    // Check if we're adding a new item or increasing quantity of existing one
    int existingIndex = currentOrderItems.indexWhere((orderItem) =>
        orderItem['item_code'] == item['item_code'] &&
        _compareOptions(orderItem['options'], selectedOptions));

    if (existingIndex != -1) {
      // For existing item, check if we can increase quantity
      if (currentOrderItems[existingIndex]['quantity'] >= availableStock) {
        Fluttertoast.showToast(
          msg: "Cannot add more than available stock ($availableStock)",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
        return;
      }
      setState(() {
        currentOrderItems[existingIndex]['quantity']++;
      });
    } else {
      // For new item, check if stock is available
      if (availableStock <= 0) {
        Fluttertoast.showToast(
          msg: "Item is out of stock",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
        return;
      }

      // Same as your existing code for adding new item...
      List<Map<String, dynamic>> variantInfo = [];
      double totalAdditionalCost = 0.0;

      if (selectedOptions.isNotEmpty &&
          item['structured_variant_info'] != null) {
        for (var variantGroup in item['structured_variant_info']) {
          final selectedOption = selectedOptions[variantGroup['variant_group']];
          if (selectedOption != null) {
            for (var option in variantGroup['options']) {
              if (option['option'] == selectedOption) {
                double optionCost =
                    (option['additional_cost'] as num).toDouble();
                totalAdditionalCost += optionCost;

                variantInfo.add({
                  'variant_group': variantGroup['variant_group'],
                  'options': [
                    {
                      'option': selectedOption,
                      'additional_cost': optionCost,
                    }
                  ],
                });
                break;
              }
            }
          }
        }
      }

      setState(() {
        Map<String, dynamic> newOrderItem = {
          'item_code': item['item_code'],
          'name': item['item_name'],
          'price': (item['price_list_rate'] ?? 0),
          'image': item['image'] ?? 'assets/pizza.png',
          'quantity': 1,
          'options': selectedOptions,
          'option_text': selectedOptions.entries
              .map((e) => '${e.key}: ${e.value}')
              .join(', '),
          'custom_serve_later': false,
          'custom_item_remarks': '',
          'structured_variant_info': item['structured_variant_info'],
          'custom_variant_info': variantInfo,
          'additional_cost': totalAdditionalCost,
        };
        currentOrderItems.add(newOrderItem);
      });
    }
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

  Future<bool> _onWillPop() async {
    if (currentOrderItems.isEmpty) {
      return true;
    }
    return _onBackPressed();
  }

  Future<bool> _onBackPressed() async {
    final authState = ref.read(authProvider);
    final isTier1 = authState.maybeWhen(
      authenticated: (sid, apiKey, apiSecret, username, email, fullName,
          posProfile, branch, paymentMethods, taxes, hasOpening, tier) {
        return tier.toLowerCase() == 'tier1';
      },
      orElse: () => false,
    );

    if (isTier1) {
      Navigator.pop(context);
      return true;
    }

    if (currentOrderItems.isEmpty) {
      // CustomerDisplayController.showDefaultDisplay();
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
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
      // CustomerDisplayController.showDefaultDisplay();
      return true;
    }
    return false;
  }

  Future<void> _submitOrder() async {
    _autoSaveAllRemarks();
    final authState = ref.read(authProvider);
    bool hasExistingOrder =
        widget.existingOrder != null && widget.existingOrder!.isNotEmpty;

    final confirmed = await showDialog<bool>(
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
                onPressed: () => {
                  Navigator.pop(context, true),
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
        ) ??
        false;

    if (!confirmed) return;

    authState.whenOrNull(
      authenticated: (sid, apiKey, apiSecret, username, email, fullName,
          posProfile, branch, paymentMethods, taxes, hasOpening, tier) async {
        setState(() => _isLoading = true);

        try {
          // 1. Get the full table name from floors and tables API
          final floorsResponse = await PosService().getFloorsAndTables(branch);
          String tableFullName = 'Table ${widget.tableNumber}'; // fallback

          if (floorsResponse['success'] == true) {
            for (var floor in floorsResponse['message']) {
              for (var table in floor['tables']) {
                if (table['title'] == 'Table ${widget.tableNumber}') {
                  tableFullName = table['name']; // e.g. "MK-Floor 1-Table 1"
                  break;
                }
              }
            }
          }

          // 2. Prepare items with proper structure
          final items = currentOrderItems.map((item) {
            dynamic variantInfo = item['custom_variant_info'];
            double additionalCost = _calculateAdditionalCost(item);
            double itemPrice = (item['price'] ?? 0) + additionalCost;

            return {
              'item_code': item['item_code'] ?? '',
              'qty': item['quantity'],
              'price_list_rate': itemPrice, // Submit BASE + ADDITIONAL COST
              'custom_item_remarks': item['custom_item_remarks'] ?? '',
              'custom_serve_later': item['custom_serve_later'] == true ? 1 : 0,
              if (variantInfo.isNotEmpty) 'custom_variant_info': variantInfo,
            };
          }).toList();

          print('Submitting order for table: $tableFullName'); // Debug log
          print('Order channel: Dine In'); // Debug log

          // 3. Submit with proper table format and order channel
          final response = await PosService().submitOrder(
            posProfile: posProfile,
            customer: 'Guest',
            items: items,
            table: tableFullName, // e.g. "MK-Floor 1-Table 1"
            orderChannel: 'Dine In', // Hardcoded as requested
            name: hasExistingOrder ? widget.existingOrder!['orderId'] : null,
          );

          if (response['success'] == true) {
            Navigator.pop(context, {
              'action': hasExistingOrder ? 'updated' : 'submitted',
              'invoice': response['message'],
              'tableNumber': widget.tableNumber,
              'tableFullName': tableFullName, // Pass both for reference
            });

            // CustomerDisplayController.showDefaultDisplay();
            Navigator.pushNamedAndRemoveUntil(
              context,
              '/',
              (route) => false,
              arguments: {
                'action': 'deleted',
                'tableNumber': widget.tableNumber,
              },
            );

            Fluttertoast.showToast(
              msg: "Order Submitted",
              gravity: ToastGravity.BOTTOM,
              backgroundColor: Colors.green,
              textColor: Colors.white,
            );
          }
        } catch (e) {
          print('Submit order error: $e');
          Fluttertoast.showToast(
            msg: 'Error submitting order: $e',
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.red,
            textColor: Colors.white,
          );
        } finally {
          setState(() => _isLoading = false);
        }
      },
    );
  }

  void _goToCheckout() async {
    final hasExistingOrder =
        widget.existingOrder != null && widget.existingOrder!.isNotEmpty;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: Text(
              hasExistingOrder ? 'Proceed to Checkout' : 'Confirm Order',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            content: Text(
              hasExistingOrder
                  ? 'Update order and proceed to checkout?'
                  : 'Submit order and proceed to checkout?',
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
                  'CONFIRM',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() => _isLoading = true);

    try {
      final authState = ref.read(authProvider);
      await authState.whenOrNull(authenticated: (sid,
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
          tier) async {
        if (tier.toLowerCase() == "tier1") {
          if (!hasOpening) {
            // Show dialog if no opening entry exists
            _showOpeningRequiredDialog();
            return;
          }
        }
        // Auto-save all remarks before proceeding
        _autoSaveAllRemarks();

        // Get the full table name from floors and tables API
        final floorsResponse = await PosService().getFloorsAndTables(branch);
        String? tableFullName;

        for (var floor in floorsResponse['message']) {
          final tables = floor['tables'];

          if (tables is Map<String, dynamic>) {
            if (floor['floor'] == 'DEFAULT' && tables['is_default'] == 1) {
              tableFullName = tables['name'];
              break;
            }
          } else if (tables is List) {
            for (var table in tables) {
              if (table['title'] == 'Table ${widget.tableNumber}') {
                tableFullName = table['name'];
                break;
              }
            }
          }
        }

        tableFullName ??= 'Table ${widget.tableNumber}';

        // Prepare items with proper structure
        final items = currentOrderItems.map((item) {
          dynamic variantInfo = item['custom_variant_info'];
          double additionalCost = _calculateAdditionalCost(item);
          double itemPrice = (item['price'] ?? 0) + additionalCost;

          return {
            'item_code': item['item_code'] ?? '',
            'qty': item['quantity'],
            'price_list_rate': itemPrice,
            'custom_item_remarks': item['custom_item_remarks'] ?? '',
            'custom_serve_later': item['custom_serve_later'] == true ? 1 : 0,
            if (variantInfo.isNotEmpty) 'custom_variant_info': variantInfo,
          };
        }).toList();

        String? orderName;

        // Submit/Update the order first
        if (hasExistingOrder) {
          // Update existing order
          final response = await PosService().submitOrder(
            posProfile: posProfile,
            customer: 'Guest',
            items: items,
            table: tableFullName,
            orderChannel: 'Dine In',
            name: widget
                .existingOrder!['orderId'], // Pass existing order ID to update
          );

          if (response['success'] == true) {
            orderName = response['message']['name'];
          } else {
            throw Exception('Failed to update order');
          }
        } else {
          // Create new order
          final response = await PosService().submitOrder(
            posProfile: posProfile,
            customer: 'Guest',
            items: items,
            table: tableFullName,
            orderChannel: 'Dine In',
          );

          if (response['success'] == true) {
            orderName = response['message']['name'];
          } else {
            throw Exception('Failed to submit order');
          }
        }

        // Now proceed to checkout with updated order
        final result = await Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => CheckoutScreen(
              order: {
                'tableNumber': widget.tableNumber,
                'items': List<Map<String, dynamic>>.from(currentOrderItems),
                'entryTime': hasExistingOrder
                    ? (widget.existingOrder!['entryTime'] ?? DateTime.now())
                    : DateTime.now(),
                'invoiceNumber': orderName ??
                    (hasExistingOrder ? widget.existingOrder!['orderId'] : ''),
                'orderId': orderName ?? widget.existingOrder?['orderId'],
              },
              tablesWithSubmittedOrders:
                  MainLayout.of(context)?.tablesWithSubmittedOrders ?? {},
              onOrderSubmitted: (order) =>
                  MainLayout.of(context)?.addNewOrder(order),
              onOrderPaid: (tableNumber) =>
                  MainLayout.of(context)?.markOrderAsPaid(tableNumber),
              activeOrders: MainLayout.of(context)?.activeOrders ?? [],
            ),
          ),
          (route) => route
              .isFirst, // This will keep only the first route (usually the main layout)
        );

        if (result != null && result['action'] == 'edit') {
          // Navigate back to HomeScreen with the existing order data
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => HomeScreen(
                tableNumber: result['tableNumber'],
                existingOrder: result['order'],
              ),
            ),
          );
        }
      });
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Error: ${e.toString()}',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildMenuItem(Map<String, dynamic> item, int index) {
    final availableStock = _itemStockQuantities[item['item_code']] ?? 999;
    final isInStock = availableStock > 0;
    final isLoadingStock = _isLoadingStock;
    final canAddItem = !isLoadingStock && isInStock;

    return GestureDetector(
      onTap: canAddItem
          ? () {
              _showItemOptionsDialog(item);
            }
          : null,
      child: Opacity(
        opacity: canAddItem ? 1.0 : 0.6,
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
                      child: Padding(
                        padding: const EdgeInsets.all(
                            8.0), // Adjust the value as needed
                        child: item['image'] != null
                            ? Image.network(
                                '$baseImageUrl${item['image']}',
                                fit: BoxFit.cover,
                                height: 70,
                                width: double.infinity,
                                color: isInStock
                                    ? null
                                    : Colors.grey.withOpacity(0.5),
                                colorBlendMode: BlendMode.saturation,
                                errorBuilder: (context, error, stackTrace) =>
                                    Image.network(
                                  item['image'],
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Image.asset(
                                'assets/pizza.png',
                                fit: BoxFit.cover,
                                height: 70,
                                width: double.infinity,
                              ),
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
                          maxLines: 1,
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
              if (!isInStock) _buildOutOfStockOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  // Add this new method
  Widget _buildOutOfStockOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'OUT OF STOCK',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderItem(Map<String, dynamic> item, int index) {
    double basePrice = item['price'];
    double additionalCost = _calculateAdditionalCost(item);
    double totalPricePerItem = basePrice + additionalCost;
    double itemSubtotal = totalPricePerItem * item['quantity'];
    final itemCode = item['item_code'];
    final availableStock = _itemStockQuantities[itemCode] ?? 999;
    final currentQuantity = item['quantity'];
    final showStockLimit = currentQuantity >= availableStock;

    // Ensure we have a controller for this item
    if (index >= _itemRemarkControllers.length) {
      _itemRemarkControllers
          .add(TextEditingController(text: item['custom_item_remarks'] ?? ''));
    } else {
      _itemRemarkControllers[index].text = item['custom_item_remarks'] ?? '';
    }

    List<Widget> variantWidgets = [];
    if (item['custom_variant_info'] != null &&
        item['custom_variant_info'] is List) {
      for (var variant in item['custom_variant_info']) {
        if (variant is Map && variant['options'] is List) {
          for (var option in variant['options']) {
            variantWidgets.add(
              Text(
                '• ${variant['variant_group']}: ${option['option']}${option['additional_cost'] > 0 ? ' +RM ${option['additional_cost'].toStringAsFixed(2)}' : ''}',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            );
          }
        }
      }
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
                        '$baseImageUrl${item['image']}',
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
                    if (variantWidgets.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: variantWidgets,
                      ),
                    SizedBox(
                      height: 4,
                    ),
                    Text(
                      'RM ${itemSubtotal.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE732A0),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Quantity controls and delete button
          Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 0, right: 0),
            child: Column(
              children: [
                // Stock limit message (conditionally shown)
                if (showStockLimit)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      'Cannot add more than available stock ($availableStock)',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Serve Later section on the left
                    Row(
                      children: [
                        Text(
                          'Serve Later',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Transform.scale(
                          scale: 0.75,
                          child: Switch(
                            value: item['custom_serve_later'] ?? false,
                            onChanged: (value) {
                              setState(() {
                                currentOrderItems[index]['custom_serve_later'] =
                                    value;
                              });
                            },
                            activeColor: Color(0xFFE732A0),
                          ),
                        ),
                      ],
                    ),

                    // Quantity control and delete on the right
                    Row(
                      children: [
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
                                constraints:
                                    BoxConstraints(minWidth: 30, minHeight: 30),
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  '${(item['quantity']).toStringAsFixed(0)}',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add, size: 16),
                                onPressed: showStockLimit
                                    ? null
                                    : () => _increaseQuantity(index),
                                padding: EdgeInsets.zero,
                                constraints:
                                    BoxConstraints(minWidth: 30, minHeight: 30),
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
                  ],
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 0, bottom: 8.0),
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
      currentOrderItems[index]['custom_item_remarks'] =
          _itemRemarkControllers[index].text;
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
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            amount,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: const Color(0xFFE732A0)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteOrder() async {
    if (widget.existingOrder == null || widget.existingOrder!.isEmpty) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: const Text(
              'Delete Order',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            content: const Text(
              'Are you sure you want to delete this order? This action cannot be undone.',
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
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                child: Text(
                  'DELETE',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() => _isLoading = true);

    try {
      final orderName = widget.existingOrder!['orderId']?.toString();
      if (orderName == null || orderName.isEmpty) {
        throw Exception('Order ID not found');
      }

      final response = await PosService().deleteOrder(orderName);

      if (response['success'] == true) {
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/',
            (route) => false,
            arguments: {
              'action': 'deleted',
              'tableNumber': widget.tableNumber,
            },
          );

          Fluttertoast.showToast(
            msg: "Order Deleted Successfully",
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.green,
            textColor: Colors.white,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Failed to delete order: ${e.toString()}',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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

  Future<bool> showDiscardOrderDialog() async {
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
          'You have items in your current order. Are you sure you want to discard them?',
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

    return result ?? false;
  }

  void _increaseQuantity(int index) {
    if (_isLoadingStock) return;

    final item = currentOrderItems[index];
    final itemCode = item['item_code'];
    final currentQuantity = item['quantity'];
    final availableStock = _itemStockQuantities[itemCode] ?? 999;

    if (currentQuantity >= availableStock) {
      return;
    }

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
      double basePrice = item['price'];
      double additionalCost = _calculateAdditionalCost(item);
      subtotal += (basePrice + additionalCost) * item['quantity'];
    }
    return subtotal;
  }

  double _calculateGST() {
    final authState = ref.read(authProvider);
    return authState.whenOrNull(
          authenticated: (sid, apiKey, apiSecret, username, email, fullName,
              posProfile, branch, paymentMethods, taxes, hasOpening, tier) {
            // Find the GST tax rate
            final gstTax = taxes.firstWhere(
              (tax) => tax['description']?.contains('GST') ?? false,
              orElse: () => {'rate': 6.0}, // Default to 6% if not found
            );
            return _calculateSubtotal() * (gstTax['rate'] ?? 6.0) / 100;
          },
        ) ??
        (_calculateSubtotal() * 0.06); // Fallback to 6% if not authenticated
  }

  double _calculateTotal() {
    return _calculateSubtotal() + _calculateGST();
  }

  double _calculateTotalRevenue() {
    // For demo purposes, just showing the current order total
    // In a real app, this would track all completed orders
    return _calculateTotal();
  }

  double _calculateAdditionalCost(Map<String, dynamic> item) {
    if (item['additional_cost'] != null) {
      return (item['additional_cost'] as num).toDouble();
    }
    return 0.0;
  }

  double _getUnroundedTotal() {
    return _calculateSubtotal() + (_calculateSubtotal() * 0.06); // GST 6%
  }

  double _getRoundedTotal() {
    double unroundedTotal = _getUnroundedTotal();
    double lastDigit = (unroundedTotal * 100) % 10;

    if (lastDigit == 1 || lastDigit == 2) {
      return (unroundedTotal * 100 - lastDigit) / 100; // Round down
    } else if (lastDigit == 3 || lastDigit == 4) {
      return (unroundedTotal * 100 + (5 - lastDigit)) / 100; // Round up to .05
    } else if (lastDigit == 6 || lastDigit == 7) {
      return (unroundedTotal * 100 - (lastDigit - 5)) /
          100; // Round down to .05
    } else if (lastDigit == 8 || lastDigit == 9) {
      return (unroundedTotal * 100 + (10 - lastDigit)) / 100; // Round up to .00
    }
    return unroundedTotal; // No rounding needed for 0 or 5
  }

  double _getRoundingDifference() {
    return _getRoundedTotal() - _getUnroundedTotal();
  }

  String _getRoundingLabel() {
    double difference = _getRoundingDifference();
    if (difference > 0) {
      return '+ RM ${difference.toStringAsFixed(2)}';
    } else if (difference < 0) {
      return '- RM ${difference.abs().toStringAsFixed(2)}';
    } else if (difference == 0) {
      return 'RM 0.00';
    }
    return '';
  }
}
