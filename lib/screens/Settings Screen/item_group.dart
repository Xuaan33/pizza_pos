import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';

class ItemGroupManagement extends StatefulWidget {
  const ItemGroupManagement({super.key});

  @override
  State<ItemGroupManagement> createState() => _ItemGroupManagementState();
}

class _ItemGroupManagementState extends State<ItemGroupManagement> {
  List<ItemGroup> itemGroups = [];
  List<ItemGroup> filteredItemGroups = [];
  bool isLoading = true;

  // New state variables for search and sorting
  String _searchQuery = '';
  String _sortBy = 'name'; // Default sort by name
  bool _sortAscending = true;

  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey<_ItemGroupWrapperState>> _itemGroupKeys = {};

  @override
  void initState() {
    super.initState();
    _loadItemGroups();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadItemGroups() async {
    try {
      setState(() => isLoading = true);
      final response = await PosService().getItemGroups();

      if (response['success'] == true) {
        final List<dynamic> groupsData = response['message']['item_groups'];

        final groups = groupsData
            .map((group) => ItemGroup.fromJson(group))
            .where((group) =>
                group.name != 'All' && group.name != 'All Item Groups')
            .toList();

        // Create keys for each item group
        _itemGroupKeys.clear();
        for (final group in groups) {
          _itemGroupKeys[group.name] = GlobalKey<_ItemGroupWrapperState>();
        }

        setState(() {
          itemGroups = groups;
          _applyFilters();
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() => isLoading = false);
      _showErrorToast('Failed to load item groups: $e');
    }
  }

  Future<void> _refreshSingleItemGroup(String groupName) async {
    try {
      final response = await PosService().getItemGroup(groupName);

      if (response['success'] == true) {
        final updatedGroup = ItemGroup.fromJson(response['message']);

        // Update the specific item group wrapper using its key
        _itemGroupKeys[groupName]
            ?.currentState
            ?.updateStatus(updatedGroup.disabled);

        // Also update the underlying data (but DON'T call setState here!)
        final mainIndex = itemGroups.indexWhere((g) => g.name == groupName);
        if (mainIndex != -1) {
          itemGroups[mainIndex] = updatedGroup;
        }

        final filteredIndex =
            filteredItemGroups.indexWhere((g) => g.name == groupName);
        if (filteredIndex != -1) {
          filteredItemGroups[filteredIndex] = updatedGroup;
        }
      }
    } catch (e) {
      print('Error refreshing single item group: $e');
    }
  }

  void _applyFilters() {
    List<ItemGroup> filtered = itemGroups.where((group) {
      // Search filter
      final matchesSearch = _searchQuery.isEmpty ||
          group.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          group.value.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesSearch;
    }).toList();

    // Apply sorting
    filtered.sort((a, b) {
      int compareResult;
      switch (_sortBy) {
        case 'name':
          compareResult = a.name.compareTo(b.name);
          break;
        case 'value':
          compareResult = a.value.compareTo(b.value);
          break;
        case 'status':
          compareResult = a.disabled.compareTo(b.disabled);
          break;
        default:
          compareResult = a.name.compareTo(b.name);
      }

      return _sortAscending ? compareResult : -compareResult;
    });

    setState(() {
      filteredItemGroups = filtered;
    });
  }

  // Reset all filters
  void _resetFilters() {
    setState(() {
      _searchQuery = '';
      _sortBy = 'name';
      _sortAscending = true;
    });
    _applyFilters();
  }

  void _showCreateItemGroupDialog() {
    showDialog(
      context: context,
      builder: (context) => CreateItemGroupDialog(
        itemGroups: itemGroups,
        onSave: _loadItemGroups,
      ),
    );
  }

  void _showEditItemGroupDialog(ItemGroup group) {
    showDialog(
      context: context,
      builder: (context) => EditItemGroupDialog(
        itemGroup: group,
        itemGroups: itemGroups,
        posService: PosService(),
        onSave: () {
          _refreshSingleItemGroup(group.name);
        },
      ),
    );
  }

  Future<void> _toggleItemGroupStatus(ItemGroup group, bool isActive) async {
    try {
      await PosService().disableItemGroup(
        itemGroup: group.name,
        disabled: isActive ? 0 : 1,
      );

      // Refresh only this item group - no full reload!
      await _refreshSingleItemGroup(group.name);

      _showSuccessToast(
          'Item group ${isActive ? 'activated' : 'deactivated'} successfully');
    } catch (e) {
      _showErrorToast('Failed to update status: $e');
      debugPrint("Update error: $e");
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
      controller: _scrollController, // ADD scroll controller
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Add Record button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Item Groups',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
              ElevatedButton(
                onPressed: _showCreateItemGroupDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text(
                  'Add Item Group',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Search and Sort Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search Bar
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search by name or value...',
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
                                _applyFilters();
                              },
                            )
                          : null,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                      _applyFilters();
                    },
                  ),
                  const SizedBox(height: 16),

                  // Sort Row
                  Row(
                    children: [
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

          // Item Groups List
          if (isLoading)
            const Center(child: CircularProgressIndicator())
          else if (filteredItemGroups.isEmpty)
            const Center(child: Text('No item groups found'))
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredItemGroups.length,
              itemBuilder: (context, index) {
                final group = filteredItemGroups[index];

                // Ensure key exists
                if (!_itemGroupKeys.containsKey(group.name)) {
                  _itemGroupKeys[group.name] =
                      GlobalKey<_ItemGroupWrapperState>();
                }

                return ItemGroupWrapper(
                  key: _itemGroupKeys[group.name],
                  itemGroup: group,
                  onEdit: () => _showEditItemGroupDialog(group),
                  onStatusToggle: (value) =>
                      _toggleItemGroupStatus(group, value),
                );
              },
            ),
        ],
      ),
    );
  }

