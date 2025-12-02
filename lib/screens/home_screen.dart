import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiok_pos_android_app/components/image_url_helper.dart';
import 'package:shiok_pos_android_app/components/main_layout.dart';
import 'package:shiok_pos_android_app/components/no_stretch_scroll_behavior.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/screens/checkout_screen.dart';
import 'package:shiok_pos_android_app/secondary%20screen/customer_display_controller.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final String tableNumber;
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
  String baseImageUrl = '';
  Map<String, int> _itemStockQuantities =
      {}; // key: item_code, value: available stock
  bool _isLoadingStock = false;
  final ScrollController _scrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _loadBaseUrl();
    _loadItemGroups();
    _loadAvailableItems();
    _initializeOrderItems();

    // Listen to scroll events
    _scrollController.addListener(_updateScrollButtons);

    // Initialize scroll buttons after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollButtons();
    });
  }

  Future<void> _loadBaseUrl() async {
    baseImageUrl = await ImageUrlHelper.getBaseImageUrl();
    setState(() {}); // Refresh UI
  }

  void _initializeOrderItems() {
    if (!mounted) return;

    if (widget.existingOrder != null &&
        widget.existingOrder!['items'] != null) {
      currentOrderItems = (widget.existingOrder!['items'] as List).map((item) {
        // Convert old format to new format if needed
        double additionalCost = _calculateAdditionalCost(item);
        double itemPrice = (item['price'] ?? 0) + additionalCost;

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
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollButtons() {
    if (!mounted) return;

    final scrollPosition = _scrollController.position;
    setState(() {
      _canScrollLeft = scrollPosition.pixels > 0;
      _canScrollRight = scrollPosition.pixels < scrollPosition.maxScrollExtent;
    });
  }

  void _scrollLeft() {
    final scrollPosition = _scrollController.position;
    final newPosition = scrollPosition.pixels - 200; // Scroll 200 pixels left
    _scrollController.animateTo(
      newPosition.clamp(0, scrollPosition.maxScrollExtent),
      duration: Duration(milliseconds: 100),
      curve: Curves.easeInOut,
    );
  }

  void _scrollRight() {
    final scrollPosition = _scrollController.position;
    final newPosition = scrollPosition.pixels + 200; // Scroll 200 pixels right
    _scrollController.animateTo(
      newPosition.clamp(0, scrollPosition.maxScrollExtent),
      duration: Duration(milliseconds: 100),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _loadItemGroups() async {
    if (!mounted) return;

    try {
      final authState = ref.read(authProvider);
      authState.whenOrNull(
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
          if (mounted) {
            setState(() {
              // Convert the itemsGroups from login response
              List<Map<String, dynamic>> groups = itemsGroups
                  .where((group) => group != 'All Item Groups')
                  .map((groupName) => {
                        'name': groupName.toString(),
                        'value': groupName.toString(),
                        'disabled': 0,
                      })
                  .toList();
              this.itemGroups = [
                {
                  'name': 'All',
                  'value': 'All',
                  'disabled': 0,
                },
                ...groups,
              ];
              _isLoadingItemGroups = false;
            });

            // Update scroll buttons after data is loaded and UI is built
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _updateScrollButtons();
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingItemGroups = false);
      }
      Fluttertoast.showToast(
        msg: 'Error loading item groups: $e',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  Future<void> _loadAvailableItems() async {
    if (!mounted) return;

    try {
      final authState = ref.read(authProvider);
      await authState.whenOrNull(
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
        ) async {
          final posService = PosService();
          final response =
              await posService.getItems(posProfile); // Pass posProfile here

          if (response['success'] == true) {
            if (mounted) {
              setState(() {
                availableItems = List<Map<String, dynamic>>.from(
                    response['message']['items']);
                _isLoadingItems = false;
              });
            }
            await _loadVariantGroupsForItems();

            // Check stock after items are loaded
            _checkStockForItems();
          } else {
            throw Exception('Failed to load available items');
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingItems = false);
      }
      Fluttertoast.showToast(
        msg: 'Error loading available items: $e',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  Future<void> _loadVariantGroupsForItems() async {
    try {
      final response = await PosService().getVariantGroups();

      if (response['success'] == true) {
        final variantGroups =
            List<Map<String, dynamic>>.from(response['message']);

        // Enrich each item with variant group configuration
        for (var item in availableItems) {
          if (item['structured_variant_info'] != null &&
              item['structured_variant_info'] is List) {
            final variants = List<Map<String, dynamic>>.from(
                item['structured_variant_info']);

            for (var variant in variants) {
              final variantGroupName = variant['variant_group'];
              final matchingGroup = variantGroups.firstWhere(
                (group) => group['variant_group'] == variantGroupName,
                orElse: () => {},
              );

              if (matchingGroup.isNotEmpty) {
                // Add the configuration values to the variant
                variant['required'] = matchingGroup['required'] ?? 0;
                variant['option_required_no'] =
                    matchingGroup['option_required_no'] ?? 1;
                variant['maximum_selection'] =
                    matchingGroup['maximum_selection'] ?? 1;
                variant['allow_multiple_selection'] =
                    matchingGroup['allow_multiple_selection'] ?? 0;
              } else {
                // Default values if variant group not found
                variant['required'] = 0;
                variant['option_required_no'] = 1;
                variant['maximum_selection'] = 1;
                variant['allow_multiple_selection'] = 0;
              }
            }
          }
        }

        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      debugPrint('Error loading variant groups for items: $e');
      // Don't show error toast as this is a background process
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
    if (!mounted) return;
    if (_isLoadingStock) return;

    if (mounted) {
      setState(() => _isLoadingStock = true);
    }

    final authState = ref.read(authProvider);
    await authState.whenOrNull(
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
      ) async {
        try {
          final response = await PosService().getStockBalanceSummary(
            posProfile: posProfile,
            isPosItem: 1,
            disable: 0,
          );

          if (response['success'] == true) {
            final newStockQuantities = <String, int>{};

            // Safely extract the message
            final message = response['message'];

            if (message == null) {
              debugPrint('Stock API returned null message');
              _setDefaultStockQuantities(newStockQuantities);
            } else if (message is! List) {
              debugPrint(
                  'Stock API message is not a List, type: ${message.runtimeType}');
              _setDefaultStockQuantities(newStockQuantities);
            } else {
              // Message is a List, process it
              final stockData = message as List;

              // Create a map for quick lookup by item code
              final stockMap = <String, Map<String, dynamic>>{};

              for (var stockItem in stockData) {
                if (stockItem is Map<String, dynamic>) {
                  final itemCode = stockItem['item']?.toString();
                  if (itemCode != null) {
                    stockMap[itemCode] = stockItem;
                  }
                }
              }

              // Update stock quantities for available items
              for (var item in availableItems) {
                final itemCode = item['item_code'];
                final stockItem = stockMap[itemCode];

                if (stockItem != null) {
                  // Safely extract quantity
                  final qtyValue = stockItem['qty'];
                  int stockQty = 0;

                  if (qtyValue != null) {
                    if (qtyValue is num) {
                      stockQty = qtyValue.toInt();
                    } else if (qtyValue is String) {
                      stockQty = int.tryParse(qtyValue) ?? 0;
                    }
                  }

                  newStockQuantities[itemCode] = stockQty;
                } else {
                  // Item not found in stock data, assume 0 stock
                  newStockQuantities[itemCode] = 0;
                }
              }
            }

            if (mounted) {
              setState(() {
                _itemStockQuantities = newStockQuantities;
              });
            }
          } else {
            debugPrint(
                'Stock API returned success=false: ${response['message']}');
            _setDefaultStockQuantities(<String, int>{});
          }
        } catch (e, stackTrace) {
          debugPrint('Error checking stock: $e');
          debugPrint('Stack trace: $stackTrace');
          _setDefaultStockQuantities(<String, int>{});
        } finally {
          if (mounted) {
            setState(() => _isLoadingStock = false);
          }
        }
      },
    );
  }

// Helper method to set default stock quantities
  void _setDefaultStockQuantities(Map<String, int> quantities) {
    for (var item in availableItems) {
      quantities[item['item_code']] = 999; // Assume unlimited
    }

    if (mounted) {
      setState(() {
        _itemStockQuantities = quantities;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get the correct items list based on selection
    List<Map<String, dynamic>> displayedItems = _getFilteredItems();
    final authState = ref.watch(authProvider);

    return authState.when(
        initial: () => const Center(),
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
          WidgetsBinding.instance.addPostFrameCallback((_) {
            CustomerDisplayController.showCustomerScreen();
            final taxDetails = _getTaxDetailsForCustomerDisplay();

            CustomerDisplayController.updateOrderDisplay(
              items: currentOrderItems.map((item) {
                return {
                  'name': item['name'] ?? 'Unknown',
                  'price': (item['price'] +
                              _calculateVariantCost(item['custom_variant_info'])
                          is int)
                      ? (item['price'] +
                              _calculateVariantCost(
                                  item['custom_variant_info']) as int)
                          .toDouble()
                      : item['price'] +
                              _calculateVariantCost(item['custom_variant_info'])
                          as double,
                  'quantity': (item['quantity'] is int)
                      ? item['quantity'] as int
                      : (item['quantity'] as double).toInt(),
                  'discount_amount': item['discount_amount'] ?? 0.0,
                  'custom_serve_later': item['custom_serve_later'] ?? false,
                  'custom_item_remarks': item['custom_item_remarks'] ?? '',
                  'custom_variant_info':
                      item['custom_variant_info']?.toString() ?? '',
                };
              }).toList(),
              subtotal: _calculateSubtotal(),
              tax: _calculateGST(),
              discount: _getDiscountAmount(),
              rounding: _getRoundingDifference(),
              total: _getRoundedTotal(),
              taxRate: _getGSTRate(),
              taxDetails: taxDetails,
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
                                            if (tier.toLowerCase() ==
                                                'tier 3') ...[
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
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                Text(
                                                  widget.isTier1
                                                      ? 'Instant Order'
                                                      : '${widget.tableNumber}',
                                                  style: const TextStyle(
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                // Add opening status - access directly from auth state
                                                Consumer(
                                                  builder:
                                                      (context, ref, child) {
                                                    final authState =
                                                        ref.watch(authProvider);
                                                    return authState.when(
                                                      initial: () =>
                                                          Container(), // Hide while loading
                                                      unauthenticated: () =>
                                                          Container(), // Hide if not authenticated
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
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 8),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: hasOpening
                                                                ? Colors.green
                                                                : Colors.red,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        30),
                                                          ),
                                                          child: Text(
                                                            hasOpening
                                                                ? 'Opening Entry: ${DateFormat('hh:mm a dd MMM yyyy').format(openingDate ?? DateTime.now())}'
                                                                : 'No Opening Entry',
                                                            style:
                                                                const TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontSize: 14,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                    );
                                                  },
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        if (tier.toLowerCase() == 'tier 3') ...[
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
                                        ? Center(
                                            child: CircularProgressIndicator())
                                        : Container(
                                            height: _calculateContainerHeight(),
                                            child: Stack(
                                              children: [
                                                // Main content with both rows in one scrollable area
                                                NotificationListener<
                                                    ScrollNotification>(
                                                  onNotification:
                                                      (scrollNotification) {
                                                    if (scrollNotification
                                                            is ScrollUpdateNotification ||
                                                        scrollNotification
                                                            is ScrollEndNotification) {
                                                      _updateScrollButtons();
                                                    }
                                                    return false;
                                                  },
                                                  child: ScrollConfiguration(
                                                    behavior:
                                                        NoStretchScrollBehavior(),
                                                    child:
                                                        SingleChildScrollView(
                                                      scrollDirection:
                                                          Axis.horizontal,
                                                      controller:
                                                          _scrollController,
                                                      child: Column(
                                                        children: [
                                                          // First row
                                                          if (itemGroups
                                                                  .length >
                                                              0)
                                                            _buildFirstRow(),
                                                          // Second row (only if needed)
                                                          if (itemGroups
                                                                  .length >
                                                              _getFirstRowCount())
                                                            SizedBox(height: 8),
                                                          if (itemGroups
                                                                  .length >
                                                              _getFirstRowCount())
                                                            _buildSecondRow(),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),

                                                // Left scroll arrow
                                                if (itemGroups.length >
                                                        _getFirstRowCount() &&
                                                    _canScrollLeft)
                                                  Positioned(
                                                    left: 0,
                                                    top: 0,
                                                    bottom: 0,
                                                    child: Container(
                                                      width: 40,
                                                      decoration: BoxDecoration(
                                                        gradient:
                                                            LinearGradient(
                                                          begin: Alignment
                                                              .centerLeft,
                                                          end: Alignment
                                                              .centerRight,
                                                          colors: [
                                                            Colors.white,
                                                            Colors.white
                                                                .withOpacity(
                                                                    0.0),
                                                          ],
                                                        ),
                                                      ),
                                                      child: Center(
                                                        child: Material(
                                                          color: Colors.white,
                                                          elevation: 2,
                                                          shape: CircleBorder(),
                                                          child: InkWell(
                                                            onTap: _scrollLeft,
                                                            customBorder:
                                                                CircleBorder(),
                                                            child: Container(
                                                              width: 32,
                                                              height: 32,
                                                              child: Icon(
                                                                Icons
                                                                    .chevron_left,
                                                                color: Colors
                                                                    .black87,
                                                                size: 24,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),

                                                // Right scroll arrow
                                                if (itemGroups.length >
                                                        _getFirstRowCount() &&
                                                    _canScrollRight)
                                                  Positioned(
                                                    right: 0,
                                                    top: 0,
                                                    bottom: 0,
                                                    child: Container(
                                                      width: 40,
                                                      decoration: BoxDecoration(
                                                        gradient:
                                                            LinearGradient(
                                                          begin: Alignment
                                                              .centerRight,
                                                          end: Alignment
                                                              .centerLeft,
                                                          colors: [
                                                            Colors.white,
                                                            Colors.white
                                                                .withOpacity(
                                                                    0.0),
                                                          ],
                                                        ),
                                                      ),
                                                      child: Center(
                                                        child: Material(
                                                          color: Colors.white,
                                                          elevation: 2,
                                                          shape: CircleBorder(),
                                                          child: InkWell(
                                                            onTap: _scrollRight,
                                                            customBorder:
                                                                CircleBorder(),
                                                            child: Container(
                                                              width: 32,
                                                              height: 32,
                                                              child: Icon(
                                                                Icons
                                                                    .chevron_right,
                                                                color: Colors
                                                                    .black87,
                                                                size: 24,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                  ),

                                  // Search Bar
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        left: 16.0,
                                        right: 16.0,
                                        top: 10.0,
                                        bottom: 5.0),
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
                                        : _selectedItemGroup == 'All'
                                            ? _buildGroupedMenuView()
                                            : _buildStandardMenuView(),
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
                                      if (_hasDiscount())
                                        _buildOrderSummaryRow(
                                          'Discount ${_getDiscountLabel()}',
                                          '-RM ${_getDiscountAmount().toStringAsFixed(2)}',
                                        ),
                                      _buildTaxSummaryRows(),
                                      _buildOrderSummaryRow(
                                          'Rounding', _getRoundingLabel()),
                                      const SizedBox(height: 10),
                                      Column(
                                        children: [
                                          if (tier.toLowerCase() ==
                                              'tier 3') ...[
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
                                              onPressed: _isLoading
                                                  ? null
                                                  : _goToCheckout,
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    const Color(0xFFE732A0),
                                                minimumSize:
                                                    const Size.fromHeight(50),
                                              ),
                                              child: _isLoading
                                                  ? SizedBox(
                                                      height: 18,
                                                      width: 18,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        valueColor:
                                                            AlwaysStoppedAnimation<
                                                                    Color>(
                                                                Colors.white),
                                                      ),
                                                    )
                                                  : Text(
                                                      'Checkout RM ${_getRoundedTotal().toStringAsFixed(2)}',
                                                      style: const TextStyle(
                                                        fontSize: 20,
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w600,
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

  int _getFirstRowCount() {
    int total = itemGroups.length;
    if (total <= 7) return total;
    return (total / 2).ceil(); // For 16 groups = 8
  }

  int _getSecondRowCount() {
    int total = itemGroups.length;
    if (total <= 7) return 0;
    return total - _getFirstRowCount(); // For 16 groups = 8
  }

  double _calculateContainerHeight() {
    int totalGroups = itemGroups.length;
    if (totalGroups <= 7) {
      return 50; // Single row
    } else {
      return 90; // Two rows (40 + 40 + 8 spacing)
    }
  }

  Widget _buildFirstRow() {
    int firstRowCount = _getFirstRowCount();
    double rowWidth = (120 * firstRowCount) + (8 * (firstRowCount - 1));

    return SizedBox(
      height: 40,
      child: NotificationListener<ScrollNotification>(
        onNotification: (scrollNotification) {
          if (scrollNotification is ScrollUpdateNotification ||
              scrollNotification is ScrollEndNotification) {
            _updateScrollButtons();
          }
          return false;
        },
        child: ScrollConfiguration(
          behavior: NoStretchScrollBehavior(),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              width: rowWidth,
              child: Row(
                children: [
                  for (int i = 0; i < firstRowCount; i++)
                    Container(
                      margin:
                          EdgeInsets.only(right: i < firstRowCount - 1 ? 8 : 0),
                      child: _buildItemGroupButton(i),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecondRow() {
    int firstRowCount = _getFirstRowCount();
    int secondRowCount = _getSecondRowCount();
    double rowWidth = (120 * secondRowCount) + (8 * (secondRowCount - 1));

    return SizedBox(
      height: 40,
      child: NotificationListener<ScrollNotification>(
        onNotification: (scrollNotification) {
          if (scrollNotification is ScrollUpdateNotification ||
              scrollNotification is ScrollEndNotification) {
            _updateScrollButtons();
          }
          return false;
        },
        child: ScrollConfiguration(
          behavior: NoStretchScrollBehavior(),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              width: rowWidth,
              child: Row(
                children: [
                  for (int i = firstRowCount; i < itemGroups.length; i++)
                    Container(
                      margin: EdgeInsets.only(
                          right: i < itemGroups.length - 1 ? 8 : 0),
                      child: _buildItemGroupButton(i),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItemGroupButton(int index) {
    return SizedBox(
      width: 120,
      height: 40,
      child: ElevatedButton(
        onPressed: () {
          setState(() {
            _selectedItemGroupIndex = index;
            _selectedItemGroup = itemGroups[index]['value'];
            searchController.clear();
            searchQuery = '';
          });
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: _selectedItemGroupIndex == index
              ? Colors.yellow
              : const Color(0xFFF2F3F4),
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          elevation: _selectedItemGroupIndex == index ? 2 : 0,
          shadowColor: Colors.black12,
        ),
        child: Text(
          itemGroups[index]['name'],
          style: TextStyle(
            fontWeight: _selectedItemGroupIndex == index
                ? FontWeight.bold
                : FontWeight.normal,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
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

    // Sort items by name alphabetically
    filteredItems.sort((a, b) => (a['item_name'] ?? '')
        .toLowerCase()
        .compareTo((b['item_name'] ?? '').toLowerCase()));

    return filteredItems;
  }

// Add a new method to group items by item group
  Map<String, List<Map<String, dynamic>>> _getGroupedItems() {
    Map<String, List<Map<String, dynamic>>> groupedItems = {};

    for (var item in availableItems) {
      String groupName = item['item_group'] ?? 'Uncategorized';
      if (!groupedItems.containsKey(groupName)) {
        groupedItems[groupName] = [];
      }
      groupedItems[groupName]!.add(item);
    }

    // Sort items within each group alphabetically
    groupedItems.forEach((groupName, items) {
      items.sort((a, b) => (a['item_name'] ?? '')
          .toLowerCase()
          .compareTo((b['item_name'] ?? '').toLowerCase()));
    });

    // Sort groups alphabetically
    final sortedGroups = groupedItems.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    Map<String, List<Map<String, dynamic>>> sortedGroupedItems = {};
    for (var groupName in sortedGroups) {
      sortedGroupedItems[groupName] = groupedItems[groupName]!;
    }

    return sortedGroupedItems;
  }

  Widget _buildStandardMenuView() {
    List<Map<String, dynamic>> displayedItems = _getFilteredItems();

    return ScrollConfiguration(
      behavior: NoStretchScrollBehavior(),
      child: GridView.builder(
        padding: const EdgeInsets.all(16.0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.8,
        ),
        itemCount: displayedItems.length,
        itemBuilder: (context, index) {
          return _buildMenuItem(displayedItems[index], index);
        },
      ),
    );
  }

  Widget _buildGroupedMenuView() {
    Map<String, List<Map<String, dynamic>>> groupedItems = _getGroupedItems();
    List<String> groupNames = groupedItems.keys.toList();

    // Apply search filter to grouped items
    if (searchQuery.isNotEmpty) {
      Map<String, List<Map<String, dynamic>>> filteredGroupedItems = {};

      groupedItems.forEach((groupName, items) {
        List<Map<String, dynamic>> filteredItems = items.where((item) {
          return item['item_name']
              .toLowerCase()
              .contains(searchQuery.toLowerCase());
        }).toList();

        if (filteredItems.isNotEmpty) {
          filteredGroupedItems[groupName] = filteredItems;
        }
      });

      groupedItems = filteredGroupedItems;
      groupNames = groupedItems.keys.toList();
    }

    return ScrollConfiguration(
      behavior: NoStretchScrollBehavior(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: groupNames.length,
        itemBuilder: (context, groupIndex) {
          String groupName = groupNames[groupIndex];
          List<Map<String, dynamic>> groupItems = groupedItems[groupName]!;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Group Header
              Padding(
                padding: EdgeInsets.only(
                    bottom: 16.0, top: groupIndex > 0 ? 24.0 : 0.0),
                child: Text(
                  groupName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              // Items Grid for this group
              GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 16.0),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.8,
                ),
                itemCount: groupItems.length,
                itemBuilder: (context, itemIndex) {
                  return _buildMenuItem(groupItems[itemIndex], itemIndex);
                },
              ),
              // Divider between groups (except after last group)
              if (groupIndex < groupNames.length - 1)
                Divider(
                  color: Colors.grey.shade300,
                  thickness: 1,
                  height: 32,
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showItemOptionsDialog(Map<String, dynamic> item) async {
    List<Map<String, dynamic>> variants =
        List.from(item['structured_variant_info'] ?? []);

    // Track selected options for each variant group
    Map<String, List<String?>> selectedOptions = {};
    Map<String, int> currentSelections = {};

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
                        final variantGroup = variant['variant_group'];
                        final isRequired = variant['required'] == 1;
                        final minSelection =
                            (variant['option_required_no'] ?? 1) as int;
                        final maxSelection =
                            (variant['maximum_selection'] ?? 1) as int;
                        final allowMultiple =
                            (variant['allow_multiple_selection'] ?? 0) == 1;

                        // Initialize selected options for this variant group
                        selectedOptions[variantGroup] ??= [];
                        currentSelections[variantGroup] ??= 0;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              variantGroup,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (isRequired)
                              Text(
                                '(Required - Select ${minSelection} to ${maxSelection})',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            if (!isRequired && allowMultiple)
                              Text(
                                '(Select up to ${maxSelection})',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            SizedBox(height: 8),
                            ...(variant['options'] as List).map((option) {
                              final isSelected = selectedOptions[variantGroup]!
                                  .contains(option['option']);

                              return Container(
                                margin: EdgeInsets.only(bottom: 4),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: isSelected
                                        ? Color(0xFFE732A0)
                                        : Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: CheckboxListTile(
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
                                  value: isSelected,
                                  activeColor: Color(0xFFE732A0),
                                  onChanged: (value) {
                                    setState(() {
                                      if (value == true) {
                                        // Multiple selection allowed
                                        if (allowMultiple) {
                                          if (currentSelections[variantGroup]! <
                                              maxSelection) {
                                            selectedOptions[variantGroup]!
                                                .add(option['option']);
                                            currentSelections[variantGroup] =
                                                currentSelections[
                                                        variantGroup]! +
                                                    1;
                                          }
                                        } else {
                                          // Single selection: replace the existing
                                          selectedOptions[variantGroup]!
                                              .clear();
                                          selectedOptions[variantGroup]!
                                              .add(option['option']);
                                          currentSelections[variantGroup] = 1;
                                        }
                                      } else {
                                        // Remove selection
                                        selectedOptions[variantGroup]!
                                            .remove(option['option']);
                                        currentSelections[variantGroup] =
                                            (currentSelections[variantGroup]! -
                                                    1)
                                                .clamp(0, maxSelection);
                                      }
                                    });
                                  },
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
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
                    bool allRequirementsMet = true;
                    String errorMessage = '';

                    for (var variant in variants) {
                      final variantGroup = variant['variant_group'];
                      final isRequired = variant['required'] == 1;
                      final minSelection = variant['option_required_no'] ?? 1;
                      final selectedCount =
                          selectedOptions[variantGroup]?.length ?? 0;

                      if (isRequired) {
                        if (selectedCount < minSelection) {
                          allRequirementsMet = false;
                          errorMessage =
                              "Please select at least $minSelection options for ${variant['variant_group']}";
                          break;
                        }
                      }

                      final maxSelection = variant['maximum_selection'] ?? 1;
                      if (selectedCount > maxSelection) {
                        allRequirementsMet = false;
                        errorMessage =
                            "Cannot select more than $maxSelection options for ${variant['variant_group']}";
                        break;
                      }
                    }

                    if (allRequirementsMet) {
                      // Convert to the format expected by _addToOrderWithOptions
                      Map<String, String?> singleSelectionOptions = {};
                      for (var variantGroup in selectedOptions.keys) {
                        final selections = selectedOptions[variantGroup]!;
                        if (selections.isNotEmpty) {
                          // For single selection, take the first one
                          // For multiple selection, we'll handle it differently
                          singleSelectionOptions[variantGroup] =
                              selections.first;
                        }
                      }

                      _addToOrderWithOptions(item, selectedOptions);
                      Navigator.pop(context);
                    } else {
                      Fluttertoast.showToast(
                        msg: errorMessage,
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
    Map<String, List<String?>> selectedOptions,
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

    // Check if we're adding a new item or increasing quantity of existing one
    int existingIndex = currentOrderItems.indexWhere((orderItem) =>
        orderItem['item_code'] == item['item_code'] &&
        _compareOptions(orderItem['options'], selectedOptions));

    if (existingIndex != -1) {
      // For existing item with same options, check if we can increase quantity
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
      // For new item or new variant combination, check total stock across all variants
      int totalQuantityOfAllVariants = currentOrderItems
          .where((orderItem) => orderItem['item_code'] == itemCode)
          .fold(0,
              (sum, orderItem) => sum + (orderItem['quantity'] as num).toInt());

      if (totalQuantityOfAllVariants >= availableStock) {
        Fluttertoast.showToast(
          msg: "Cannot add more than available stock ($availableStock)",
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
          final selectedOptionList =
              selectedOptions[variantGroup['variant_group']] ?? [];
          if (selectedOptionList.isNotEmpty) {
            for (var selectedOptionName in selectedOptionList) {
              for (var option in variantGroup['options']) {
                if (option['option'] == selectedOptionName) {
                  double optionCost =
                      (option['additional_cost'] as num).toDouble();
                  totalAdditionalCost += optionCost;

                  variantInfo.add({
                    'variant_group': variantGroup['variant_group'],
                    'options': [
                      {
                        'option': selectedOptionName,
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
              .map((e) => '${e.key}: ${e.value.join(", ")}')
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

  bool _compareOptions(dynamic options1, Map<String, List<String?>> options2) {
    if (options1 == null || options2 == null) return false;

    // Handle both single selection (Map) and multiple selection (Map with Lists)
    if (options1 is Map<String, dynamic> &&
        options2 is Map<String, List<String?>>) {
      // Convert single selection to multiple selection format for comparison
      Map<String, List<String?>> convertedOptions1 = {};

      options1.forEach((key, value) {
        if (value is String) {
          convertedOptions1[key] = [value];
        } else if (value is List<String>) {
          convertedOptions1[key] = value;
        }
      });

      if (convertedOptions1.length != options2.length) return false;

      for (var key in convertedOptions1.keys) {
        final list1 = convertedOptions1[key]!;
        final list2 = options2[key];

        if (list2 == null || list1.length != list2.length) return false;

        // Check if both lists contain the same options (order doesn't matter)
        if (!list1.every((option) => list2.contains(option)) ||
            !list2.every((option) => list1.contains(option))) {
          return false;
        }
      }

      return true;
    }

    return false;
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
        opneingDate,
        itemsGroups,
        baseUrl,
        merchantId,
        printMerchantReceiptCopy,
        enableFiuu,
      ) {
        return tier.toLowerCase() != 'tier 3';
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
      ) async {
        setState(() => _isLoading = true);

        try {
          // 1. Get the full table name from floors and tables API
          final floorsResponse = await PosService().getFloorsAndTables(branch);
          String tableFullName = '${widget.tableNumber}'; // fallback

          if (floorsResponse['success'] == true) {
            for (var floor in floorsResponse['message']) {
              for (var table in floor['tables']) {
                if (table['title'] == '${widget.tableNumber}') {
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
      await authState.whenOrNull(authenticated: (
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
      ) async {
        if (!hasOpening) {
          // Show dialog if no opening entry exists
          _showOpeningRequiredDialog();
          return;
        }

        // Auto-save all remarks before proceeding
        _autoSaveAllRemarks();

        // Get the full table name from floors and tables API
        final floorsResponse = await PosService().getFloorsAndTables(branch);
        String? tableFullName;

        for (var floor in floorsResponse['message']) {
          final tables = floor['tables'];

          if (tables is Map<String, dynamic>) {
            if (tables['is_default'] == 1) {
              tableFullName = tables['name'];
              break;
            }
          } else if (tables is List) {
            for (var table in tables) {
              if (table['title'] == '${widget.tableNumber}') {
                tableFullName = table['name'];
                break;
              }
            }
          }
        }

        tableFullName ??= '${widget.tableNumber}';

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
            'custom_variant_info': variantInfo,
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
              name: widget.existingOrder!['orderId'],
              couponCode: widget.existingOrder!['coupon_code'],
              remarks: widget.existingOrder!['remarks'],
              custom_user_voucher:
                  widget.existingOrder!['custom_user_voucher']);

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
                'tableFullName': tableFullName,
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
                            12.0), // Adjust the value as needed
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
                                    Image.asset(
                                  'assets/pizza.png',
                                  fit: BoxFit.cover,
                                  height: 70,
                                  width: double.infinity,
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

    // Check if this item has remarks
    bool hasRemarks = item['custom_item_remarks'] != null &&
        item['custom_item_remarks'].toString().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: item['image'] != null
                    ? Image.network(
                        '$baseImageUrl${item['image']}',
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            Image.asset(
                          'assets/pizza.png',
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Image.asset(
                        'assets/pizza.png',
                        width: 50,
                        height: 50,
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
                    // Show remarks if they exist
                    if (hasRemarks)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          'Remarks: ${item['custom_item_remarks']}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    SizedBox(height: 2),
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
                        // Add Remarks Button
                        IconButton(
                          icon: Icon(
                            Icons.note_add_outlined,
                            size: 20,
                            color: hasRemarks ? Color(0xFFE732A0) : Colors.grey,
                          ),
                          onPressed: () => _showRemarksDialog(index),
                          tooltip: 'Add remarks',
                        ),
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
          Divider(color: Colors.grey.shade200),
        ],
      ),
    );
  }

// Add this new method to show remarks dialog
  void _showRemarksDialog(int index) {
    TextEditingController remarksController = TextEditingController(
        text: currentOrderItems[index]['custom_item_remarks'] ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        title: Text(
          'Add Remarks',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              currentOrderItems[index]['name'],
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 16),
            TextField(
              controller: remarksController,
              decoration: InputDecoration(
                hintText: 'Enter remarks (e.g., Less spicy, No onion...)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Color(0xFFE732A0)),
                ),
              ),
              maxLines: 3,
              textInputAction: TextInputAction.done,
            ),
          ],
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
              setState(() {
                currentOrderItems[index]['custom_item_remarks'] =
                    remarksController.text.trim();
              });
              Navigator.pop(context);
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
              'SAVE',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
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

  Widget _buildTaxSummaryRows() {
    final authState = ref.read(authProvider);
    return authState.whenOrNull(
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
            // Filter out taxes with 0% rate and calculate each tax
            final applicableTaxes = taxes.where((tax) {
              final rate = (tax['rate'] ?? 0.0).toDouble();
              return rate > 0;
            }).toList();

            if (applicableTaxes.isEmpty) {
              return SizedBox.shrink();
            }

            // Calculate subtotal for tax calculation
            double subtotal = _calculateSubtotal();
            double discount = _getDiscountAmount();
            double taxableAmount = subtotal - discount;

            return Column(
              children: applicableTaxes.map((tax) {
                final taxName = tax['description'] ?? 'Tax';
                final taxRate = (tax['rate'] ?? 0.0).toDouble();
                final taxAmount = taxableAmount * (taxRate / 100);

                return _buildOrderSummaryRow(
                  '$taxName (${taxRate.toStringAsFixed(1)}%)',
                  'RM ${taxAmount.toStringAsFixed(2)}',
                );
              }).toList(),
            );
          },
        ) ??
        SizedBox.shrink();
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

    // Calculate total quantity of this item across all variants
    int totalQuantityOfAllVariants = currentOrderItems
        .where((orderItem) => orderItem['item_code'] == itemCode)
        .fold(0,
            (sum, orderItem) => sum + (orderItem['quantity'] as num).toInt());

    if (totalQuantityOfAllVariants >= availableStock) {
      Fluttertoast.showToast(
        msg: "Cannot add more than available stock ($availableStock)",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
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
            // Calculate total of all applicable taxes
            double subtotal = _calculateSubtotal();
            double discount = _getDiscountAmount();
            double taxableAmount = subtotal - discount;

            double totalTax = 0.0;
            for (var tax in taxes) {
              final taxRate = (tax['rate'] ?? 0.0).toDouble();
              if (taxRate > 0) {
                totalTax += taxableAmount * (taxRate / 100);
              }
            }
            return totalTax;
          },
        ) ??
        0.0;
  }

  List<Map<String, dynamic>> _getTaxDetailsForCustomerDisplay() {
    final authState = ref.read(authProvider);
    return authState.whenOrNull(
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
            // Filter out taxes with 0% rate
            final applicableTaxes = taxes.where((tax) {
              final rate = (tax['rate'] ?? 0.0).toDouble();
              return rate > 0;
            }).toList();

            if (applicableTaxes.isEmpty) {
              return [];
            }

            // Calculate subtotal for tax calculation
            double subtotal = _calculateSubtotal();
            double discount = _getDiscountAmount();
            double taxableAmount = subtotal - discount;

            // Create tax details with name, rate, and amount
            return applicableTaxes.map((tax) {
              final taxName = tax['description'] ?? 'Tax';
              final taxRate = (tax['rate'] ?? 0.0).toDouble();
              final taxAmount = taxableAmount * (taxRate / 100);

              return {
                'name': taxName,
                'rate': taxRate,
                'amount': taxAmount,
              };
            }).toList();
          },
        ) ??
        [];
  }

  // Check if there's a discount applied
  bool _hasDiscount() {
    return widget.existingOrder != null &&
        widget.existingOrder!['discount_amount'] != null &&
        (widget.existingOrder!['discount_amount'] as num) > 0;
  }

// Get the discount amount
  double _getDiscountAmount() {
    if (widget.existingOrder != null &&
        widget.existingOrder!['discount_amount'] != null) {
      return (widget.existingOrder!['discount_amount'] as num).toDouble();
    }
    return 0.0;
  }

// Get the discount label (voucher code)
  String _getDiscountLabel() {
    if (widget.existingOrder != null) {
      final voucherCode = widget.existingOrder!['user_voucher_code'] ??
          widget.existingOrder!['custom_user_voucher'];
      if (voucherCode != null && voucherCode.isNotEmpty) {
        return '($voucherCode)';
      }
    }
    return '';
  }

// Update the total calculation to account for discount
  double _calculateTotal() {
    double subtotal = _calculateSubtotal();
    double gst = _calculateGST();
    double discount = _getDiscountAmount();

    return subtotal - discount + gst;
  }

// Update the rounded total calculation to account for discount
  double _getUnroundedTotal() {
    double subtotal = _calculateSubtotal();
    double discount = _getDiscountAmount();
    double gstAmount = (subtotal - discount) * (_getGSTRateAsDouble() / 100);

    return (subtotal - discount) + gstAmount;
  }

// Helper method to get GST rate as double
  double _getGSTRateAsDouble() {
    final authState = ref.read(authProvider);
    return authState.whenOrNull(
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
            // Calculate combined tax rate for rounding calculations
            double combinedRate = 0.0;
            for (var tax in taxes) {
              final taxRate = (tax['rate'] ?? 0.0).toDouble();
              if (taxRate > 0) {
                combinedRate += taxRate;
              }
            }
            return combinedRate;
          },
        ) ??
        0.0;
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

  double _calculateVariantCost(dynamic variantInfo) {
    if (variantInfo == null) return 0.0;

    double totalVariantCost = 0.0;

    try {
      // Handle case where variantInfo is a JSON string
      dynamic parsedVariant = variantInfo;
      if (variantInfo is String) {
        try {
          parsedVariant = jsonDecode(variantInfo);
        } catch (e) {
          debugPrint('Error parsing variant info: $e');
          return 0.0;
        }
      }

      // Handle case where variantInfo is a List (new format)
      if (parsedVariant is List) {
        for (var variant in parsedVariant) {
          if (variant is Map && variant['options'] is List) {
            for (var option in variant['options']) {
              if (option is Map) {
                final additionalCost =
                    (option['additional_cost'] as num?)?.toDouble() ?? 0.0;
                totalVariantCost += additionalCost;
              }
            }
          }
        }
      }

      // Handle case where variantInfo is a Map (old format)
      if (parsedVariant is Map) {
        // Old format might not have additional cost info
        // You might need to adjust this based on your actual data structure
        debugPrint('Old variant format detected: $parsedVariant');
      }
    } catch (e) {
      debugPrint('Error calculating variant cost: $e');
    }

    return totalVariantCost;
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

  String _getGSTRate() {
    final authState = ref.read(authProvider);
    return authState.whenOrNull(
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
            // For backward compatibility, return the first tax rate if only one exists
            if (taxes.isNotEmpty) {
              final firstTax = taxes.first;
              return (firstTax['rate'] ?? 0.0).toStringAsFixed(0);
            }
            return '0';
          },
        ) ??
        '0';
  }
}
