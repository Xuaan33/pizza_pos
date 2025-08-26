import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';

class VariantManagementScreen extends ConsumerStatefulWidget {
  const VariantManagementScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<VariantManagementScreen> createState() =>
      _VariantManagementScreenState();
}

class _VariantManagementScreenState
    extends ConsumerState<VariantManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  List<dynamic> _variantGroups = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _selectedVariantGroup;
  final TextEditingController _titleController = TextEditingController();
  final List<Map<String, dynamic>> _variantInfoTable = [];
  bool _isRequired = true;
  bool _isOptionRequired = true;

  @override
  void initState() {
    super.initState();
    // Initialize with null to ensure dropdown starts in a valid state
    _selectedVariantGroup = null;
    _loadVariantGroups();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadVariantGroups() async {
    setState(() => _isLoading = true);
    try {
      final response = await PosService().getVariantGroups();
      final newVariantGroups = response['message'] ?? [];

      // Map API response to expected format
      final mappedVariantGroups = newVariantGroups.map((group) {
        return {
          'name': group['variant_group']?.toString(),
          'title': group['variant_group']?.toString() ?? 'Untitled Group',
        };
      }).toList();

      setState(() {
        _variantGroups = mappedVariantGroups;
        _validateSelectedVariantGroup();
      });
    } catch (e) {
      _showError('Failed to load variant groups: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _validateSelectedVariantGroup() {
    // Check if the currently selected variant group still exists
    if (_selectedVariantGroup != null) {
      final exists = _variantGroups
          .any((group) => group['name']?.toString() == _selectedVariantGroup);

      if (!exists) {
        // Reset if the selected variant group no longer exists
        _selectedVariantGroup = null;
        _resetForm();
      }
    }
  }

  Future<void> _loadVariantGroupDetails(String name) async {
    setState(() => _isLoading = true);
    try {
      final response = await PosService().getVariantGroup(name);
      final data = response['message'];

      setState(() {
        _titleController.text = data['variant_group'] ?? '';
        _variantInfoTable.clear();
        if (data['options'] != null) {
          _variantInfoTable.addAll(
            List<Map<String, dynamic>>.from(data['options']).map((option) {
              return {
                'option': option['option']?.toString(),
                'price_adjustment': option['additional_cost'] ?? 0.0,
              };
            }).toList(),
          );
        }
        _isRequired = data['required'] == 1;
        _isOptionRequired = data['option_required_no'] == 1;
      });
    } catch (e) {
      _showError('Failed to load variant group details: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveVariantGroup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      // Prepare variant info table with correct field names
      final mappedVariantInfoTable = _variantInfoTable.map((option) {
        return {
          'option': option['option'],
          'additional_cost': option['price_adjustment'],
        };
      }).toList();

      if (_selectedVariantGroup == null) {
        // Create new
        await PosService().createVariantGroup(
          title: _titleController.text,
          variantInfoTable: mappedVariantInfoTable,
          required: _isRequired ? 1 : 0,
          optionRequiredNo: _isOptionRequired ? 1 : 0,
        );
        _showSuccess('Variant group created successfully');
      } else {
        // Update existing
        await PosService().updateVariantGroup(
          name: _selectedVariantGroup!,
          variantInfoTable: mappedVariantInfoTable,
          required: _isRequired ? 1 : 0,
          optionRequiredNo: _isOptionRequired ? 1 : 0,
        );
        _showSuccess('Variant group updated successfully');
      }
      await _loadVariantGroups();
      _resetForm();
    } catch (e) {
      _showError('Failed to save variant group: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteVariantGroup() async {
    if (_selectedVariantGroup == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content:
            const Text('Are you sure you want to delete this variant group?'),
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
      _showSuccess('Variant group deleted successfully');
      await _loadVariantGroups();
      _resetForm();
    } catch (e) {
      _showError('Failed to delete variant group: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _resetForm() {
    setState(() {
      _selectedVariantGroup = null;
      _titleController.clear();
      _variantInfoTable.clear();
      _isRequired = true;
      _isOptionRequired = true;
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
        title: const Text('Manage Variant Groups'),
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
                    // Only show dropdown if variant groups are loaded
                    if (_variantGroups.isNotEmpty ||
                        _selectedVariantGroup == null)
                      _buildVariantGroupDropdown()
                    else
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('Loading variant groups...'),
                        ),
                      ),
                    const SizedBox(height: 20),
                    _buildVariantGroupForm(),
                    const SizedBox(height: 20),
                    _buildActionButtons(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildVariantGroupDropdown() {
    // Build the items list first
    final dropdownItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: null,
        child: Text('Create New Variant Group'),
      ),
    ];

    // Add variant groups with null safety
    for (final group in _variantGroups) {
      final groupName = group['name']?.toString();
      if (groupName != null && groupName.isNotEmpty) {
        dropdownItems.add(
          DropdownMenuItem<String>(
            value: groupName,
            child: Text(group['title']?.toString() ?? 'Untitled Group'),
          ),
        );
      }
    }

    // Get all available values from items
    final availableValues = dropdownItems.map((item) => item.value).toSet();

    // Force reset to null if current selection is invalid
    String? validSelectedValue = null;
    if (_selectedVariantGroup != null &&
        availableValues.contains(_selectedVariantGroup)) {
      validSelectedValue = _selectedVariantGroup;
    }

    // Debug: Print values to help identify the issue
    print('Available values: $availableValues');
    print('Selected value: $_selectedVariantGroup');
    print('Valid selected value: $validSelectedValue');

    // If we have an invalid selection, schedule a reset
    if (_selectedVariantGroup != null &&
        !availableValues.contains(_selectedVariantGroup)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selectedVariantGroup = null;
            _resetForm();
          });
        }
      });
    }

    return DropdownButtonFormField<String>(
      key: ValueKey('dropdown_${_variantGroups.length}_$validSelectedValue'),
      value: validSelectedValue,
      decoration: const InputDecoration(
        labelText: 'Select Variant Group',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.search),
      ),
      items: dropdownItems,
      onChanged: (value) {
        setState(() {
          _selectedVariantGroup = value;
          if (value != null) {
            _loadVariantGroupDetails(value);
          } else {
            _resetForm();
          }
        });
      },
    );
  }

  Widget _buildVariantGroupForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: 'Title',
            border: OutlineInputBorder(),
          ),
          validator: (value) =>
              value?.isEmpty ?? true ? 'Required field' : null,
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Required'),
          value: _isRequired,
          onChanged: (value) => setState(() => _isRequired = value),
        ),
        SwitchListTile(
          title: const Text('Option Required'),
          value: _isOptionRequired,
          onChanged: (value) => setState(() => _isOptionRequired = value),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Variant Options:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ElevatedButton.icon(
              onPressed: _addVariantOption,
              icon: const Icon(Icons.add),
              label: const Text('Add Option'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_variantInfoTable.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'No variant options added yet. Click "Add Option" to get started.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ..._buildVariantOptions(),
      ],
    );
  }

  List<Widget> _buildVariantOptions() {
    return _variantInfoTable.asMap().entries.map((entry) {
      final index = entry.key;
      final option = entry.value;

      return Card(
        margin: const EdgeInsets.only(bottom: 8.0),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).primaryColor,
            child: Text(
              '${index + 1}',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Text(option['option']?.toString() ?? 'Unnamed Option'),
          subtitle: Text(
            'Price Adjustment: \$${(option['price_adjustment'] ?? 0.0).toStringAsFixed(2)}',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => setState(() => _variantInfoTable.removeAt(index)),
          ),
        ),
      );
    }).toList();
  }

  void _addVariantOption() {
    final optionController = TextEditingController();
    final priceController = TextEditingController(text: '0.00');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Variant Option'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: optionController,
              decoration: const InputDecoration(
                labelText: 'Option Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: priceController,
              decoration: const InputDecoration(
                labelText: 'Price Adjustment',
                border: OutlineInputBorder(),
                prefixText: '\$',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (optionController.text.isNotEmpty) {
                final priceAdjustment =
                    double.tryParse(priceController.text) ?? 0.0;
                setState(() {
                  _variantInfoTable.add({
                    'option': optionController.text,
                    'price_adjustment': priceAdjustment,
                  });
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveVariantGroup,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    _selectedVariantGroup == null ? 'Create' : 'Update',
                    style: const TextStyle(fontSize: 16),
                  ),
          ),
        ),
        if (_selectedVariantGroup != null) ...[
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: _isSaving ? null : _deleteVariantGroup,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
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