  // Check if any filters are active
  bool get _hasActiveFilters {
    return _searchQuery.isNotEmpty || _sortBy != 'name' || !_sortAscending;
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
          _applyFilters();
        },
      ));
    }

    if (_sortBy != 'name' || !_sortAscending) {
      String sortText = '';
      switch (_sortBy) {
        case 'name':
          sortText = 'Name ${_sortAscending ? 'A-Z' : 'Z-A'}';
          break;
        case 'value':
          sortText = 'Value ${_sortAscending ? 'A-Z' : 'Z-A'}';
          break;
        case 'status':
          sortText =
              'Status ${_sortAscending ? 'Active First' : 'Inactive First'}';
          break;
      }

      chips.add(Chip(
        label: Text('Sort: $sortText'),
        onDeleted: () {
          setState(() {
            _sortBy = 'name';
            _sortAscending = true;
          });
          _applyFilters();
        },
      ));
    }

    return chips;
  }

  // Show sort dialog
  void _showSortDialog() {
    String? tempSortBy = _sortBy;
    bool? tempSortAscending = _sortAscending;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text(
                'Sort Item Groups',
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
                          groupValue: tempSortBy,
                          onChanged: (value) {
                            setStateDialog(() {
                              tempSortBy = value;
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
                          groupValue: tempSortAscending,
                          onChanged: (value) {
                            setStateDialog(() {
                              tempSortAscending = value;
                            });
                          },
                        ),
                        const Text('Ascending'),
                        Radio<bool>(
                          value: false,
                          groupValue: tempSortAscending,
                          onChanged: (value) {
                            setStateDialog(() {
                              tempSortAscending = value;
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
                    // Apply the sort options
                    setState(() {
                      _sortBy = tempSortBy!;
                      _sortAscending = tempSortAscending!;
                    });
                    _applyFilters();
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

class ItemGroupWrapper extends StatefulWidget {
  final ItemGroup itemGroup;
  final VoidCallback onEdit;
  final Function(bool) onStatusToggle;

  const ItemGroupWrapper({
    Key? key,
    required this.itemGroup,
    required this.onEdit,
    required this.onStatusToggle,
  }) : super(key: key);

  @override
  State<ItemGroupWrapper> createState() => _ItemGroupWrapperState();
}

class _ItemGroupWrapperState extends State<ItemGroupWrapper> {
  late int _disabled;

  @override
  void initState() {
    super.initState();
    _disabled = widget.itemGroup.disabled;
  }

  // Method to update status without rebuilding parent
  void updateStatus(int newDisabled) {
    if (mounted) {
      setState(() {
        _disabled = newDisabled;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ItemGroupCard(
      itemGroup: widget.itemGroup,
      disabled: _disabled,
      onEdit: widget.onEdit,
      onStatusToggle: widget.onStatusToggle,
    );
  }
}

class ItemGroupCard extends StatefulWidget {
  final ItemGroup itemGroup;
  final int disabled;
  final VoidCallback onEdit;
  final Function(bool) onStatusToggle;

  const ItemGroupCard({
    super.key,
    required this.itemGroup,
    required this.disabled,
    required this.onEdit,
    required this.onStatusToggle,
  });

  @override
  State<ItemGroupCard> createState() => _ItemGroupCardState();
}

class _ItemGroupCardState extends State<ItemGroupCard> {
  bool isExpanded = false;
  bool isLoading = false;

  bool get isActive => widget.disabled == 0;

  Future<void> _toggleActiveStatus(bool value) async {
    if (!mounted) return;

    setState(() => isLoading = true);
    try {
      await widget.onStatusToggle(value);

      Fluttertoast.showToast(
        msg: '${widget.itemGroup.name} ${value ? 'activated' : 'deactivated'}',
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
      debugPrint("Update error: $e");
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
            leading: Icon(
              isExpanded
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_right,
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    widget.itemGroup.name,
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
            subtitle: Text('Group: ${widget.itemGroup.value}'),
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
                        'Group Details:',
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
                        _buildDetailRow('Name:', widget.itemGroup.name),
                        const SizedBox(height: 8),
                        _buildDetailRow('Value:', widget.itemGroup.value),
                        const SizedBox(height: 8),
                        _buildDetailRow(
                            'Status:', isActive ? 'Active' : 'Inactive'),
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

// Dialog for creating new item group
class CreateItemGroupDialog extends StatefulWidget {
  final List<ItemGroup> itemGroups;
  final VoidCallback onSave;

  const CreateItemGroupDialog({
    super.key,
    required this.itemGroups,
    required this.onSave,
  });

  @override
  State<CreateItemGroupDialog> createState() => _CreateItemGroupDialogState();
}

class _CreateItemGroupDialogState extends State<CreateItemGroupDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  String? _selectedParentGroup;
  bool _isGroup = false;
  bool _isLoading = false;
  bool _itemGroupExpanded = false;

  Future<void> _saveItemGroup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await PosService().createItemGroup(
        itemGroupName: _nameController.text,
        parentItemGroup: _selectedParentGroup,
        isGroup: _isGroup ? 1 : 0,
      );

      if (response['success'] == true) {
        widget.onSave();
        Navigator.pop(context);
        Fluttertoast.showToast(
          msg: 'Item group created successfully',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      } else {
        throw Exception('Failed to create item group');
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
        'Create Item Group',
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
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Group Name *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty ?? true
                      ? 'Please enter a group name'
                      : null,
                ),
                const SizedBox(height: 16),

                // Parent Group selection
                const Text(
                  'Parent Group (Optional)',
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
                                child: _selectedParentGroup == null
                                    ? const Text(
                                        'Select Parent Group',
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
                                          _selectedParentGroup!,
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
                                  groupValue: _selectedParentGroup,
                                  onChanged: (String? value) {
                                    setState(() {
                                      _selectedParentGroup = value;
                                      _itemGroupExpanded = false;
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

                // Is Group toggle
                Row(
                  children: [
                    const Text('Is Group?'),
                    const SizedBox(width: 16),
                    Switch(
                      value: _isGroup,
                      onChanged: (value) => setState(() => _isGroup = value),
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
          onPressed: _isLoading ? null : _saveItemGroup,
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
    _nameController.dispose();
    super.dispose();
  }
}

// Dialog for editing item group
class EditItemGroupDialog extends StatefulWidget {
  final ItemGroup itemGroup;
  final List<ItemGroup> itemGroups;
  final dynamic posService;
  final VoidCallback onSave;

  const EditItemGroupDialog({
    super.key,
    required this.itemGroup,
    required this.itemGroups,
    required this.posService,
    required this.onSave,
  });

  @override
  State<EditItemGroupDialog> createState() => _EditItemGroupDialogState();
}

class _EditItemGroupDialogState extends State<EditItemGroupDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  String? _selectedParentGroup;
  bool _isGroup = false;
  bool _isLoading = false;
  bool _itemGroupExpanded = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.itemGroup.name);
    _isGroup = widget.itemGroup.value ==
        widget.itemGroup.name; // Assuming value indicates is_group
  }

  Future<void> _updateItemGroup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await PosService().updateItemGroup(
        name: widget.itemGroup.name,
        itemGroupName: _nameController.text,
        parentItemGroup: _selectedParentGroup,
        isGroup: _isGroup ? 1 : 0,
        disabled: widget.itemGroup.disabled,
      );

      if (response['success'] == true) {
        widget.onSave();
        Navigator.pop(context);
        Fluttertoast.showToast(
          msg: 'Item group updated successfully',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      } else {
        throw Exception('Failed to update item group');
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
      title: const Text(
        'Edit Item Group',
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
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Group Name *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a group name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Parent Group selection
                const Text(
                  'Parent Group (Optional)',
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
                                child: _selectedParentGroup == null
                                    ? const Text(
                                        'Select Parent Group',
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
                                          _selectedParentGroup!,
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
                                if (group.name !=
                                    widget.itemGroup
                                        .name) // Exclude current group
                                  RadioListTile<String>(
                                    title: Text(group.name),
                                    value: group.name,
                                    groupValue: _selectedParentGroup,
                                    onChanged: (String? value) {
                                      setState(() {
                                        _selectedParentGroup = value;
                                        _itemGroupExpanded = false;
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

                // Is Group toggle
                Row(
                  children: [
                    const Text('Is Group?'),
                    const SizedBox(width: 16),
                    Switch(
                      value: _isGroup,
                      onChanged: (value) => setState(() => _isGroup = value),
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
          onPressed: _isLoading ? null : _updateItemGroup,
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
    _nameController.dispose();
    super.dispose();
  }
}

class ItemGroup {
  final String name;
  final String value;
  final int disabled;
  final List<Map<String, dynamic>> variantGroups; // Add variant groups support

  ItemGroup({
    required this.name,
    required this.value,
    required this.disabled,
    this.variantGroups = const [],
  });

  factory ItemGroup.fromJson(Map<String, dynamic> json) {
    return ItemGroup(
      name: json['name'] ?? '',
      value: json['item_group_name'] ?? json['value'] ?? '',
      disabled: json['disabled'] ?? 0,
      variantGroups: (json['custom_variant_group_table'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          [],
    );
  }
}
