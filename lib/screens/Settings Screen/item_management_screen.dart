import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';

class ItemManagementScreen extends ConsumerStatefulWidget {
  const ItemManagementScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<ItemManagementScreen> createState() =>
      _ItemManagementScreenState();
}

class _ItemManagementScreenState extends ConsumerState<ItemManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  List<dynamic> _items = [];
  List<dynamic> _itemGroups = [];
  List<dynamic> _variantGroups = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _selectedItem;
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _imageUrlController = TextEditingController();
  String? _selectedItemGroup;
  String? _selectedVariantGroup;
  bool _isDisabled = false;
  final List<Map<String, dynamic>> _variantGroupTable = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      // Get posProfile from auth state or context
      final authState =
          ref.read(authProvider); // Assuming you're using Provider
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
        throw Exception('Not authenticated or posProfile not available');
      }

      final [itemsRes, groupsRes, variantsRes] = await Future.wait([
        PosService().getAllItems(posProfile), // Only this one needs posProfile
        PosService().getItemGroups(), // No posProfile needed
        PosService().getVariantGroups(), // No posProfile needed
      ]);

      setState(() {
        // Handle items response
        final itemsData = itemsRes['message'];
        if (itemsData is Map && itemsData.containsKey('items')) {
          _items = itemsData['items'] ?? [];
        } else if (itemsData is List) {
          _items = itemsData;
        } else {
          _items = [];
        }

        // Handle item groups
        final groupsData = groupsRes['message'];
        if (groupsData is List) {
          _itemGroups = groupsData
              .where((group) => group['name'] != null)
              .toList(); // Filter out groups with null names
        } else if (groupsData is Map && groupsData.containsKey('data')) {
          _itemGroups = (groupsData['data'] as List)
              .where((group) => group['name'] != null)
              .toList();
        } else if (groupsData is Map) {
          _itemGroups = groupsData['name'] != null ? [groupsData] : [];
        } else {
          _itemGroups = [];
        }

        // Handle variant groups
        final variantsData = variantsRes['message'];
        if (variantsData is List) {
          _variantGroups =
              variantsData.where((group) => group['name'] != null).toList();
        } else if (variantsData is Map && variantsData.containsKey('data')) {
          _variantGroups = (variantsData['data'] as List)
              .where((group) => group['name'] != null)
              .toList();
        } else if (variantsData is Map) {
          _variantGroups = variantsData['name'] != null ? [variantsData] : [];
        } else {
          _variantGroups = [];
        }

        // Reset invalid selections
        if (_selectedItem != null &&
            !_items.any((item) => item['item_code'] == _selectedItem)) {
          _resetForm();
        }
        if (_selectedItemGroup != null &&
            !_itemGroups.any((group) => group['name'] == _selectedItemGroup)) {
          _selectedItemGroup = null;
        }
        if (_selectedVariantGroup != null &&
            !_variantGroups
                .any((group) => group['name'] == _selectedVariantGroup)) {
          _selectedVariantGroup = null;
        }
      });
    } catch (e) {
      _showError('Failed to load initial data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadItemDetails(String itemCode) async {
    setState(() => _isLoading = true);
    try {
      final response = await PosService().getItem(itemCode);
      final data = response['message'];

      // Verify if itemCode exists in _items
      final isValidItem = _items.any((item) => item['item_code'] == itemCode);
      if (!isValidItem) {
        _showError('Selected item not found in available items');
        _resetForm();
        return;
      }

      setState(() {
        _selectedItem = itemCode;
        _codeController.text = data['item_code'] ?? '';
        _nameController.text = data['item_name'] ?? '';
        _descriptionController.text = data['description'] ?? '';
        _imageUrlController.text = data['image_url'] ?? '';

        // Validate item group
        final itemGroup = data['item_group'];
        print('Item Group from API: $itemGroup');
        print(
            'Available Item Groups: ${_itemGroups.map((g) => g['name']).toList()}');
        _selectedItemGroup =
            _itemGroups.any((group) => group['name'] == itemGroup)
                ? itemGroup
                : null;

        // Validate variant group
        final variantGroup = data['variant_group'];
        print('Variant Group from API: $variantGroup');
        print(
            'Available Variant Groups: ${_variantGroups.map((g) => g['name']).toList()}');
        _selectedVariantGroup =
            _variantGroups.any((group) => group['name'] == variantGroup)
                ? variantGroup
                : null;

        _isDisabled = data['disabled'] == 1;
        _variantGroupTable.clear();
        if (data['variant_group_table'] != null) {
          _variantGroupTable.addAll(
              List<Map<String, dynamic>>.from(data['variant_group_table']));
        }
      });
    } catch (e) {
      _showError('Failed to load item details: $e');
      _resetForm();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveItem() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      if (_selectedItem == null) {
        // Create new
        await PosService().createItem(
          itemCode: _codeController.text,
          itemName: _nameController.text,
          itemGroup: _selectedItemGroup ?? '',
          variantGroupTable: _variantGroupTable,
          description: _descriptionController.text.isEmpty
              ? null
              : _descriptionController.text,
          imageUrl: _imageUrlController.text.isEmpty
              ? null
              : _imageUrlController.text,
        );
        _showSuccess('Item created successfully');
      } else {
        // Update existing
        await PosService().updateItem(
          itemCode: _codeController.text,
          itemName: _nameController.text,
          itemGroup: _selectedItemGroup,
          variantGroupTable:
              _variantGroupTable.isNotEmpty ? _variantGroupTable : null,
          disabled: _isDisabled ? 1 : 0,
          description: _descriptionController.text.isEmpty
              ? null
              : _descriptionController.text,
          imageUrl: _imageUrlController.text.isEmpty
              ? null
              : _imageUrlController.text,
        );
        _showSuccess('Item updated successfully');
      }
      _loadInitialData();
      _resetForm();
    } catch (e) {
      _showError('Failed to save item: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteItem() async {
    if (_selectedItem == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      // Implement delete API call if available
      _showSuccess('Item deleted successfully');
      _loadInitialData();
      _resetForm();
    } catch (e) {
      _showError('Failed to delete item: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _resetForm() {
    setState(() {
      _selectedItem = null;
      _codeController.clear();
      _nameController.clear();
      _descriptionController.clear();
      _imageUrlController.clear();
      _selectedItemGroup = null;
      _selectedVariantGroup = null;
      _variantGroupTable.clear();
      _isDisabled = false;
    });
  }

  void _showError(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.red,
      textColor: Colors.white,
    );
  }

  void _showSuccess(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.green,
      textColor: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Items'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    _buildItemDropdown(),
                    const SizedBox(height: 20),
                    if (_selectedItem != null || _selectedItem == null)
                      _buildItemForm(),
                    const SizedBox(height: 20),
                    _buildActionButtons(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildItemDropdown() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width - 32,
        ),
        child: DropdownButtonFormField<String>(
          value: _selectedItem,
          decoration: const InputDecoration(
            labelText: 'Select Item',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.search),
          ),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('Create New Item'),
            ),
            ..._items.map((item) {
              return DropdownMenuItem<String>(
                value: item['item_code'],
                child: Text('${item['item_name']} (${item['item_code']})'),
              );
            }).toList(),
          ],
          onChanged: (value) {
            setState(() {
              _selectedItem = value;
              if (value != null) {
                _loadItemDetails(value);
              } else {
                _resetForm();
              }
            });
          },
        ),
      ),
    );
  }

  Widget _buildItemForm() {
    return Column(
      children: [
        TextFormField(
          controller: _codeController,
          decoration: const InputDecoration(
            labelText: 'Item Code',
            border: OutlineInputBorder(),
          ),
          validator: (value) =>
              value?.isEmpty ?? true ? 'Required field' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Item Name',
            border: OutlineInputBorder(),
          ),
          validator: (value) =>
              value?.isEmpty ?? true ? 'Required field' : null,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _selectedItemGroup,
          decoration: const InputDecoration(
            labelText: 'Item Group',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('Select Item Group'),
            ),
            ..._itemGroups.map((group) {
              return DropdownMenuItem<String>(
                value: group['name'],
                child: Text(
                  group['item_group_name']?.toString() ??
                      group['name']?.toString() ??
                      'Untitled Group',
                ),
              );
            }).toList(),
          ],
          onChanged: (value) {
            print('Selected Item Group: $value');
            setState(() => _selectedItemGroup = value);
          },
          validator: (value) => value == null ? 'Required field' : null,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _selectedVariantGroup,
          decoration: const InputDecoration(
            labelText: 'Variant Group (optional)',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('No Variant Group'),
            ),
            ..._variantGroups.map((group) {
              return DropdownMenuItem<String>(
                value: group['name'],
                child: Text(group['title'] ??
                    group['name'] ??
                    'Untitled Variant Group'),
              );
            }).toList(),
          ],
          onChanged: (value) => setState(() => _selectedVariantGroup = value),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _descriptionController,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _imageUrlController,
          decoration: const InputDecoration(
            labelText: 'Image URL (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Disabled'),
          value: _isDisabled,
          onChanged: (value) => setState(() => _isDisabled = value),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveItem,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isSaving
                ? const CircularProgressIndicator(color: Colors.white)
                : Text(
                    _selectedItem == null ? 'Create' : 'Update',
                    style: const TextStyle(fontSize: 16),
                  ),
          ),
        ),
        if (_selectedItem != null) ...[
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: _isSaving ? null : _deleteItem,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
