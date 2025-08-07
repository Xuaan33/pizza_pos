import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiok_pos_android_app/components/closing_entry_dialog.dart';
import 'package:shiok_pos_android_app/components/item.dart';
import 'package:shiok_pos_android_app/components/item_group.dart';
import 'package:shiok_pos_android_app/components/opening_entry_dialog.dart';
import 'package:shiok_pos_android_app/components/variant_group.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _selectedIndex = 0;
  bool _isPosConnected = false;
  bool _isTesting = false;
  bool _isSaving = false; // Add this for save button loading state
  final TextEditingController _ipController =
      TextEditingController(text: '192.168.');
  final TextEditingController _portController =
      TextEditingController(text: '8800');
  List<VariantGroup> variantGroups = [];
  bool isLoading = true;

  static const List<String> _sections = [
    'POS Opening & Closing',
    'POS Card Terminal',
    'Item Group',
    'Item',
    'Variant',
    'Stock',
    'Finished Goods',
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedConfig(); // Load saved config when widget initializes
    _loadVariantGroups();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _loadVariantGroups() async {
    try {
      final response = await PosService().getVariantGroups();
      if (response['success'] == true) {
        setState(() {
          variantGroups = (response['message'] as List)
              .map((json) => VariantGroup.fromJson(json))
              .toList();
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() => isLoading = false);
      Fluttertoast.showToast(
        msg: 'Error loading variant groups: $e',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  Future<void> _loadSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ipController.text = prefs.getString('pos_ip') ?? '192.168';
      _portController.text = '8800';
    });
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);

    final posIp = _ipController.text.trim();
    final posPort = _portController.text.trim();

    if (posIp.isEmpty || posPort.isEmpty) {
      Fluttertoast.showToast(
        msg: "Please enter both IP and Port",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      setState(() => _isSaving = false);
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pos_ip', posIp);
      await prefs.setInt('pos_port', int.tryParse(posPort) ?? 8800);

      Fluttertoast.showToast(
        msg: "Configuration saved successfully",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Failed to save configuration: $e",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return authState.when(
      initial: () => const Center(child: CircularProgressIndicator()),
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
      ) {
        return Scaffold(
          body: Row(
            children: [
              // Navigation Drawer
              Container(
                width: 250,
                color: Colors.grey[100],
                child: ListView.builder(
                  itemCount: _sections.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      title: Text(_sections[index]),
                      selected: _selectedIndex == index,
                      onTap: () {
                        setState(() {
                          _selectedIndex = index;
                        });
                      },
                    );
                  },
                ),
              ),
              // Main Content
              Expanded(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(20),
                  child: _buildSectionContent(_selectedIndex, hasOpening),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionContent(int index, bool hasOpening) {
    switch (index) {
      case 0:
        return _buildPosOpeningClosingSection(hasOpening);
      case 1:
        return _buildPosTerminalSection();
      case 2:
        return _buildItemGroupSection();
      case 3:
        return _buildItemSection();
      case 4:
        return _buildVariantSection();
      case 5:
        return _buildStockSection();
      case 6:
        return _buildFinishedGoodsSection();
      default:
        return const Center(child: Text('Select a section'));
    }
  }

  Widget _buildPosOpeningClosingSection(bool hasOpening) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'POS Opening & Closing',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 30),
        Row(
          children: [
            Expanded(
              child: _buildOpeningEntryButton(hasOpening),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildClosingEntryButton(hasOpening),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPosTerminalSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'POS Terminal Connection',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        _buildConnectionStatusIndicator(),
        const SizedBox(height: 20),
        _buildConnectionForm(),
        const SizedBox(height: 20),
        _buildTestButton(),
      ],
    );
  }

  Widget _buildItemGroupSection() {
    return SingleChildScrollView(
      child: Container(
        height: MediaQuery.of(context).size.height - 200,
        child: ItemGroupManagement(),
      ),
    );
  }

  Widget _buildItemSection() {
    return SingleChildScrollView(
      child: Container(
        height: MediaQuery.of(context).size.height - 200,
        child: ItemManagement(),
      ),
    );
  }

  Widget _buildVariantSection() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Add Record button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Variant Groups',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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

          // Variant Groups List
          if (isLoading)
            const Center(child: CircularProgressIndicator())
          else if (variantGroups.isEmpty)
            const Center(child: Text('No variant groups found'))
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: variantGroups.length,
              itemBuilder: (context, index) {
                final group = variantGroups[index];
                return VariantGroupCard(
                  variantGroup: group,
                  onEdit: () => _showEditVariantGroupDialog(group),
                  onStatusToggle: (value) =>
                      _toggleVariantGroupStatus(group, value),
                );
              },
            ),
        ],
      ),
    );
  }

  void _showCreateVariantGroupDialog() {
    final nameController = TextEditingController();
    bool isRequired = false;

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
                await _createVariantGroup(
                    nameController.text.trim(), isRequired);
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

  void _showCreateVariantDialog(VariantGroup group) {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final priceController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          'Add Variant to ${group.variantGroup}',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Variant Name *',
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
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: priceController,
                    decoration: const InputDecoration(
                      labelText: 'Additional Cost',
                      border: OutlineInputBorder(),
                      prefixText: 'RM ',
                    ),
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                Fluttertoast.showToast(
                  msg: 'Variant Name is required',
                  gravity: ToastGravity.BOTTOM,
                  backgroundColor: Colors.orange,
                  textColor: Colors.white,
                );
                return;
              }

              await _addVariantToGroup(
                group,
                nameController.text.trim(),
                double.tryParse(priceController.text) ?? 0.0,
              );
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _createVariantGroup(String title, bool isRequired) async {
    try {
      setState(() => isLoading = true);
      final response = await PosService().createVariantGroup(
        title: title,
        variantInfoTable: [],
        requiredNo: isRequired ? 1 : 0,
        optionRequiredNo: 1,
      );

      if (response['success'] == true) {
        _loadVariantGroups();
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

  Future<void> _addVariantToGroup(
      VariantGroup group, String variantName, double additionalCost) async {
    try {
      // Create updated variant info table
      final updatedVariants = List<Map<String, dynamic>>.from(
        group.options.map((option) => {
              'option': option.option,
              'additional_cost': option.additionalCost,
            }),
      );

      // Add new variant
      updatedVariants.add({
        'option': variantName,
        'additional_cost': additionalCost,
      });

      final response = await PosService().updateVariantGroup(
        name: group.variantGroup,
        variantInfoTable: updatedVariants,
        requiredNo: group.required,
        optionRequiredNo: group.optionRequiredNo,
      );

      if (response['success'] == true) {
        Fluttertoast.showToast(
          msg: 'Variant added successfully',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
        _loadVariantGroups(); // Reload the list
      } else {
        throw Exception(response['message'] ?? 'Failed to add variant');
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Error: $e',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  void _showEditVariantGroupDialog(VariantGroup group) {
    final nameController = TextEditingController(text: group.variantGroup);
    final descriptionController =
        TextEditingController(); // Fill if available in model
    bool isRequired = group.required == 1;
    int optionRequiredNo = group.optionRequiredNo;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          title: Text(
            'Edit Variant Group',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Required?'),
                        const SizedBox(width: 16),
                        Switch(
                          value: isRequired,
                          onChanged: (value) {
                            setDialogState(() {
                              isRequired = value;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Option Required Number:'),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            controller: TextEditingController(
                              text: optionRequiredNo.toString(),
                            ),
                            onChanged: (value) {
                              optionRequiredNo = int.tryParse(value) ?? 1;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Current Variants:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: ListView.builder(
                        itemCount: group.options.length,
                        itemBuilder: (context, index) {
                          final option = group.options[index];
                          return ListTile(
                            dense: true,
                            title: Text(option.option),
                            subtitle: Text(
                              option.additionalCost > 0
                                  ? 'Additional Cost: RM ${option.additionalCost.toStringAsFixed(2)}'
                                  : 'Free',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit, size: 16),
                              onPressed: () {
                                _showEditVariantDialog(group, option, index);
                              },
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
              child: Text(
                'Cancel',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
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

                await _updateVariantGroup(
                  group,
                  nameController.text.trim(),
                  isRequired,
                  optionRequiredNo,
                );
                Navigator.pop(context);
              },
              child: Text(
                'Update',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditVariantDialog(
      VariantGroup group, VariantOption option, int optionIndex) {
    final nameController = TextEditingController(text: option.option);
    final priceController =
        TextEditingController(text: option.additionalCost.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Variant'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Variant Name *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priceController,
                  decoration: const InputDecoration(
                    labelText: 'Additional Cost',
                    border: OutlineInputBorder(),
                    prefixText: 'RM ',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _deleteVariantFromGroup(group, optionIndex);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                Fluttertoast.showToast(
                  msg: "Variant Name is required",
                  toastLength: Toast.LENGTH_LONG,
                  gravity: ToastGravity.BOTTOM,
                  backgroundColor: Colors.orange,
                  textColor: Colors.white,
                );
                return;
              }

              await _updateVariantInGroup(
                group,
                optionIndex,
                nameController.text.trim(),
                double.tryParse(priceController.text) ?? 0.0,
              );
              Navigator.pop(context);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateVariantGroup(
    VariantGroup group,
    String newTitle,
    bool isRequired,
    int optionRequiredNo,
  ) async {
    try {
      final response = await PosService().updateVariantGroup(
        name: group.variantGroup,
        variantInfoTable: group.options
            .map((option) => {
                  'option': option.option,
                  'additional_cost': option.additionalCost,
                })
            .toList(),
        requiredNo: isRequired ? 1 : 0,
        optionRequiredNo: optionRequiredNo,
      );

      if (response['success'] == true) {
        _loadVariantGroups();
        Fluttertoast.showToast(
          msg: "Variant group updated successfully",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      } else {
        throw Exception(
            response['message'] ?? 'Failed to update variant group');
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Error: $e",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  Future<void> _toggleVariantGroupStatus(
      VariantGroup group, bool isActive) async {
    try {
      setState(() => isLoading = true);
      await PosService().disableVariantGroup(
        variantGroup: group.variantGroup,
        disabled: isActive ? 0 : 1,
      );
      _loadVariantGroups(); // Refresh the list
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
      setState(() => isLoading = false);
    }
  }

  Future<void> _updateVariantInGroup(
    VariantGroup group,
    int optionIndex,
    String newVariantName,
    double newAdditionalCost,
  ) async {
    try {
      // Create updated variant info table
      final updatedVariants = List<Map<String, dynamic>>.from(
        group.options.asMap().entries.map((entry) => {
              'option': entry.key == optionIndex
                  ? newVariantName
                  : entry.value.option,
              'additional_cost': entry.key == optionIndex
                  ? newAdditionalCost
                  : entry.value.additionalCost,
            }),
      );

      final response = await PosService().updateVariantGroup(
        name: group.variantGroup,
        variantInfoTable: updatedVariants,
        requiredNo: group.required,
        optionRequiredNo: group.optionRequiredNo,
      );

      if (response['success'] == true) {
        Fluttertoast.showToast(
          msg: 'Variant updated successfully',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
        _loadVariantGroups(); // Reload the list
      } else {
        throw Exception(response['message'] ?? 'Failed to update variant');
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Error: $e',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  Future<void> _deleteVariantFromGroup(
      VariantGroup group, int optionIndex) async {
    try {
      // Create updated variant info table without the deleted variant
      final updatedVariants = group.options
          .asMap()
          .entries
          .where((entry) => entry.key != optionIndex)
          .map((entry) => {
                'option': entry.value.option,
                'additional_cost': entry.value.additionalCost,
              })
          .toList();

      final response = await PosService().updateVariantGroup(
        name: group.variantGroup,
        variantInfoTable: updatedVariants,
        requiredNo: group.required,
        optionRequiredNo: group.optionRequiredNo,
      );

      if (response['success'] == true) {
        Fluttertoast.showToast(
          msg: 'Variant deleted successfully',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
        _loadVariantGroups(); // Reload the list
      } else {
        throw Exception(response['message'] ?? 'Failed to delete variant');
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Error: $e',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  Widget _buildStockSection() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Stock Management',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 20),
        Text('Stock management will be shown here'),
      ],
    );
  }

  Widget _buildFinishedGoodsSection() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Finished Goods Management',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 20),
        Text('Finished goods management will be shown here'),
      ],
    );
  }

  Widget _buildOpeningEntryButton(bool hasOpening) {
    final isDisabled = hasOpening;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isDisabled ? null : () => _showOpeningEntryDialog(),
        style: ElevatedButton.styleFrom(
          backgroundColor: isDisabled ? Colors.grey[400] : Colors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Text(
          isDisabled ? 'Opened' : 'Create Opening Entry',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _showOpeningEntryDialog() {
    showDialog(
      context: context,
      builder: (context) => const OpeningEntryDialog(),
    );
  }

  Widget _buildClosingEntryButton(bool hasOpening) {
    final isDisabled = !hasOpening;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isDisabled ? null : () => _showClosingEntryDialog(),
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isDisabled ? Colors.grey[400] : const Color(0xFFE732A0),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Text(
          isDisabled ? 'No Opening Entry' : 'Create Closing Entry',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Future<void> _showClosingEntryDialog() async {
    try {
      final authState = ref.read(authProvider);

      await authState.whenOrNull(
        authenticated: (sid, apiKey, apiSecret, username, email, fullName,
            posProfile, branch, paymentMethods, taxes, hasOpening, tier) async {
          final response = await PosService().requestClosingVoucher(
            posProfile: posProfile,
          );

          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => ClosingEntryDialog(closingData: response),
            );
          }
        },
      );
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: "Error requesting closing data: ${e.toString()}",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    }
  }

  Widget _buildConnectionStatusIndicator() {
    return Row(
      children: [
        Icon(
          _isPosConnected ? Icons.check_circle : Icons.error,
          color: _isPosConnected ? Colors.green : Colors.red,
          size: 24,
        ),
        const SizedBox(width: 8),
        Text(
          _isPosConnected ? 'Testing OK' : 'Not Test',
          style: TextStyle(
            fontSize: 16,
            color: _isPosConnected ? Colors.green : Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionForm() {
    return Column(
      children: [
        TextField(
          controller: _ipController,
          decoration: const InputDecoration(
            labelText: 'POS Terminal IP',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.computer),
          ),
          keyboardType: TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveConfig,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50), // Green color for save
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Save Configuration',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildTestButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isTesting ? null : _testPosConnection,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFE732A0),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: _isTesting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                'Test POS Terminal Connection',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Future<void> _testPosConnection() async {
    setState(() {
      _isTesting = true;
      _isPosConnected = false;
    });

    final posIp = _ipController.text.trim();
    final posPort = int.tryParse(_portController.text.trim()) ?? 8800;

    // 1. Verify basic network reachability
    if (!await _isHostReachable(posIp)) {
      _handleConnectionError("Host $posIp is unreachable");
      setState(() => _isTesting = false);
      return;
    }

    // 2. Attempt connection with proper message
    const pingHexMessage =
        "02 00 18 36 30 30 30 30 30 30 30 30 30 31 30 46 46 30 30 30 1C 03 30";

    try {
      // Extended timeout for initial connection
      final socket = await Socket.connect(posIp, posPort,
          timeout: const Duration(seconds: 5));

      // Configure socket for response handling
      socket.setOption(SocketOption.tcpNoDelay, true);
      socket.listen(
        (data) => _handleResponse(data),
        onError: (e) => _handleConnectionError(e.toString()),
        onDone: () => socket.destroy(),
      );

      // Send ping message
      socket.add(_hexStringToBytes(pingHexMessage));

      // Set timeout for complete transaction
      Timer(const Duration(seconds: 10), () {
        if (!_isPosConnected) {
          socket.destroy();
          _handleConnectionError("Response timeout");
        }
      });
      socket.destroy();
    } on SocketException catch (e) {
      _handleConnectionError("Network error: ${e.message}");
    } on Exception catch (e) {
      _handleConnectionError(e.toString());
    } finally {
      if (!_isPosConnected) {
        setState(() => _isTesting = false);
      }
    }
  }

  Future<bool> _isHostReachable(String ip) async {
    try {
      final result = await InternetAddress.lookup(ip);
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _handleConnectionError(String error) {
    setState(() {
      _isPosConnected = false;
    });
    Fluttertoast.showToast(
      msg: "POS Connection Failed: $error",
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.red,
      textColor: Colors.white,
    );
    debugPrint('POS Connection Error: $error');
  }

  List<int> _hexStringToBytes(String hexString) {
    return hexString
        .split(' ')
        .map((hex) => int.parse(hex, radix: 16))
        .toList();
  }

  void _handleResponse(List<int> data) {
    try {
      final hexResponse =
          data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      debugPrint('Raw POS Response (Hex): $hexResponse');

      // Handle ACK (06) response
      if (data.length == 1 && data[0] == 0x06) {
        _handleSuccessfulConnection("POS Terminal connected! (ACK received)");
        return;
      }

      // Validate full message format
      if (data.length < 5) {
        throw Exception('Response too short (${data.length} bytes)');
      }

      // Verify STX (02) and ETX (03) markers
      if (data.first != 0x02 || data[data.length - 2] != 0x03) {
        throw Exception('Missing STX/ETX markers');
      }

      // Calculate LRC
      int calculatedLrc = 0;
      for (int i = 0; i < data.length - 1; i++) {
        calculatedLrc ^= data[i];
      }

      final receivedLrc = data.last;
      final shouldAccept =
          (calculatedLrc == receivedLrc) || (receivedLrc == 0x31);

      if (!shouldAccept) {
        throw Exception('LRC mismatch');
      }

      // Success case
      _handleSuccessfulConnection("POS Terminal connected successfully!");
      final parsed = parsePosResponse(data);
      debugPrint(jsonEncode(parsed));
    } catch (e) {
      _handleConnectionError("Protocol error: ${e.toString()}");
    }
  }

  Map<String, dynamic> parsePosResponse(List<int> data) {
    final hex = data.map((b) => b.toRadixString(16).padLeft(2, '0')).toList();

    if (data.length < 5) {
      throw Exception("Invalid POS response (too short)");
    }

    return {
      "STX": hex[0].toUpperCase(),
      "Length": "${hex[1].toUpperCase()} ${hex[2].toUpperCase()}",
      "TransportHeader":
          hex.sublist(3, data.indexOf(0x1C)).join('').toUpperCase(),
      "PresentationHeader": hex
          .sublist(data.indexOf(0x1C), data.length - 1)
          .join('')
          .toUpperCase(),
      "ETX": "03",
      "LRC": hex.last.toUpperCase(),
      "Fields": {}, // Needs decoding spec to populate
      "status": "success",
      "message": "Transaction successful."
    };
  }

  void _handleSuccessfulConnection(String message) {
    setState(() {
      _isPosConnected = true;
      _isTesting = false;
    });
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.green,
      textColor: Colors.white,
    );
  }
}
