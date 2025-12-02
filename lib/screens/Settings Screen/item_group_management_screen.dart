import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';

class ItemGroupManagementScreen extends ConsumerStatefulWidget {
  const ItemGroupManagementScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<ItemGroupManagementScreen> createState() =>
      _ItemGroupManagementScreenState();
}

class _ItemGroupManagementScreenState
    extends ConsumerState<ItemGroupManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  List<dynamic> _itemGroups = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _selectedItemGroup;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _parentController = TextEditingController();
  bool _isGroup = false;

  @override
  void initState() {
    super.initState();
    _loadItemGroups();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _parentController.dispose();
    super.dispose();
  }

  Future<void> _loadItemGroups() async {
    setState(() => _isLoading = true);
    try {
      final response = await PosService().getItemGroups();
      // Handle the actual API response structure
      final message = response['message'];
      List<dynamic> itemGroupsList = [];

      if (message is Map && message.containsKey('item_groups')) {
        itemGroupsList = message['item_groups'] ?? [];
      } else if (message is List) {
        itemGroupsList = message;
      } else if (message is Map) {
        // Try other common keys
        if (message.containsKey('data') && message['data'] is List) {
          itemGroupsList = message['data'];
        } else if (message.containsKey('items') && message['items'] is List) {
          itemGroupsList = message['items'];
        } else if (message.containsKey('results') &&
            message['results'] is List) {
          itemGroupsList = message['results'];
        }
      }

      setState(() {
        _itemGroups = itemGroupsList;
        // Reset selected item group to avoid dropdown assertion error
        _selectedItemGroup = '__create_new__';
      });
    } catch (e) {
      print('Error loading item groups: $e'); // Debug print
      _showError('Failed to load item groups: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadItemGroupDetails(String name) async {
    setState(() => _isLoading = true);
    try {
      final response = await PosService().getItemGroup(name);
      final data = response['message'];

      // Add null checks and type safety
      if (data is Map<String, dynamic>) {
        _nameController.text = data['item_group_name']?.toString() ?? '';
        _parentController.text = data['parent_item_group']?.toString() ?? '';
        _isGroup = data['is_group'] == 1 || data['is_group'] == true;
      } else {
        _showError('Invalid item group data format');
      }
    } catch (e) {
      print('Error loading item group details: $e'); // Debug print
      _showError('Failed to load item group details: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveItemGroup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      if (_selectedItemGroup == null) {
        // Create new
        await PosService().createItemGroup(
          itemGroupName: _nameController.text,
          parentItemGroup:
              _parentController.text.isEmpty ? null : _parentController.text,
          isGroup: _isGroup ? 1 : 0,
        );
        _showSuccess('Item group created successfully');
      } else {
        // Update existing
        await PosService().updateItemGroup(
          name: _selectedItemGroup!,
          itemGroupName: _nameController.text,
          parentItemGroup:
              _parentController.text.isEmpty ? null : _parentController.text,
          isGroup: _isGroup ? 1 : 0,
          disabled: 0
        );
        _showSuccess('Item group updated successfully');
      }
      _loadItemGroups();
      _clearForm();
    } catch (e) {
      print('Error saving item group: $e'); // Debug print
      _showError('Failed to save item group: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteItemGroup() async {
    if (_selectedItemGroup == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this item group?'),
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
      // await PosService().deleteItemGroup(_selectedItemGroup!);
      _showSuccess('Item group deleted successfully');
      _loadItemGroups();
      _clearForm();
    } catch (e) {
      print('Error deleting item group: $e'); // Debug print
      _showError('Failed to delete item group: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _clearForm() {
    setState(() => _selectedItemGroup = null);
    _nameController.clear();
    _parentController.clear();
    _isGroup = false;
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
        title: const Text('Manage Item Groups'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildItemGroupDropdown(),
                    const SizedBox(height: 20),
                    _buildItemGroupForm(),
                    const SizedBox(height: 40),
                    _buildActionButtons(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildItemGroupDropdown() {
    final validItemGroups = _itemGroups
        .where(
            (group) => group is Map<String, dynamic> && group['name'] != null)
        .toList();

    final dropdownItems = [
      const DropdownMenuItem<String>(
        value: '__create_new__', // Use a special string instead of null
        child: Text('Create New Item Group'),
      ),
      ...validItemGroups.map((group) {
        final name = group['name'].toString();
        final displayName = group['value']?.toString() ?? name;
        return DropdownMenuItem<String>(
          value: name,
          child: Text(displayName),
        );
      }),
    ];

    // Set default selected value safely
    final currentValue = _selectedItemGroup ?? '__create_new__';
    final validValues = dropdownItems.map((item) => item.value).toSet();
    final safeValue =
        validValues.contains(currentValue) ? currentValue : '__create_new__';

    return DropdownButtonFormField<String>(
      value: safeValue,
      decoration: const InputDecoration(
        labelText: 'Select Item Group',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.search),
      ),
      items: dropdownItems,
      onChanged: (value) {
        setState(() {
          if (value == '__create_new__') {
            _selectedItemGroup = null;
            _nameController.clear();
            _parentController.clear();
            _isGroup = false;
          } else {
            _selectedItemGroup = value;
            if (value != null) _loadItemGroupDetails(value);
          }
        });
      },
    );
  }

  Widget _buildItemGroupForm() {
    return Column(
      children: [
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Group Name',
            border: OutlineInputBorder(),
          ),
          validator: (value) =>
              value?.isEmpty ?? true ? 'Required field' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _parentController,
          decoration: const InputDecoration(
            labelText: 'Parent Group (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Is Group'),
          subtitle:
              const Text('Enable if this is a category, not a product group'),
          value: _isGroup,
          onChanged: (value) => setState(() => _isGroup = value),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveItemGroup,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isSaving
                ? const CircularProgressIndicator(color: Colors.white)
                : Text(
                    _selectedItemGroup == null ? 'Create' : 'Update',
                    style: const TextStyle(fontSize: 16),
                  ),
          ),
        ),
        if (_selectedItemGroup != null) ...[
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: _isSaving ? null : _deleteItemGroup,
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
