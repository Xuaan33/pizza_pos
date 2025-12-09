import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shiok_pos_android_app/components/image_url_helper.dart';
import 'package:shiok_pos_android_app/components/no_stretch_scroll_behavior.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/screens/Settings%20Screen/item_group.dart';
import 'package:shiok_pos_android_app/screens/Settings%20Screen/variant_group.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';

class ItemManagement extends ConsumerStatefulWidget {
  const ItemManagement({super.key});

  @override
  ConsumerState<ItemManagement> createState() => _ItemManagementState();
}

class _ItemManagementState extends ConsumerState<ItemManagement> {
  List<Item> items = [];
  List<ItemGroup> itemGroups = [];
  List<VariantGroup> variantGroups = [];
  bool isLoading = true;
  Map<String, Item> _detailedItemsCache = {}; // Cache for detailed items

  // New state variables for search and sorting
  String _searchQuery = '';
  String _sortBy = 'name'; // Default sort by name
  bool _sortAscending = true;
  String? _filterStatus; // 'active', 'inactive', or null for all
  String? _filterPosStatus; // 'pos', 'non-pos', or null for all
  String? _filterItemGroup; // Specific item group or null for all
  String? _filterVariantGroup; // Specific variant group or null for all

  String? _tempFilterStatus;
  String? _tempFilterPosStatus;
  String? _tempFilterItemGroup;
  String? _tempFilterVariantGroup;
  String? _tempSortBy;
  bool? _tempSortAscending;
  String baseImageUrl = '';

  // Progress tracking
  bool _isLoadingDetails = false;
  int _loadedItemsCount = 0;
  int _totalItemsCount = 0;

  // NEW: Scroll controller to preserve position
  final ScrollController _scrollController = ScrollController();

  // NEW: Track if we're doing a single item update
  bool _isSingleItemUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadBaseUrl();
    _loadData();

    _tempFilterStatus = _filterStatus;
    _tempFilterPosStatus = _filterPosStatus;
    _tempFilterItemGroup = _filterItemGroup;
    _tempFilterVariantGroup = _filterVariantGroup;
    _tempSortBy = _sortBy;
    _tempSortAscending = _sortAscending;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadBaseUrl() async {
    baseImageUrl = await ImageUrlHelper.getBaseImageUrl();
    setState(() {
      items.clear();
      itemGroups.clear();
      variantGroups.clear();
      _detailedItemsCache.clear();
      isLoading = true;
    }); // Refresh UI
  }

