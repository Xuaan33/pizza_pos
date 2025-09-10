import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shiok_pos_android_app/components/item_group.dart';
import 'package:shiok_pos_android_app/components/variant_group.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';

class ItemManagement extends StatefulWidget {
  const ItemManagement({super.key});

  @override
  State<ItemManagement> createState() => _ItemManagementState();
}

class _ItemManagementState extends State<ItemManagement> {
  List<Item> items = [];
  List<ItemGroup> itemGroups = [];
  List<VariantGroup> variantGroups = [];
  bool isLoading = true;
  Map<String, Item> _detailedItemsCache = {}; // Cache for detailed items

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() => isLoading = true);

      // Load all necessary data in parallel
      final responses = await Future.wait([
        PosService().getAllItems(),
        PosService().getItemGroups(),
        PosService().getVariantGroups(),
      ]);

      if (responses[0]['success'] == true) {
        final List<dynamic> itemsData = responses[0]['message']['items'];

        // First create basic items
        final basicItems =
            itemsData.map((item) => Item.fromJson(item)).toList();

        // Then fetch detailed information for each item
        final detailedItems = await _fetchDetailedItems(basicItems);

        setState(() {
          items = detailedItems;
        });
      }

      if (responses[1]['success'] == true) {
        final List<dynamic> groupsData = responses[1]['message']['item_groups'];
        setState(() {
          itemGroups = groupsData
              .map((group) => ItemGroup.fromJson(group))
              .where((group) => group.disabled == 0)
              .toList();
        });
      }

      if (responses[2]['success'] == true) {
        setState(() {
          variantGroups = (responses[2]['message'] as List)
              .map((json) => VariantGroup.fromJson(json))
              .where((group) => group.disabled == 0)
              .toList();
        });
      }

      setState(() => isLoading = false);
    } catch (e) {
      setState(() => isLoading = false);
      _showErrorToast('Failed to load data: $e');
    }
  }

  Future<List<Item>> _fetchDetailedItems(List<Item> basicItems) async {
    final List<Item> detailedItems = [];

    for (final basicItem in basicItems) {
      try {
        // Check cache first
        if (_detailedItemsCache.containsKey(basicItem.itemCode)) {
          detailedItems.add(_detailedItemsCache[basicItem.itemCode]!);
          continue;
        }

        // Fetch detailed item information
        final response = await PosService().getItem(basicItem.itemCode);

        if (response['success'] == true) {
          final detailedItem = Item.fromDetailedJson(response['message']);
          _detailedItemsCache[basicItem.itemCode] = detailedItem;
          detailedItems.add(detailedItem);
        } else {
          // If detailed fetch fails → mark as not POS
          detailedItems.add(
            basicItem.copyWith(isPosItem: 0),
          );
        }
      } catch (e) {
        print('Error fetching detailed info for ${basicItem.itemCode}: $e');
        // Same here → mark as not POS
        detailedItems.add(
          basicItem.copyWith(isPosItem: 0),
        );
      }
    }

    return detailedItems;
  }

  Future<void> _refreshItemDetails(Item item) async {
    try {
      // Fetch updated detailed information
      final response = await PosService().getItem(item.itemCode);

      if (response['success'] == true) {
        final updatedItem = Item.fromDetailedJson(response['message']);
        _detailedItemsCache[item.itemCode] = updatedItem;

        // Update the item in the list
        setState(() {
          final index = items.indexWhere((i) => i.itemCode == item.itemCode);
          if (index != -1) {
            items[index] = updatedItem;
          }
        });
      }
    } catch (e) {
      print('Error refreshing item details: $e');
    }
  }

  void _showCreateItemDialog() {
    showDialog(
      context: context,
      builder: (context) => CreateItemDialog(
        itemGroups: itemGroups,
        variantGroups: variantGroups,
        onSave: _loadData,
      ),
    );
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
          onSave: _loadData,
        ),
      );
    });
  }

  Future<void> _toggleItemStatus(Item item, bool isActive) async {
    try {
      setState(() => isLoading = true);
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
      await _loadData();
      _showSuccessToast(
          'Item ${isActive ? 'activated' : 'deactivated'} successfully');
    } catch (e) {
      _showErrorToast('Failed to update status: $e');
    } finally {
      setState(() => isLoading = false);
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
    return SingleChildScrollView(
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
          const SizedBox(height: 16),

          // Items List
          if (isLoading)
            const Center(child: CircularProgressIndicator())
          else if (items.isEmpty)
            const Center(child: Text('No items found'))
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return ItemCard(
                  item: item,
                  onEdit: () => _showEditItemDialog(item),
                  onStatusToggle: (value) => _toggleItemStatus(item, value),
                );
              },
            ),
        ],
      ),
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
  bool isActive = true;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    isActive = widget.item.disabled == 0;
  }

  Future<void> _toggleActiveStatus(bool value) async {
    if (!mounted) return;

    setState(() => isLoading = true);
    try {
      await widget.onStatusToggle(value);
      if (mounted) {
        setState(() => isActive = value);
      }
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
    _isPosItem = widget.item.isPosItemBool;

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
  final int isPosItem; // Use custom_is_pos_item from detailed API

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
  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      itemCode: json['item_code'] ?? '',
      itemName: json['item_name'] ?? '',
      itemGroup: json['item_group'] ?? '',
      price: (json['price_list_rate'] as num?)?.toDouble() ?? 0.0,
      imageUrl: json['image'] != null
          ? 'https://mejaa.joydivisionpadel.com${json['image']}'
          : null,
      description: json['description'] as String?,
      variantGroups: (json['structured_variant_info'] as List<dynamic>?)
              ?.map((e) => e['variant_group'].toString())
              .toList() ??
          [],
      disabled: json['disabled'] as int? ?? 0,
      // For basic list, we might not have custom_is_pos_item, so default to 1
      isPosItem: 1, // Default value until we fetch detailed info
    );
  }

  // Factory method for detailed item response
  factory Item.fromDetailedJson(Map<String, dynamic> json) {
    return Item(
      itemCode: json['item_code'] ?? '',
      itemName: json['item_name'] ?? '',
      itemGroup: json['item_group'] ?? '',
      price: (json['price_list_rate'] as num?)?.toDouble() ?? 0.0,
      imageUrl: json['image'] != null
          ? 'https://mejaa.joydivisionpadel.com${json['image']}'
          : null,
      description: json['description'] as String?,
      variantGroups: (json['custom_variant_group_table'] as List<dynamic>?)
              ?.map((e) => e['variant_group'].toString())
              .toList() ??
          [],
      disabled: json['disabled'] as int? ?? 0,
      // FIX: Use the actual custom_is_pos_item from detailed API
      isPosItem: json['custom_is_pos_item'] as int? ?? 1,
    );
  }

  // Helper getter for UI convenience
  bool get isPosItemBool => isPosItem == 1;
}
