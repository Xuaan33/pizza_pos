import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/screens/Settings%20Screen/stock_item_card.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';

class StockManagementSection extends ConsumerStatefulWidget {
  const StockManagementSection({Key? key}) : super(key: key);

  @override
  ConsumerState<StockManagementSection> createState() =>
      _StockManagementSectionState();
}

class _StockManagementSectionState
    extends ConsumerState<StockManagementSection> {
  List<Map<String, dynamic>> _stockItems = [];
  List<Map<String, dynamic>> _filteredStockItems = [];
  bool _isStockLoading = false;
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _stockScrollController = ScrollController();

  // NEW: Map to track individual item controllers
  final Map<String, GlobalKey<_StockItemWrapperState>> _itemKeys = {};

  @override
  void initState() {
    super.initState();
    print('StockManagementSection initState called');
    _loadStockItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _stockScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadStockItems() async {
    try {
      if (mounted) {
        setState(() => _isStockLoading = true);
      }

      final authState = ref.read(authProvider);

      await authState.when(
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
          final response = await PosService().getStockBalanceSummary(
            posProfile: posProfile,
            isPosItem: 1,
            date: DateFormat('yyyy-MM-dd').format(_selectedDate),
          );

          if (response['success'] == true) {
            final items =
                List<Map<String, dynamic>>.from(response['message'] ?? []);

            final mappedItems = items.map((item) {
              String imageUrl = '';
              if (item['image'] != null &&
                  item['image'].toString().isNotEmpty) {
                final rawImage = item['image'].toString();

                if (rawImage.startsWith('http')) {
                  imageUrl = rawImage;
                } else if (rawImage.startsWith('/')) {
                  imageUrl = '$baseUrl$rawImage';
                } else {
                  imageUrl = '$baseUrl/$rawImage';
                }
              }

              return {
                'item_code': item['item_code'] ?? '',
                'item_name': item['item_name'] ?? '',
                'actual_qty': (item['qty'] ?? 0).toDouble(),
                'reserved_qty': 0.0,
                'available_qty': (item['qty'] ?? 0).toDouble(),
                'value': (item['value'] ?? 0).toDouble(),
                'image': imageUrl,
              };
            }).toList();

            if (mounted) {
              // Create keys for each item
              _itemKeys.clear();
              for (final item in mappedItems) {
                _itemKeys[item['item_code']] =
                    GlobalKey<_StockItemWrapperState>();
              }

              setState(() {
                _stockItems = mappedItems;
                _filteredStockItems = mappedItems;
              });
            }
          } else {
            throw Exception(
                response['message'] ?? 'Failed to load stock items');
          }
        },
        initial: () => throw Exception('Not authenticated'),
        unauthenticated: () => throw Exception('Not authenticated'),
      );
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Error loading stock items: ${e.toString()}',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
        setState(() {
          _stockItems = [];
          _filteredStockItems = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isStockLoading = false);
      }
    }
  }

  // NEW: Update single item using its individual key
  Future<void> _refreshSingleStockItem(String itemCode) async {
    try {
      final authState = ref.read(authProvider);

      await authState.when(
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
          final response = await PosService().getStockQuantity(
            posProfile: posProfile,
            itemCode: itemCode,
            date: DateFormat('yyyy-MM-dd').format(_selectedDate),
          );

          if (response['success'] == true) {
            final updatedQty = (response['message']['qty'] ?? 0).toDouble();

            // Update the specific item wrapper using its key
            _itemKeys[itemCode]?.currentState?.updateQuantity(updatedQty);

            // Also update the underlying data (but DON'T call setState here!)
            final mainIndex = _stockItems.indexWhere(
              (item) => item['item_code'] == itemCode,
            );
            if (mainIndex != -1) {
              _stockItems[mainIndex]['actual_qty'] = updatedQty;
              _stockItems[mainIndex]['available_qty'] = updatedQty;
            }

            final filteredIndex = _filteredStockItems.indexWhere(
              (item) => item['item_code'] == itemCode,
            );
            if (filteredIndex != -1) {
              _filteredStockItems[filteredIndex]['actual_qty'] = updatedQty;
              _filteredStockItems[filteredIndex]['available_qty'] = updatedQty;
            }
          }
        },
        initial: () => throw Exception('Not authenticated'),
        unauthenticated: () => throw Exception('Not authenticated'),
      );
    } catch (e) {
      print('Error refreshing single stock item: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Finished Goods',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        _buildControls(),
        const SizedBox(height: 20),
        Expanded(
          child: _isStockLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredStockItems.isEmpty
                  ? const Center(child: Text('No stock items found'))
                  : _buildStockList(),
        ),
      ],
    );
  }

  Widget _buildControls() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search Items',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _filterStockItems('');
                      },
                    )
                  : null,
            ),
            onChanged: (value) {
              _filterStockItems(value);
            },
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton(
          onPressed: () async {
            final DateTime? picked = await showDatePicker(
              context: context,
              initialDate: _selectedDate,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null && picked != _selectedDate) {
              setState(() {
                _selectedDate = picked;
              });
              _loadStockItems();
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.black,
          ),
          child: Text(
            DateFormat('yyyy-MM-dd').format(_selectedDate),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton(
          onPressed: _isStockLoading ? null : _loadStockItems,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          child: const Text(
            'Refresh',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildStockList() {
    return ListView.builder(
      controller: _stockScrollController,
      itemCount: _filteredStockItems.length,
      itemBuilder: (context, index) {
        final item = _filteredStockItems[index];
        final itemCode = item['item_code'];

        // Ensure key exists
        if (!_itemKeys.containsKey(itemCode)) {
          _itemKeys[itemCode] = GlobalKey<_StockItemWrapperState>();
        }

        return StockItemWrapper(
          key: _itemKeys[itemCode],
          item: item,
          onManageStock: () => _showManageStockDialog(item),
        );
      },
    );
  }

  void _showManageStockDialog(Map<String, dynamic> item) {
    final qtyController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Manage Stock',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item['item_name'] ?? 'Unknown Item',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              'Current Quantity: ${(item['actual_qty'] ?? 0).toStringAsFixed(0)}',
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: qtyController,
              decoration: const InputDecoration(
                labelText: 'Quantity to Add/Remove',
                border: OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final quantity = double.tryParse(qtyController.text);
              if (quantity == null || quantity <= 0) {
                Fluttertoast.showToast(
                  msg: 'Please enter a valid quantity greater than 0',
                  gravity: ToastGravity.BOTTOM,
                  backgroundColor: Colors.orange,
                  textColor: Colors.white,
                );
                return;
              }

              if (_wouldResultInNegativeStock(item, quantity)) {
                Fluttertoast.showToast(
                  msg: 'Cannot reduce more than current quantity',
                  gravity: ToastGravity.BOTTOM,
                  backgroundColor: Colors.red,
                  textColor: Colors.white,
                );
                return;
              }

              Navigator.pop(context);
              _reduceStock(item, quantity);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text(
              'Reduce Stock',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final quantity = double.tryParse(qtyController.text);
              if (quantity == null || quantity <= 0) {
                Fluttertoast.showToast(
                  msg: 'Please enter a valid quantity greater than 0',
                  gravity: ToastGravity.BOTTOM,
                  backgroundColor: Colors.orange,
                  textColor: Colors.white,
                );
                return;
              }

              Navigator.pop(context);
              _stockInItems(item, quantity);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text(
              'Add Stock',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _stockInItems(
    Map<String, dynamic> item,
    double quantityToAdd,
  ) async {
    try {
      final authState = ref.read(authProvider);

      await authState.when(
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
          final itemsToStockIn = [
            {
              'item_code': item['item_code'],
              'qty': quantityToAdd,
            }
          ];

          final response = await PosService().stockInItems(
            posProfile: posProfile,
            items: itemsToStockIn,
          );

          if (response['success'] == true) {
            Fluttertoast.showToast(
              msg: 'Stock added successfully',
              gravity: ToastGravity.BOTTOM,
              backgroundColor: Colors.green,
              textColor: Colors.white,
            );

            // Refresh ONLY this item - no setState on parent!
            await _refreshSingleStockItem(item['item_code']);
          } else {
            throw Exception(response['message'] ?? 'Failed to add stock');
          }
        },
        initial: () => throw Exception('Not authenticated'),
        unauthenticated: () => throw Exception('Not authenticated'),
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Error adding stock: ${e.toString()}',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  Future<void> _reduceStock(
    Map<String, dynamic> item,
    double quantityToRemove,
  ) async {
    try {
      final authState = ref.read(authProvider);

      await authState.when(
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
          final currentQty = (item['actual_qty'] ?? 0).toDouble();
          final newQty = currentQty - quantityToRemove;
          final adjustedQty = newQty >= 0 ? newQty : 0;

          final itemsToAdjust = [
            {
              'item_code': item['item_code'],
              'actual_qty': adjustedQty,
            }
          ];

          final response = await PosService().adjustStock(
            posProfile: posProfile,
            items: itemsToAdjust,
          );

          if (response['success'] == true) {
            Fluttertoast.showToast(
              msg: 'Stock reduced successfully',
              gravity: ToastGravity.BOTTOM,
              backgroundColor: Colors.green,
              textColor: Colors.white,
            );

            // Refresh ONLY this item - no setState on parent!
            await _refreshSingleStockItem(item['item_code']);
          } else {
            throw Exception(response['message'] ?? 'Failed to reduce stock');
          }
        },
        initial: () => throw Exception('Not authenticated'),
        unauthenticated: () => throw Exception('Not authenticated'),
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Error reducing stock: ${e.toString()}',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  bool _wouldResultInNegativeStock(
    Map<String, dynamic> item,
    double quantityToRemove,
  ) {
    final currentQty = (item['actual_qty'] ?? 0).toDouble();
    return (currentQty - quantityToRemove) < 0;
  }

  void _filterStockItems(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredStockItems = _stockItems;
      });
      return;
    }

    final filtered = _stockItems.where((item) {
      final itemCode = item['item_code']?.toString().toLowerCase() ?? '';
      final itemName = item['item_name']?.toString().toLowerCase() ?? '';
      final searchLower = query.toLowerCase();

      return itemCode.contains(searchLower) || itemName.contains(searchLower);
    }).toList();

    setState(() {
      _filteredStockItems = filtered;
    });
  }
}

// NEW: Wrapper widget that manages its own state independently
class StockItemWrapper extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onManageStock;

  const StockItemWrapper({
    Key? key,
    required this.item,
    required this.onManageStock,
  }) : super(key: key);

  @override
  State<StockItemWrapper> createState() => _StockItemWrapperState();
}

class _StockItemWrapperState extends State<StockItemWrapper> {
  late double _currentQty;
  late double _availableQty;

  @override
  void initState() {
    super.initState();
    _currentQty = (widget.item['actual_qty'] ?? 0).toDouble();
    _availableQty = (widget.item['available_qty'] ?? 0).toDouble();
  }

  // Method to update quantity without rebuilding parent
  void updateQuantity(double newQty) {
    if (mounted) {
      setState(() {
        _currentQty = newQty;
        _availableQty = newQty;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StockItemCard(
      itemCode: widget.item['item_code'] ?? '',
      itemName: widget.item['item_name'] ?? '',
      currentQty: _currentQty,
      reservedQty: (widget.item['reserved_qty'] ?? 0).toDouble(),
      availableQty: _availableQty,
      value: (widget.item['value'] ?? 0).toDouble(),
      image: widget.item['image'],
      onManageStock: widget.onManageStock,
    );
  }
}