  Future<void> _loadData() async {
    try {
      if (!mounted) return;
      setState(() => isLoading = true);

      final authState = ref.read(authProvider);
      final posProfile = authState.maybeWhen(
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
          cashDrawerPin,
        ) =>
            posProfile,
        orElse: () => null,
      );

      if (posProfile == null) {
        if (!mounted) return;
        _showErrorToast('Not authenticated or posProfile not available');
        setState(() => isLoading = false);
        return;
      }

      final responses = await Future.wait([
        PosService().getAllItems(posProfile),
        PosService().getItemGroups(),
        PosService().getVariantGroups(),
      ]);

      if (!mounted) return;

      // Load item groups and variant groups first
      if (responses[1]['success'] == true) {
        final List<dynamic> groupsData = responses[1]['message']['item_groups'];
        if (!mounted) return;
        setState(() {
          itemGroups = groupsData
              .map((group) => ItemGroup.fromJson(group))
              .where((group) => group.disabled == 0)
              .toList();
        });
      }

      if (responses[2]['success'] == true) {
        if (!mounted) return;
        setState(() {
          variantGroups = (responses[2]['message'] as List)
              .map((json) => VariantGroup.fromJson(json))
              .where((group) => group.disabled == 0)
              .toList();
        });
      }

      // Show basic items immediately
      if (responses[0]['success'] == true) {
        final List<dynamic> itemsData = responses[0]['message']['items'];

        final basicItems = itemsData
            .map((item) => Item.fromJson(item, baseUrl: baseImageUrl))
            .toList();

        if (!mounted) return;
        setState(() {
          items = basicItems;
          isLoading = false; // Show items immediately
        });

        // Load detailed information in background
        _fetchDetailedItemsInBackground(basicItems);
      } else {
        if (!mounted) return;
        setState(() => isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      _showErrorToast('Failed to load data: $e');
    }
  }

// Background loading method
  Future<void> _fetchDetailedItemsInBackground(List<Item> basicItems) async {
    const int batchSize = 10;

    for (int i = 0; i < basicItems.length; i += batchSize) {
      if (!mounted) break;

      final batch = basicItems.skip(i).take(batchSize).toList();

      final batchResults = await Future.wait(
        batch.map((basicItem) async {
          try {
            if (_detailedItemsCache.containsKey(basicItem.itemCode)) {
              return _detailedItemsCache[basicItem.itemCode]!;
            }

            final response = await PosService().getItem(basicItem.itemCode);

            if (response['success'] == true) {
              final detailedItem = Item.fromDetailedJson(
                response['message'],
                baseUrl: baseImageUrl,
              );
              _detailedItemsCache[basicItem.itemCode] = detailedItem;
              return detailedItem;
            } else {
              final nonPosItem = basicItem.copyWith(isPosItem: 0);
              _detailedItemsCache[basicItem.itemCode] = nonPosItem;
              return nonPosItem;
            }
          } catch (e) {
            final nonPosItem = basicItem.copyWith(isPosItem: 0);
            _detailedItemsCache[basicItem.itemCode] = nonPosItem;
            return nonPosItem;
          }
        }),
      );

      // Update items progressively after each batch
      if (mounted) {
        setState(() {
          for (final detailedItem in batchResults) {
            final index = items.indexWhere(
              (item) => item.itemCode == detailedItem.itemCode,
            );
            if (index != -1) {
              items[index] = detailedItem;
            }
          }
        });
      }
    }
  }

  Future<List<Item>> _fetchDetailedItems(List<Item> basicItems) async {
    final List<Item> detailedItems = [];

    for (final basicItem in basicItems) {
      try {
        if (!mounted) break; // Check if widget is still mounted

        // Check cache first
        if (_detailedItemsCache.containsKey(basicItem.itemCode)) {
          detailedItems.add(_detailedItemsCache[basicItem.itemCode]!);
          continue;
        }

        // Fetch detailed item information
        final response = await PosService().getItem(basicItem.itemCode);

        if (!mounted) break; // Check again after async operation

        if (response['success'] == true) {
          final detailedItem =
              Item.fromDetailedJson(response['message'], baseUrl: baseImageUrl);
          _detailedItemsCache[basicItem.itemCode] = detailedItem;
          detailedItems.add(detailedItem);
        } else {
          // If detailed fetch fails → mark as not POS
          detailedItems.add(
            basicItem.copyWith(isPosItem: 0),
          );
        }
      } catch (e) {
        if (!mounted) break;
        print('Error fetching detailed info for ${basicItem.itemCode}: $e');
        // Same here → mark as not POS
        detailedItems.add(
          basicItem.copyWith(isPosItem: 0),
        );

        print('Test here ${basicItem.isPosItem}');
      }
    }

    return detailedItems;
  }

  Future<void> _refreshItemDetails(Item item) async {
    try {
      // Fetch updated detailed information
      final response = await PosService().getItem(item.itemCode);

      if (!mounted) return;

      if (response['success'] == true) {
        final updatedItem =
            Item.fromDetailedJson(response['message'], baseUrl: baseImageUrl);
        _detailedItemsCache[item.itemCode] = updatedItem;

        // Update the item in the list
        if (!mounted) return;
        setState(() {
          final index = items.indexWhere((i) => i.itemCode == item.itemCode);
          if (index != -1) {
            items[index] = updatedItem;
          }
        });
      } else {
        // FIX: If item not found, mark as non-POS
        print(
            'Item ${item.itemCode} not found during refresh, marking as non-POS');
        final nonPosItem = item.copyWith(isPosItem: 0);
        _detailedItemsCache[item.itemCode] = nonPosItem;

        if (!mounted) return;
        setState(() {
          final index = items.indexWhere((i) => i.itemCode == item.itemCode);
          if (index != -1) {
            items[index] = nonPosItem;
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      print('Error refreshing item details: $e');
      // FIX: On error, also mark as non-POS
      final nonPosItem = item.copyWith(isPosItem: 0);
      _detailedItemsCache[item.itemCode] = nonPosItem;

      if (!mounted) return;
      setState(() {
        final index = items.indexWhere((i) => i.itemCode == item.itemCode);
        if (index != -1) {
          items[index] = nonPosItem;
        }
      });
    }
  }

  List<Item> get _filteredItems {
    List<Item> filtered = items.where((item) {
      // Search filter
      final matchesSearch = _searchQuery.isEmpty ||
          item.itemName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.itemCode.toLowerCase().contains(_searchQuery.toLowerCase());

      // Status filter
      final matchesStatus = _filterStatus == null ||
          (_filterStatus == 'active' && item.disabled == 0) ||
          (_filterStatus == 'inactive' && item.disabled == 1);

      // POS status filter
      final matchesPosStatus = _filterPosStatus == null ||
          (_filterPosStatus == 'pos' && item.isPosItemBool) ||
          (_filterPosStatus == 'non-pos' && !item.isPosItemBool);

      // Item group filter
      final matchesItemGroup =
          _filterItemGroup == null || item.itemGroup == _filterItemGroup;

      // Variant group filter
      final matchesVariantGroup = _filterVariantGroup == null ||
          item.variantGroups.contains(_filterVariantGroup);

      return matchesSearch &&
          matchesStatus &&
          matchesPosStatus &&
          matchesItemGroup &&
          matchesVariantGroup;
    }).toList();

    // Apply sorting
    filtered.sort((a, b) {
      int compareResult;
      switch (_sortBy) {
        case 'name':
          compareResult = a.itemName.compareTo(b.itemName);
          break;
        case 'code':
          compareResult = a.itemCode.compareTo(b.itemCode);
          break;
        case 'price':
          compareResult = a.price.compareTo(b.price);
          break;
        case 'status':
          compareResult = a.disabled.compareTo(b.disabled);
          break;
        case 'posStatus':
          compareResult = a.isPosItem.compareTo(b.isPosItem);
          break;
        case 'group':
          compareResult = a.itemGroup.compareTo(b.itemGroup);
          break;
        default:
          compareResult = a.itemName.compareTo(b.itemName);
      }

      return _sortAscending ? compareResult : -compareResult;
    });

    return filtered;
  }

  // Reset all filters
  void _resetFilters() {
    setState(() {
      _searchQuery = '';
      _sortBy = 'name';
      _sortAscending = true;
      _filterStatus = null;
      _filterPosStatus = null;
      _filterItemGroup = null;
      _filterVariantGroup = null;

      // Also reset temp variables
      _tempFilterStatus = null;
      _tempFilterPosStatus = null;
      _tempFilterItemGroup = null;
      _tempFilterVariantGroup = null;
      _tempSortBy = 'name';
      _tempSortAscending = true;
    });
  }

  void _showCreateItemDialog() {
    showDialog(
      context: context,
      builder: (context) => CreateItemDialog(
        itemGroups: itemGroups,
        variantGroups: variantGroups,
        onSave: _loadDataAfterCreate, // Use special method for new items
      ),
    );
  }

  // NEW: Reload data after creating new item (scroll to top makes sense here)
  Future<void> _loadDataAfterCreate() async {
    await _loadData();
    // Scroll to top to show the new item (user expects this)
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showEditItemDialog(Item item) {
    // Refresh item details before opening edit dialog
    _refreshItemDetails(item).then((_) {
      final updatedItem = _detailedItemsCache[item.itemCode] ?? item;

      print('Opening EditDialog for: ${updatedItem.itemCode}');
      print(
          'isPosItem value: ${updatedItem.isPosItem} (${updatedItem.isPosItemBool})');

      showDialog(
        context: context,
        builder: (context) => EditItemDialog(
          item: updatedItem,
          itemGroups: itemGroups,
          variantGroups: variantGroups,
          onSave: () => _refreshSingleItem(item.itemCode),
        ),
      );
    });
  }

  Future<void> _refreshSingleItem(String itemCode) async {
    try {
      if (!mounted) return;

      // Set flag to indicate single item update
      setState(() {
        _isSingleItemUpdate = true;
      });

      // Fetch updated item details
      final response = await PosService().getItem(itemCode);

      if (!mounted) return;

      if (response['success'] == true) {
        final updatedItem = Item.fromDetailedJson(
          response['message'],
          baseUrl: baseImageUrl,
        );

        // Update cache
        _detailedItemsCache[itemCode] = updatedItem;

        // Update only the specific item in the list
        if (!mounted) return;
        setState(() {
          final index = items.indexWhere((i) => i.itemCode == itemCode);
          if (index != -1) {
            items[index] = updatedItem;
          }
          _isSingleItemUpdate = false;
        });

        _showSuccessToast('Item updated successfully');
      } else {
        // If item not found, mark as non-POS
        final nonPosItem = items
            .firstWhere((i) => i.itemCode == itemCode)
            .copyWith(isPosItem: 0);
        _detailedItemsCache[itemCode] = nonPosItem;

        if (!mounted) return;
        setState(() {
          final index = items.indexWhere((i) => i.itemCode == itemCode);
          if (index != -1) {
            items[index] = nonPosItem;
          }
          _isSingleItemUpdate = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSingleItemUpdate = false;
      });
      //_showErrorToast('Failed to refresh item: $e');
    }
  }

  Future<void> _toggleItemStatus(Item item, bool isActive) async {
    try {
      if (!mounted) return;

      // Show loading indicator on the specific item (optional)
      setState(() {
        _isSingleItemUpdate = true;
      });

      // Refresh the item details first to get the latest data
      await _refreshItemDetails(item);
      final currentItem = _detailedItemsCache[item.itemCode] ?? item;

      await PosService().updateItem(
        itemCode: item.itemCode,
        itemName: currentItem.itemName,
        itemGroup: currentItem.itemGroup,
        variantGroupTable: currentItem.variantGroups
            .map<Map<String, Object>>((group) => {
                  'variant_group': group,
                  'active': 0,
                })
            .toList(),
        disabled: isActive ? 0 : 1,
      );

      // Instead of reloading all data, just update this specific item
      await _refreshItemDetails(item);

      // Update the item in the local list WITHOUT scrolling
      if (!mounted) return;
      setState(() {
        final index = items.indexWhere((i) => i.itemCode == item.itemCode);
        if (index != -1) {
          final updatedItem = _detailedItemsCache[item.itemCode] ??
              item.copyWith(disabled: isActive ? 0 : 1);
          items[index] = updatedItem;
        }
        _isSingleItemUpdate = false;
      });

      if (!mounted) return;
      _showSuccessToast(
          'Item ${isActive ? 'activated' : 'deactivated'} successfully');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSingleItemUpdate = false;
      });
      _showErrorToast('Failed to update status: $e');
    }
  }

  void _showErrorToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.red,
      textColor: Colors.white,
    );
  }

  void _showSuccessToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.green,
      textColor: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: NoStretchScrollBehavior(),
      child: SingleChildScrollView(
        controller: _scrollController, // ADD THIS: Attach scroll controller
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Add Record button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Items',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                ElevatedButton(
                  onPressed: _showCreateItemDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    'Add Item',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),

            // Progress indicator for background loading
            if (_isLoadingDetails) ...[
              const SizedBox(height: 12),
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.blue.shade700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Loading item details in background...',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue.shade900,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _totalItemsCount > 0
                            ? _loadedItemsCount / _totalItemsCount
                            : 0,
                        backgroundColor: Colors.blue.shade100,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.blue.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_loadedItemsCount / $_totalItemsCount items loaded',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Search and Filter Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Search Bar
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Search by name or code...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _searchQuery = '';
                                  });
                                },
                              )
                            : null,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Filters and Sorting Row
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _showFilterDialog(),
                          icon: const Icon(Icons.filter_list, size: 16),
                          label: const Text(
                            'Filters',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[200],
                            foregroundColor: Colors.black,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _showSortDialog(),
                          icon: Icon(
                            _sortAscending
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            size: 16,
                          ),
                          label: const Text(
                            'Sort',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[200],
                            foregroundColor: Colors.black,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_hasActiveFilters)
                          TextButton.icon(
                            onPressed: _resetFilters,
                            icon: const Icon(Icons.clear, size: 16),
                            label: const Text('Clear Filters'),
                          ),
                      ],
                    ),

                    // Active Filters Indicator
                    if (_hasActiveFilters) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: _activeFilterChips,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Items List
            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_filteredItems.isEmpty)
              const Center(child: Text('No items found'))
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _filteredItems.length,
                itemBuilder: (context, index) {
                  final item = _filteredItems[index];
                  return ItemCard(
                    item: item,
                    onEdit: () => _showEditItemDialog(item),
                    onStatusToggle: (value) => _toggleItemStatus(item, value),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // Check if any filters are active
  bool get _hasActiveFilters {
    return _searchQuery.isNotEmpty ||
        _filterStatus != null ||
        _filterPosStatus != null ||
        _filterItemGroup != null ||
        _filterVariantGroup != null ||
        _sortBy != 'name' ||
        !_sortAscending;
  }

  // Get active filter chips
  List<Widget> get _activeFilterChips {
    final chips = <Widget>[];

    if (_searchQuery.isNotEmpty) {
      chips.add(Chip(
        label: Text('Search: "$_searchQuery"'),
        onDeleted: () {
          setState(() {
            _searchQuery = '';
          });
        },
      ));
    }

    if (_filterStatus != null) {
      chips.add(Chip(
        label: Text(
            'Status: ${_filterStatus == 'active' ? 'Active' : 'Inactive'}'),
        onDeleted: () {
          setState(() {
            _filterStatus = null;
          });
        },
      ));
    }

    if (_filterPosStatus != null) {
      chips.add(Chip(
        label: Text(
            'POS: ${_filterPosStatus == 'pos' ? 'POS Item' : 'Non-POS Item'}'),
        onDeleted: () {
          setState(() {
            _filterPosStatus = null;
          });
        },
      ));
    }

    if (_filterItemGroup != null) {
      chips.add(Chip(
        label: Text('Group: $_filterItemGroup'),
        onDeleted: () {
          setState(() {
            _filterItemGroup = null;
          });
        },
      ));
    }

    if (_filterVariantGroup != null) {
      chips.add(Chip(
        label: Text('Variant: $_filterVariantGroup'),
        onDeleted: () {
          setState(() {
            _filterVariantGroup = null;
          });
        },
      ));
    }

    if (_sortBy != 'name' || !_sortAscending) {
      String sortText = '';
      switch (_sortBy) {
        case 'name':
          sortText = 'Name ${_sortAscending ? 'A-Z' : 'Z-A'}';
          break;
        case 'code':
          sortText = 'Code ${_sortAscending ? 'A-Z' : 'Z-A'}';
          break;
        case 'price':
          sortText = 'Price ${_sortAscending ? 'Low-High' : 'High-Low'}';
          break;
        case 'status':
          sortText =
              'Status ${_sortAscending ? 'Active First' : 'Inactive First'}';
          break;
        case 'posStatus':
          sortText = 'POS ${_sortAscending ? 'POS First' : 'Non-POS First'}';
          break;
        case 'group':
          sortText = 'Group ${_sortAscending ? 'A-Z' : 'Z-A'}';
          break;
      }

      chips.add(Chip(
        label: Text('Sort: $sortText'),
        onDeleted: () {
          setState(() {
            _sortBy = 'name';
            _sortAscending = true;
          });
        },
      ));
    }

    return chips;
  }

  // Show filter dialog
  void _showFilterDialog() {
    // Initialize temp variables with current values
    _tempFilterStatus = _filterStatus;
    _tempFilterPosStatus = _filterPosStatus;
    _tempFilterItemGroup = _filterItemGroup;
    _tempFilterVariantGroup = _filterVariantGroup;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text(
                'Filter Items',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.white,
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status filter
                    const Text('Status:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Radio<String>(
                          value: 'active',
                          groupValue: _tempFilterStatus,
                          onChanged: (value) {
                            setStateDialog(() {
                              _tempFilterStatus = value;
                            });
                          },
                        ),
                        const Text('Active'),
                        Radio<String>(
                          value: 'inactive',
                          groupValue: _tempFilterStatus,
                          onChanged: (value) {
                            setStateDialog(() {
                              _tempFilterStatus = value;
                            });
                          },
                        ),
                        const Text('Inactive'),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // POS Status filter
                    const Text('POS Status:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Radio<String>(
                          value: 'pos',
                          groupValue: _tempFilterPosStatus,
                          onChanged: (value) {
                            setStateDialog(() {
                              _tempFilterPosStatus = value;
                            });
                          },
                        ),
                        const Text('POS Items'),
                        Radio<String>(
                          value: 'non-pos',
                          groupValue: _tempFilterPosStatus,
                          onChanged: (value) {
                            setStateDialog(() {
                              _tempFilterPosStatus = value;
                            });
                          },
                        ),
                        const Text('Non-POS Items'),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Item Group filter
                    const Text('Item Group:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    DropdownButton<String>(
                      value: _tempFilterItemGroup,
                      isExpanded: true,
                      hint: const Text('All Groups'),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('All Groups')),
                        ...itemGroups.map((group) {
                          return DropdownMenuItem(
                            value: group.name,
                            child: Text(group.name),
                          );
                        }).toList(),
                      ],
                      onChanged: (value) {
                        setStateDialog(() {
                          _tempFilterItemGroup = value;
                        });
                      },
                    ),

                    const SizedBox(height: 16),

                    // Variant Group filter
                    const Text('Variant Group:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    DropdownButton<String>(
                      value: _tempFilterVariantGroup,
                      isExpanded: true,
                      hint: const Text('All Variant Groups'),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('All Variant Groups')),
                        ...variantGroups.map((group) {
                          return DropdownMenuItem(
                            value: group.variantGroup,
                            child: Text(group.variantGroup),
                          );
                        }).toList(),
                      ],
                      onChanged: (value) {
                        setStateDialog(() {
                          _tempFilterVariantGroup = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Apply the filters from temp variables
                    setState(() {
                      _filterStatus = _tempFilterStatus;
                      _filterPosStatus = _tempFilterPosStatus;
                      _filterItemGroup = _tempFilterItemGroup;
                      _filterVariantGroup = _tempFilterVariantGroup;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text(
                    'Apply Filters',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Show sort dialog
  void _showSortDialog() {
    // Initialize temp variables with current values
    _tempSortBy = _sortBy;
    _tempSortAscending = _sortAscending;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text(
                'Sort Items',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.white,
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sort by options
                    const Text('Sort by:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Column(
                      children: [
                        RadioListTile<String>(
                          title: const Text('Name'),
                          value: 'name',
                          groupValue: _tempSortBy,
                          onChanged: (value) {
                            setStateDialog(() {
                              _tempSortBy = value;
                            });
                          },
                        ),
                        RadioListTile<String>(
                          title: const Text('Code'),
                          value: 'code',
                          groupValue: _tempSortBy,
                          onChanged: (value) {
                            setStateDialog(() {
                              _tempSortBy = value;
                            });
                          },
                        ),
                        RadioListTile<String>(
                          title: const Text('Price'),
                          value: 'price',
                          groupValue: _tempSortBy,
                          onChanged: (value) {
                            setStateDialog(() {
                              _tempSortBy = value;
                            });
                          },
                        ),
                        RadioListTile<String>(
                          title: const Text('Status'),
                          value: 'status',
                          groupValue: _tempSortBy,
                          onChanged: (value) {
                            setStateDialog(() {
                              _tempSortBy = value;
                            });
                          },
                        ),
                        RadioListTile<String>(
                          title: const Text('POS Status'),
                          value: 'posStatus',
                          groupValue: _tempSortBy,
                          onChanged: (value) {
                            setStateDialog(() {
                              _tempSortBy = value;
                            });
                          },
                        ),
                        RadioListTile<String>(
                          title: const Text('Item Group'),
                          value: 'group',
                          groupValue: _tempSortBy,
                          onChanged: (value) {
                            setStateDialog(() {
                              _tempSortBy = value;
                            });
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Sort order
                    const Text('Order:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Radio<bool>(
                          value: true,
                          groupValue: _tempSortAscending,
                          onChanged: (value) {
                            setStateDialog(() {
                              _tempSortAscending = value;
                            });
                          },
                        ),
                        const Text('Ascending'),
                        Radio<bool>(
                          value: false,
                          groupValue: _tempSortAscending,
                          onChanged: (value) {
                            setStateDialog(() {
                              _tempSortAscending = value;
                            });
                          },
                        ),
                        const Text('Descending'),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Apply the sort options from temp variables
                    setState(() {
                      _sortBy = _tempSortBy!;
                      _sortAscending = _tempSortAscending!;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text(
                    'Apply Sort',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class ItemCard extends StatefulWidget {
  final Item item;
  final VoidCallback onEdit;
  final Function(bool) onStatusToggle;

  const ItemCard({
    super.key,
    required this.item,
    required this.onEdit,
    required this.onStatusToggle,
  });

  @override
  State<ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<ItemCard> {
  bool isExpanded = false;
  bool get isActive => widget.item.disabled == 0;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    //isActive = widget.item.disabled == 0;
  }

  Future<void> _toggleActiveStatus(bool value) async {
    if (!mounted) return;

    setState(() => isLoading = true);
    try {
      await widget.onStatusToggle(value);
      // No need to set local state here since parent will refresh the data
      Fluttertoast.showToast(
        msg: '${widget.item.itemName} ${value ? 'activated' : 'deactivated'}',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: value ? Colors.green : Colors.orange,
        textColor: Colors.white,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Failed to update status: $e',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      // If there's an error, we might want to revert the UI state
      // But since the parent will refresh, we don't need to do anything
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ListTile(
            leading: widget.item.imageUrl != null
                ? Image.network(
                    widget.item.imageUrl!,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.fastfood,
                        size: 50,
                      );
                    },
                  )
                : const Icon(
                    Icons.fastfood,
                    size: 50,
                  ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    widget.item.itemName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isActive ? Colors.black : Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color:
                        isActive ? Colors.green.shade100 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isActive ? 'Active' : 'Inactive',
                    style: TextStyle(
                      fontSize: 12,
                      color: isActive ? Colors.green : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Text('Group: ${widget.item.itemGroup}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: isActive,
                  onChanged: (value) => _toggleActiveStatus(value),
                  activeColor: Colors.green,
                  inactiveThumbColor: Colors.grey,
                ),
              ],
            ),
            onTap: () {
              setState(() {
                isExpanded = !isExpanded;
              });
            },
          ),
          if (isExpanded)
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Item Details:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: widget.onEdit,
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text(
                              'Edit',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDetailRow('Name:', widget.item.itemName),
                        const SizedBox(height: 8),
                        _buildDetailRow('Code:', widget.item.itemCode),
                        const SizedBox(height: 8),
                        _buildDetailRow('Group:', widget.item.itemGroup),
                        const SizedBox(height: 8),
                        _buildDetailRow('Price:',
                            'RM ${widget.item.price.toStringAsFixed(2)}'),
                        const SizedBox(height: 8),
                        _buildDetailRow(
                            'Status:', isActive ? 'Active' : 'Inactive'),
                        if (widget.item.variantGroups.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buildDetailRow('Variants:',
                              widget.item.variantGroups.join(', ')),
                        ],
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

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

// Dialog for creating new item
class CreateItemDialog extends StatefulWidget {
  final List<ItemGroup> itemGroups;
  final List<VariantGroup> variantGroups;
  final VoidCallback onSave;

  const CreateItemDialog({
    super.key,
    required this.itemGroups,
    required this.variantGroups,
    required this.onSave,
  });

  @override
  State<CreateItemDialog> createState() => _CreateItemDialogState();
}

class _CreateItemDialogState extends State<CreateItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _imageUrlController = TextEditingController();
  String? _selectedItemGroup; // Changed to single selection
  List<Map<String, Object>> _selectedVariantGroups = []; // Fixed type
  bool _isPosItem = true;
  bool _isLoading = false;
  bool _itemGroupExpanded = false;
  bool _variantGroupExpanded = false;

  Future<void> _saveItem() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedItemGroup == null) {
      Fluttertoast.showToast(
        msg: 'Please select an item group',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await PosService().createItem(
        itemCode: _codeController.text.trim(),
        itemName: _nameController.text.trim(),
        itemGroup: _selectedItemGroup!,
        variantGroupTable: _selectedVariantGroups,
        description: _descriptionController.text.trim(),
        isPosItem: _isPosItem ? 1 : 0,
      );

      if (response['success'] == true) {
        widget.onSave();
        Navigator.pop(context);
        Fluttertoast.showToast(
          msg: 'Item created successfully',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      } else {
        throw Exception('Failed to create item');
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Error: $e',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text(
        'Create New Item',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 600,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image and basic info row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image URL input
                    Container(
                      width: 120,
                      height: 180,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.image, size: 40, color: Colors.grey),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Item details column
                    Expanded(
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _codeController,
                            decoration: const InputDecoration(
                              labelText: 'Item Code *',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) => value?.isEmpty ?? true
                                ? 'Please enter an item code'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Item Name *',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) => value?.isEmpty ?? true
                                ? 'Please enter an item name'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _descriptionController,
                            decoration: const InputDecoration(
                              labelText: 'Description',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Item Group selection - Single selection
                const Text(
                  'Item Group *',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    children: [
                      // Header with selected item and dropdown arrow
                      InkWell(
                        onTap: () => setState(
                            () => _itemGroupExpanded = !_itemGroupExpanded),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: _selectedItemGroup == null
                                    ? const Text(
                                        'Select Item Group',
                                        style: TextStyle(color: Colors.grey),
                                      )
                                    : Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade100,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: Colors.blue.shade300),
                                        ),
                                        child: Text(
                                          _selectedItemGroup!,
                                          style: TextStyle(
                                            color: Colors.blue.shade700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                              ),
                              Icon(
                                _itemGroupExpanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Expandable content
                      if (_itemGroupExpanded)
                        Container(
                          decoration: BoxDecoration(
                            border: Border(
                                top: BorderSide(color: Colors.grey.shade300)),
                          ),
                          child: Column(
                            children: [
                              for (final group in widget.itemGroups)
                                RadioListTile<String>(
                                  title: Text(group.name),
                                  value: group.name,
                                  groupValue: _selectedItemGroup,
                                  onChanged: (String? value) {
                                    setState(() {
                                      _selectedItemGroup = value;
                                    });
                                  },
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Variant Groups selection - Multiple selection
                const Text(
                  'Variant Groups',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    children: [
                      // Header with selected items and dropdown arrow
                      InkWell(
                        onTap: () => setState(() =>
                            _variantGroupExpanded = !_variantGroupExpanded),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: _selectedVariantGroups.isEmpty
                                    ? const Text(
                                        'Select Variant Groups',
                                        style: TextStyle(color: Colors.grey),
                                      )
                                    : Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: _selectedVariantGroups
                                            .map(
                                              (vg) => Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.shade100,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                      color: Colors
                                                          .green.shade300),
                                                ),
                                                child: Text(
                                                  vg['variant_group'] as String,
                                                  style: TextStyle(
                                                    color:
                                                        Colors.green.shade700,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                              ),
                              Icon(
                                _variantGroupExpanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Expandable content
                      if (_variantGroupExpanded)
                        Container(
                          decoration: BoxDecoration(
                            border: Border(
                                top: BorderSide(color: Colors.grey.shade300)),
                          ),
                          child: Column(
                            children: [
                              for (final group in widget.variantGroups)
                                CheckboxListTile(
                                  title: Text(group.variantGroup),
                                  subtitle:
                                      Text('${group.options.length} options'),
                                  value: _selectedVariantGroups.any((vg) =>
                                      vg['variant_group'] ==
                                      group.variantGroup),
                                  onChanged: (bool? value) {
                                    setState(() {
                                      if (value == true) {
                                        _selectedVariantGroups.add({
                                          'variant_group': group.variantGroup,
                                          'active': 0
                                        });
                                      } else {
                                        _selectedVariantGroups.removeWhere(
                                            (vg) =>
                                                vg['variant_group'] ==
                                                group.variantGroup);
                                      }
                                    });
                                  },
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // POS Item toggle
                Row(
                  children: [
                    const Text('Is POS Item?'),
                    const SizedBox(width: 16),
                    Switch(
                      value: _isPosItem,
                      onChanged: (value) => setState(() => _isPosItem = value),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveItem,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(
                  'Save',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }
}

// Dialog for editing item - Updated to match CreateItemDialog style
class EditItemDialog extends StatefulWidget {
  final Item item;
  final List<ItemGroup> itemGroups;
  final List<VariantGroup> variantGroups;
  final VoidCallback onSave;

  const EditItemDialog({
    super.key,
    required this.item,
    required this.itemGroups,
    required this.variantGroups,
    required this.onSave,
  });

  @override
  State<EditItemDialog> createState() => _EditItemDialogState();
}

class _EditItemDialogState extends State<EditItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _codeController;
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _imageUrlController;
  String? _selectedItemGroup; // Changed to single selection
  List<Map<String, Object>> _selectedVariantGroups = []; // Fixed type
  late bool _isPosItem; // Keep as bool for Switch widget
  bool _isLoading = false;
  bool _itemGroupExpanded = false;
  bool _variantGroupExpanded = false;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.item.itemCode);
    _nameController = TextEditingController(text: widget.item.itemName);
    _descriptionController = TextEditingController(
      text: widget.item.description ?? '',
    );
    _imageUrlController =
        TextEditingController(text: widget.item.imageUrl ?? '');
    _selectedItemGroup = widget.item.itemGroup;

    // Initialize variant groups from detailed response
    _selectedVariantGroups = widget.item.variantGroups
        .map<Map<String, Object>>((group) => {
              'variant_group': group,
              'active': 0,
            })
        .toList();

    // FIX: Use the actual custom_is_pos_item value from detailed API
    _isPosItem = widget.item.isPosItem == 1; // Convert int to bool

    print('EditItemDialog - Item: ${widget.item.itemCode}');
    print('EditItemDialog - isPosItem (int): ${widget.item.isPosItem}');
    print('EditItemDialog - isPosItem (bool): $_isPosItem');
    print('EditItemDialog - Variant groups: ${widget.item.variantGroups}');
  }

  Future<void> _updateItem() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedItemGroup == null) {
      Fluttertoast.showToast(
        msg: 'Please select an item group',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await PosService().updateItem(
        itemCode: widget.item.itemCode,
        itemName: _nameController.text.trim(),
        itemGroup: _selectedItemGroup!,
        variantGroupTable: _selectedVariantGroups,
        description: _descriptionController.text.trim(),
        isPosItem: _isPosItem ? 1 : 0,
      );

      if (response['success'] == true) {
        widget.onSave();
        Navigator.pop(context);
        Fluttertoast.showToast(
          msg: 'Item updated successfully',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      } else {
        throw Exception('Failed to update item');
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Error: $e',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text(
        'Edit Item',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 600,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image and basic info row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image preview section
                    Column(
                      children: [
                        if (widget.item.imageUrl != null ||
                            _imageUrlController.text.isNotEmpty)
                          Image.network(
                            _imageUrlController.text.isNotEmpty
                                ? _imageUrlController.text
                                : widget.item.imageUrl!,
                            height: 120,
                            width: 120,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 120,
                                height: 120,
                                color: Colors.grey[200],
                                child: const Icon(Icons.image),
                              );
                            },
                          )
                        else
                          Container(
                            width: 120,
                            height: 120,
                            color: Colors.grey[200],
                            child: const Icon(Icons.image),
                          ),
                        const SizedBox(height: 8),
                      ],
                    ),
                    const SizedBox(width: 16),
                    // Item details column
                    Expanded(
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _codeController,
                            decoration: const InputDecoration(
                              labelText: 'Item Code *',
                              border: OutlineInputBorder(),
                            ),
                            enabled: false, // Disable editing for item code
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Item Name *',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) => value?.isEmpty ?? true
                                ? 'Please enter an item name'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _descriptionController,
                            decoration: const InputDecoration(
                              labelText: 'Description',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Item Group selection - Single selection
                const Text(
                  'Item Group *',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    children: [
                      // Header with selected item and dropdown arrow
                      InkWell(
                        onTap: () => setState(
                            () => _itemGroupExpanded = !_itemGroupExpanded),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: _selectedItemGroup == null
                                    ? const Text(
                                        'Select Item Group',
                                        style: TextStyle(color: Colors.grey),
                                      )
                                    : Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade100,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: Colors.blue.shade300),
                                        ),
                                        child: Text(
                                          _selectedItemGroup!,
                                          style: TextStyle(
                                            color: Colors.blue.shade700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                              ),
                              Icon(
                                _itemGroupExpanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Expandable content
                      if (_itemGroupExpanded)
                        Container(
                          decoration: BoxDecoration(
                            border: Border(
                                top: BorderSide(color: Colors.grey.shade300)),
                          ),
                          child: Column(
                            children: [
                              for (final group in widget.itemGroups)
                                RadioListTile<String>(
                                  title: Text(group.name),
                                  value: group.name,
                                  groupValue: _selectedItemGroup,
                                  onChanged: (String? value) {
                                    setState(() {
                                      _selectedItemGroup = value;
                                    });
                                  },
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Variant Groups selection - Multiple selection
                const Text(
                  'Variant Groups',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    children: [
                      // Header with selected items and dropdown arrow
                      InkWell(
                        onTap: () => setState(() =>
                            _variantGroupExpanded = !_variantGroupExpanded),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: _selectedVariantGroups.isEmpty
                                    ? const Text(
                                        'Select Variant Groups',
                                        style: TextStyle(color: Colors.grey),
                                      )
                                    : Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: _selectedVariantGroups
                                            .map(
                                              (vg) => Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.shade100,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                      color: Colors
                                                          .green.shade300),
                                                ),
                                                child: Text(
                                                  vg['variant_group'] as String,
                                                  style: TextStyle(
                                                    color:
                                                        Colors.green.shade700,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                              ),
                              Icon(
                                _variantGroupExpanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Expandable content
                      if (_variantGroupExpanded)
                        Container(
                          decoration: BoxDecoration(
                            border: Border(
                                top: BorderSide(color: Colors.grey.shade300)),
                          ),
                          child: Column(
                            children: [
                              for (final group in widget.variantGroups)
                                CheckboxListTile(
                                  title: Text(group.variantGroup),
                                  subtitle:
                                      Text('${group.options.length} options'),
                                  value: _selectedVariantGroups.any((vg) =>
                                      vg['variant_group'] ==
                                      group.variantGroup),
                                  onChanged: (bool? value) {
                                    setState(() {
                                      if (value == true) {
                                        _selectedVariantGroups.add({
                                          'variant_group': group.variantGroup,
                                          'active': 0
                                        });
                                      } else {
                                        _selectedVariantGroups.removeWhere(
                                            (vg) =>
                                                vg['variant_group'] ==
                                                group.variantGroup);
                                      }
                                    });
                                  },
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // POS Item toggle
                Row(
                  children: [
                    const Text('Is POS Item?'),
                    const SizedBox(width: 16),
                    Switch(
                      value: _isPosItem,
                      onChanged: (value) => setState(() => _isPosItem = value),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _updateItem,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(
                  'Update',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }
}

// Item model
class Item {
  final String itemCode;
  final String itemName;
  final String itemGroup;
  final double price;
  final String? imageUrl;
  final String? description;
  final List<String> variantGroups;
  final int disabled;
  final int isPosItem;

  Item({
    required this.itemCode,
    required this.itemName,
    required this.itemGroup,
    required this.price,
    this.imageUrl,
    this.description,
    this.variantGroups = const [],
    this.disabled = 0,
    required this.isPosItem,
  });

  Item copyWith({
    String? itemCode,
    String? itemName,
    String? itemGroup,
    double? price,
    String? imageUrl,
    String? description,
    List<String>? variantGroups,
    int? disabled,
    int? isPosItem,
  }) {
    return Item(
      itemCode: itemCode ?? this.itemCode,
      itemName: itemName ?? this.itemName,
      itemGroup: itemGroup ?? this.itemGroup,
      price: price ?? this.price,
      imageUrl: imageUrl ?? this.imageUrl,
      description: description ?? this.description,
      variantGroups: variantGroups ?? this.variantGroups,
      disabled: disabled ?? this.disabled,
      isPosItem: isPosItem ?? this.isPosItem,
    );
  }

  // Factory method for basic item list response
  factory Item.fromJson(Map<String, dynamic> json, {required String baseUrl}) {
    return Item(
      itemCode: json['item_code'] ?? '',
      itemName: json['item_name'] ?? '',
      itemGroup: json['item_group'] ?? '',
      price: (json['price_list_rate'] as num?)?.toDouble() ?? 0.0,
      imageUrl: json['image'] != null ? '$baseUrl${json['image']}' : null,
      description: json['description'] as String?,
      variantGroups: (json['structured_variant_info'] as List<dynamic>?)
              ?.map((e) => e['variant_group'].toString())
              .toList() ??
          [],
      disabled: json['disabled'] as int? ?? 0,
      // For basic list, we might not have custom_is_pos_item, so default to 1
      isPosItem: 0, // Default value until we fetch detailed info
    );
  }

  // Factory method for detailed item response
  factory Item.fromDetailedJson(Map<String, dynamic> json,
      {required String baseUrl}) {
    return Item(
      itemCode: json['item_code'] ?? '',
      itemName: json['item_name'] ?? '',
      itemGroup: json['item_group'] ?? '',
      price: (json['standard_rate'] as num?)?.toDouble() ?? 0.0,
      imageUrl: json['image'] != null ? '$baseUrl${json['image']}' : null,
      description: json['description'] as String?,
      variantGroups: (json['custom_variant_group_table'] as List<dynamic>?)
              ?.map((e) => e['variant_group'].toString())
              .toList() ??
          [],
      disabled: json['disabled'] as int? ?? 0,
      // FIX: Use the actual custom_is_pos_item from detailed API
      isPosItem: json['custom_is_pos_item'] as int? ?? 0,
    );
  }

  // Helper getter for UI convenience
  bool get isPosItemBool => isPosItem == 1;
}
