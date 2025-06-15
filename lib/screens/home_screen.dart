import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiok_pos_android_app/components/main_layout.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';
import 'checkout_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final int tableNumber;
  final Map<String, dynamic>? existingOrder;

  const HomeScreen({
    Key? key,
    required this.tableNumber,
    this.existingOrder,
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
        Map<String, dynamic> newItem = {
          'item_code': item['item_code'] ?? '',
          'name': item['item_name'] ?? item['name'] ?? '',
          'price': (item['price_list_rate'] ?? item['price'] ?? 0).toDouble(),
          'image': item['image'] ?? 'assets/pizza.png',
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

  @override
  Widget build(BuildContext context) {
    // Get the correct items list based on selection
    List<Map<String, dynamic>> displayedItems = _getFilteredItems();
    final authState = ref.watch(authProvider);

    return authState.when(
        initial: () => const Center(child: CircularProgressIndicator()),
        unauthenticated: () => const Center(child: Text('Unauthorized')),
        authenticated: (sid, apiKey, apiSecret, username, email, fullName,
            posProfile, branch, paymentMethods, taxes, hasOpening) {
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
                                              icon:
                                                  const Icon(Icons.arrow_back),
                                              onPressed: () {
                                                _onBackPressed();
                                              },
                                            ),
                                            const SizedBox(width: 8),
                                            Image.asset(
                                                'assets/logo-shiokpos.png',
                                                height: 40),
                                            const SizedBox(width: 10),
                                            Text(
                                              'Welcome back, $username - Table ${widget.tableNumber}',
                                              style: const TextStyle(
                                                fontSize: 24,
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
                                      ],
                                    ),
                                  ),

                                  // Item Groups Selector
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0),
                                    child: _isLoadingItemGroups
                                        ? CircularProgressIndicator()
                                        : SingleChildScrollView(
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
                                                      padding: const EdgeInsets
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
                                        : GridView.builder(
                                            padding: const EdgeInsets.all(16.0),
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
                                      _buildOrderSummaryRow('GST (6%)',
                                          'RM ${_calculateGST().toStringAsFixed(2)}'),
                                      const SizedBox(height: 10),
                                      Column(
                                        children: [
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
                                                              FontWeight.w600),
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
              content: SingleChildScrollView(
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
    List<Map<String, dynamic>> variantInfo = [];
    double totalAdditionalCost = 0.0;

    if (selectedOptions.isNotEmpty && item['structured_variant_info'] != null) {
      // Find matching options and their additional costs
      for (var variantGroup in item['structured_variant_info']) {
        final selectedOption = selectedOptions[variantGroup['variant_group']];
        if (selectedOption != null) {
          // Find the selected option in the variant group
          for (var option in variantGroup['options']) {
            if (option['option'] == selectedOption) {
              double optionCost = (option['additional_cost'] as num).toDouble();
              totalAdditionalCost += optionCost;

              variantInfo.add({
                'variant_group': variantGroup['variant_group'],
                'option': selectedOption,
                'additional_cost': optionCost,
              });
              break;
            }
          }
        }
      }
    }

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
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
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
          posProfile, branch, paymentMethods, taxes, hasOpening) async {
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

            Fluttertoast.showToast(
              msg: "Order Submitted",
              gravity: ToastGravity.BOTTOM,
              backgroundColor: Colors.green,
              textColor: Colors.white,
            );
          }
        } catch (e) {
          print('Submit order error: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error submitting order: $e')),
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
          hasOpening) async {
        // Auto-save all remarks before proceeding
        _autoSaveAllRemarks();

        // Get the full table name from floors and tables API
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

        // Prepare items with proper structure
        final items = currentOrderItems.map((item) {
          dynamic variantInfo = item['custom_variant_info'];

          return {
            'item_code': item['item_code'] ?? '',
            'qty': item['quantity'],
            'price_list_rate': item['price'],
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
                            item['image'],
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
    double basePrice = item['price'];
    double additionalCost = _calculateAdditionalCost(item);
    double totalPrice = basePrice + additionalCost;

    // Ensure we have a controller for this item
    if (index >= _itemRemarkControllers.length) {
      _itemRemarkControllers
          .add(TextEditingController(text: item['custom_item_remarks'] ?? ''));
    } else {
      _itemRemarkControllers[index].text = item['custom_item_remarks'] ?? '';
    }

    // Parse variant info if it exists
    String variantText = '';
    // Parse options if variant info exists
    Map<String, dynamic> options = {};
    String optionText = '';
    dynamic customVariantInfo = item['custom_variant_info'];

    // Parse the variant info if it exists
    if (customVariantInfo != null) {
      try {
        // Handle both string (JSON) and direct list formats
        dynamic parsed = customVariantInfo is String
            ? jsonDecode(customVariantInfo)
            : customVariantInfo;

        if (parsed is List && parsed.isNotEmpty) {
          // New format - list of direct option maps
          if (parsed[0] is Map) {
            options = Map<String, dynamic>.from(parsed[0]);
            optionText =
                options.entries.map((e) => '${e.key}: ${e.value}').join(', ');
            variantText = optionText;
          }
        }
      } catch (e) {
        debugPrint('Variant parsing error: $e');
      }
    }

    List<Widget> variantWidgets = [];
    if (item['custom_variant_info'] != null &&
        item['custom_variant_info'] is List) {
      for (var variant in item['custom_variant_info']) {
        if (variant is Map) {
          variantWidgets.add(
            Text(
              '• ${variant['variant_group']}: ${variant['option']}${variant['additional_cost'] > 0 ? ' +RM ${variant['additional_cost'].toStringAsFixed(2)}' : ''}',
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
                        '${item['image']}',
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
                    if (variantText.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (variantWidgets.isNotEmpty)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: variantWidgets,
                            ),
                          if (additionalCost > 0)
                            Text(
                              '+RM ${additionalCost.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: Color(0xFFE732A0),
                                fontSize: 12,
                              ),
                            ),
                        ],
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
            ],
          ),
          // Quantity controls and delete button moved here
          Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 0, right: 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
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
                        onPressed: () => _increaseQuantity(index),
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
          ),
          // Serve Later section
          Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 0, bottom: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
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
                            value; // Fixed: directly set the value
                      });
                    },
                    activeColor: Color(0xFFE732A0),
                  ),
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
          Navigator.pop(context, {
            'action': 'deleted',
            'tableNumber': widget.tableNumber,
          });
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete order: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
              posProfile, branch, paymentMethods, taxes, hasOpening) {
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
}
