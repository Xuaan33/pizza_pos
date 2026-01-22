import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shiok_pos_android_app/components/main_layout.dart';
import 'package:shiok_pos_android_app/components/no_stretch_scroll_behavior.dart';
import 'package:shiok_pos_android_app/dialogs/option_dialog.dart';
import 'package:shiok_pos_android_app/screens/Settings%20Screen/variant_group.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';

class VariantSection extends ConsumerStatefulWidget {
  const VariantSection({Key? key}) : super(key: key);

  @override
  ConsumerState<VariantSection> createState() => _VariantSectionState();
}

class _VariantSectionState extends ConsumerState<VariantSection> {
  List<VariantGroup> variantGroups = [];
  bool isLoading = true;
  bool isRequired = false;
  int optionRequiredNo = 1;
  List<Map<String, dynamic>> confirmedOptions = [];
  String _searchQuery = '';
  String _sortBy = 'name'; // Default sort by name
  bool _sortAscending = true;
  List<VariantGroup> _filteredVariantGroups = [];

  // NEW: Scroll controller to preserve position
  final ScrollController _scrollController = ScrollController();

  // NEW: Track if we're doing a single item update
  bool _isSingleItemUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadVariantGroups();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadVariantGroups() async {
    try {
      if (mounted) {
        setState(() => isLoading = true);
      }

      final response =
          await _safeApiCall(() => PosService().getVariantGroups());
      if (response['success'] == true) {
        if (mounted) {
          setState(() {
            variantGroups = (response['message'] as List)
                .map((json) => VariantGroup.fromJson(json))
                .toList();
            isLoading = false;
            _applyFilters();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        Fluttertoast.showToast(
          msg: 'Error loading variant groups: $e',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    }
  }

  // NEW: Reload data after creating new variant group (scroll to top makes sense here)
  Future<void> _loadDataAfterCreate() async {
    await _loadVariantGroups();
    // Scroll to top to show the new item (user expects this)
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with Add Record button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Variant Groups',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
            ElevatedButton(
              onPressed: _showCreateVariantGroupDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Add Variant Group',
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
                    hintText: 'Search by variant group name...',
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
                    // Sort Button
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

                    // Reset Filters Button
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

        // Body expands with scrollable list - ADDED ScrollController
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredVariantGroups.isEmpty
                  ? const Center(child: Text('No variant groups found'))
                  : ScrollConfiguration(
                      behavior: NoStretchScrollBehavior(),
                      child: ListView.builder(
                        controller: _scrollController, // ADD THIS
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _filteredVariantGroups.length,
                        itemBuilder: (context, index) {
                          final group = _filteredVariantGroups[index];
                          return VariantGroupCard(
                            variantGroup: group,
                            onEdit: () => _showEditVariantGroupDialog(group),
                            onStatusToggle: (value) =>
                                _toggleVariantGroupStatus(group, value),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  void _showCreateVariantGroupDialog() {
    final nameController = TextEditingController();
    bool isRequired = false;
    int optionRequiredNo = 1;
    int maximumSelection = 1;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Create Variant Group',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Variant Group Name *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'Required?',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 16),
                    Switch(
                      value: isRequired,
                      onChanged: (value) =>
                          setDialogState(() => isRequired = value),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Minimum selection (existing)
                Row(
                  children: [
                    const Text('Minimum selection:'),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        controller: TextEditingController(
                            text: optionRequiredNo.toString()),
                        onChanged: (value) =>
                            optionRequiredNo = int.tryParse(value) ?? 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Maximum selection (new)
                Row(
                  children: [
                    const Text('Maximum selection:'),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        controller: TextEditingController(
                            text: maximumSelection.toString()),
                        onChanged: (value) =>
                            maximumSelection = int.tryParse(value) ?? 1,
                      ),
                    ),
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
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  Fluttertoast.showToast(
                    msg: 'Variant Group Name is required',
                    gravity: ToastGravity.BOTTOM,
                    backgroundColor: Colors.orange,
                    textColor: Colors.white,
                  );
                  return;
                }

                // Validate that maximum is not less than minimum
                if (maximumSelection < optionRequiredNo) {
                  Fluttertoast.showToast(
                    msg:
                        'Maximum selection cannot be less than minimum selection',
                    gravity: ToastGravity.BOTTOM,
                    backgroundColor: Colors.orange,
                    textColor: Colors.white,
                  );
                  return;
                }

                await _createVariantGroup(
                  nameController.text.trim(),
                  isRequired,
                  optionRequiredNo,
                  maximumSelection,
                );
                Navigator.pop(context);
              },
              child: const Text(
                'Create',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // UPDATED: Added optionRequiredNo and maximumSelection parameters
  Future<void> _createVariantGroup(
    String title,
    bool isRequired,
    int optionRequiredNo,
    int maximumSelection,
  ) async {
    try {
      setState(() => isLoading = true);
      final response = await _safeApiCall(() => PosService().createVariantGroup(
            title: title,
            variantInfoTable: [],
            required: isRequired ? 1 : 0,
            optionRequiredNo: optionRequiredNo,
            maximumSelection: maximumSelection,
            allowMultipleSelection: maximumSelection > 1 ? 1 : 0,
          ));

      if (response['success'] == true) {
        _loadDataAfterCreate(); // Use the new method
        Fluttertoast.showToast(
          msg: 'Variant group created successfully',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      } else {
        throw Exception(
            response['message'] ?? 'Failed to create variant group');
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Error: $e',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _showEditVariantGroupDialog(VariantGroup group) {
    final nameController = TextEditingController(text: group.variantGroup);
    final descriptionController = TextEditingController();

    List<Map<String, dynamic>> confirmedOptions = (group.options ?? [])
        .map((o) => {
              "option": (o.option ?? "").toString(),
              "additional_cost": (o.additionalCost ?? 0).toDouble(),
            })
        .toList();

    bool isRequired = (group.required ?? 0) == 1;
    int optionRequiredNo = group.optionRequiredNo ?? 1;
    int maximumSelection = group.maximumSelection ?? 1;
    bool allowMultipleSelection = (group.allowMultipleSelection ?? 0) == 1;

    // Create controllers for the number fields
    final minSelectionController =
        TextEditingController(text: optionRequiredNo.toString());
    final maxSelectionController =
        TextEditingController(text: maximumSelection.toString());

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Edit Variant Group',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 400,
            height: MediaQuery.of(context).size.height * 0.8,
            child: ScrollConfiguration(
              behavior: NoStretchScrollBehavior(),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 7,
                    ),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Variant Group Name *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),

                    // Required toggle
                    Row(
                      children: [
                        const Text('Required?'),
                        const SizedBox(width: 16),
                        Switch(
                          value: isRequired,
                          onChanged: (value) =>
                              setDialogState(() => isRequired = value),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Allow Multiple Selection toggle
                    Row(
                      children: [
                        const Text('Allow Multiple Selection?'),
                        const SizedBox(width: 16),
                        Switch(
                          value: allowMultipleSelection,
                          onChanged: (value) {
                            setDialogState(() {
                              allowMultipleSelection = value;
                              // If disabling multiple selection, ensure max selection is 1
                              if (!value && maximumSelection > 1) {
                                maximumSelection = 1;
                                maxSelectionController.text = '1';
                              }
                              // If enabling multiple selection and min is > 1, ensure max >= min
                              if (value &&
                                  maximumSelection < optionRequiredNo) {
                                maximumSelection = optionRequiredNo;
                                maxSelectionController.text =
                                    optionRequiredNo.toString();
                              }
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Minimum selection
                    Row(
                      children: [
                        const Text('Minimum selection:'),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            decoration: const InputDecoration(
                                border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            controller: minSelectionController,
                            onChanged: (value) {
                              // Allow empty or invalid input temporarily for editing
                              if (value.isEmpty) return;

                              final newValue = int.tryParse(value);
                              if (newValue == null || newValue < 1) return;

                              setDialogState(() {
                                optionRequiredNo = newValue;
                                // Ensure maximum is not less than minimum
                                if (maximumSelection < newValue) {
                                  maximumSelection = newValue;
                                  maxSelectionController.text =
                                      newValue.toString();
                                }
                                // If min > 1, automatically enable multiple selection
                                if (newValue > 1 && !allowMultipleSelection) {
                                  allowMultipleSelection = true;
                                  Fluttertoast.showToast(
                                    msg:
                                        'Multiple selection enabled automatically',
                                    gravity: ToastGravity.BOTTOM,
                                    backgroundColor: Colors.blue,
                                    textColor: Colors.white,
                                  );
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Maximum selection
                    Row(
                      children: [
                        const Text('Maximum selection:'),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            decoration: const InputDecoration(
                                border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            controller: maxSelectionController,
                            onChanged: (value) {
                              // Allow empty or invalid input temporarily for editing
                              if (value.isEmpty) return;

                              final newValue = int.tryParse(value);
                              if (newValue == null || newValue < 1) return;

                              setDialogState(() {
                                maximumSelection = newValue;
                                // Ensure minimum is not more than maximum
                                if (optionRequiredNo > newValue) {
                                  optionRequiredNo = newValue;
                                  minSelectionController.text =
                                      newValue.toString();
                                }
                                // If max > 1, automatically enable multiple selection
                                if (newValue > 1 && !allowMultipleSelection) {
                                  allowMultipleSelection = true;
                                  Fluttertoast.showToast(
                                    msg:
                                        'Multiple selection enabled automatically',
                                    gravity: ToastGravity.BOTTOM,
                                    backgroundColor: Colors.blue,
                                    textColor: Colors.white,
                                  );
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Header row + Manage Options button
                    Row(
                      children: [
                        const Text('Current Variants:',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: () async {
                            final result =
                                await showDialog<List<Map<String, dynamic>>>(
                              context: context,
                              builder: (_) =>
                                  OptionDialog(options: confirmedOptions),
                            );
                            if (result != null) {
                              setDialogState(() {
                                confirmedOptions = result;
                              });
                            }
                          },
                          child: const Text("Manage Options"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Scrollable list of current variants with fixed height
                    SizedBox(
                      height: 200,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: confirmedOptions.length,
                        itemBuilder: (_, i) {
                          final opt = confirmedOptions[i];
                          return ListTile(
                            dense: true,
                            title: Text(opt["option"]?.toString() ?? ""),
                            subtitle: Text(
                              "RM ${(opt["additional_cost"] as double).toStringAsFixed(2)}",
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  Fluttertoast.showToast(
                    msg: "Variant Group Name is required",
                    gravity: ToastGravity.BOTTOM,
                    backgroundColor: Colors.orange,
                    textColor: Colors.white,
                  );
                  return;
                }

                // Validate minimum selection field
                if (minSelectionController.text.isEmpty ||
                    int.tryParse(minSelectionController.text) == null ||
                    int.parse(minSelectionController.text) < 1) {
                  Fluttertoast.showToast(
                    msg: 'Minimum selection must be at least 1',
                    gravity: ToastGravity.BOTTOM,
                    backgroundColor: Colors.orange,
                    textColor: Colors.white,
                  );
                  return;
                }

                // Validate maximum selection field
                if (maxSelectionController.text.isEmpty ||
                    int.tryParse(maxSelectionController.text) == null ||
                    int.parse(maxSelectionController.text) < 1) {
                  Fluttertoast.showToast(
                    msg: 'Maximum selection must be at least 1',
                    gravity: ToastGravity.BOTTOM,
                    backgroundColor: Colors.orange,
                    textColor: Colors.white,
                  );
                  return;
                }

                // Update values from controllers
                optionRequiredNo = int.parse(minSelectionController.text);
                maximumSelection = int.parse(maxSelectionController.text);

                // Validate that maximum is not less than minimum
                if (maximumSelection < optionRequiredNo) {
                  Fluttertoast.showToast(
                    msg:
                        'Maximum selection cannot be less than minimum selection',
                    gravity: ToastGravity.BOTTOM,
                    backgroundColor: Colors.orange,
                    textColor: Colors.white,
                  );
                  return;
                }

                // Validate that if optionRequiredNo > 1, multiple selection must be allowed
                if (optionRequiredNo > 1 && !allowMultipleSelection) {
                  Fluttertoast.showToast(
                    msg:
                        'Multiple selection must be enabled when minimum selection is greater than 1',
                    gravity: ToastGravity.BOTTOM,
                    backgroundColor: Colors.orange,
                    textColor: Colors.white,
                  );
                  return;
                }

                // Validate that if multiple selection is not allowed, max should be 1
                if (!allowMultipleSelection && maximumSelection > 1) {
                  Fluttertoast.showToast(
                    msg:
                        'Maximum selection must be 1 when multiple selection is disabled',
                    gravity: ToastGravity.BOTTOM,
                    backgroundColor: Colors.orange,
                    textColor: Colors.white,
                  );
                  return;
                }

                // NEW: Set single item update flag
                if (mounted) {
                  setState(() {
                    _isSingleItemUpdate = true;
                  });
                }

                await _safeApiCall(() => PosService().updateVariantGroup(
                      name: nameController.text.trim(),
                      required: isRequired ? 1 : 0,
                      optionRequiredNo: optionRequiredNo,
                      maximumSelection: maximumSelection,
                      allowMultipleSelection: allowMultipleSelection ? 1 : 0,
                      variantInfoTable: confirmedOptions,
                    ));

                Navigator.pop(context);

                // NEW: Update only the specific variant group instead of reloading all
                await _refreshSingleVariantGroup(group.variantGroup);
              },
              child: const Text('Update',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // NEW: Refresh single variant group instead of reloading all
  Future<void> _refreshSingleVariantGroup(String variantGroupName) async {
    try {
      // Fetch all variant groups and find the updated one
      final response =
          await _safeApiCall(() => PosService().getVariantGroups());

      if (response['success'] == true && mounted) {
        final allGroups = (response['message'] as List)
            .map((json) => VariantGroup.fromJson(json))
            .toList();

        // Find the index of the updated group in the filtered list
        final index = _filteredVariantGroups
            .indexWhere((group) => group.variantGroup == variantGroupName);

        if (index != -1) {
          // Find the updated group in the new data
          final updatedGroup = allGroups.firstWhere(
            (group) => group.variantGroup == variantGroupName,
            orElse: () => _filteredVariantGroups[index],
          );

          // Update both the main list and filtered list
          final mainIndex = variantGroups
              .indexWhere((group) => group.variantGroup == variantGroupName);

          if (mainIndex != -1) {
            setState(() {
              variantGroups[mainIndex] = updatedGroup;
              _filteredVariantGroups[index] = updatedGroup;
              _isSingleItemUpdate = false;
            });
          }

          Fluttertoast.showToast(
            msg: "Variant group updated successfully",
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.green,
            textColor: Colors.white,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSingleItemUpdate = false;
        });
      }
      print('Error refreshing variant group: $e');
    }
  }

  Future<void> _toggleVariantGroupStatus(
      VariantGroup group, bool isActive) async {
    try {
      // NEW: Set single item update flag instead of full loading
      if (mounted) {
        setState(() {
          _isSingleItemUpdate = true;
        });
      }

      await _safeApiCall(() => PosService().disableVariantGroup(
            variantGroup: group.variantGroup,
            disabled: isActive ? 0 : 1,
          ));

      // NEW: Update only the specific variant group
      await _refreshSingleVariantGroup(group.variantGroup);

      Fluttertoast.showToast(
        msg:
            "Variant group ${isActive ? 'activated' : 'deactivated'} successfully",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Failed to update status: $e",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      if (mounted && _isSingleItemUpdate) {
        setState(() {
          _isSingleItemUpdate = false;
        });
      }
    }
  }

  // Apply filters function
  void _applyFilters() {
    List<VariantGroup> filtered = variantGroups.where((group) {
      // Search filter
      final matchesSearch = _searchQuery.isEmpty ||
          group.variantGroup.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesSearch;
    }).toList();

    // Apply sorting
    filtered.sort((a, b) {
      int compareResult;
      switch (_sortBy) {
        case 'name':
          compareResult = a.variantGroup.compareTo(b.variantGroup);
          break;
        case 'options':
          compareResult = a.options.length.compareTo(b.options.length);
          break;
        case 'status':
          compareResult = a.disabled.compareTo(b.disabled);
          break;
        default:
          compareResult = a.variantGroup.compareTo(b.variantGroup);
      }

      return _sortAscending ? compareResult : -compareResult;
    });

    setState(() {
      _filteredVariantGroups = filtered;
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
        case 'options':
          sortText = 'Options ${_sortAscending ? 'Few-Many' : 'Many-Few'}';
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
                'Sort Variant Groups',
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
                        RadioListTile<String>(
                          title: const Text('Number of Options'),
                          value: 'options',
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

  Future<T> _safeApiCall<T>(Future<T> Function() apiCall) async {
    try {
      final mainLayout = MainLayout.of(context);
      if (mainLayout != null) {
        return await mainLayout.safeExecuteAPICall(apiCall);
      }
    } catch (e) {
      debugPrint('MainLayout not available: $e');
    }
    return await apiCall(); // Fallback
  }
}
