import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiok_pos_android_app/components/closing_entry_dialog.dart';
import 'package:shiok_pos_android_app/components/item.dart';
import 'package:shiok_pos_android_app/components/item_group.dart';
import 'package:shiok_pos_android_app/components/opening_entry_dialog.dart';
import 'package:shiok_pos_android_app/components/option_dialog.dart';
import 'package:shiok_pos_android_app/components/stock_item_card.dart';
import 'package:shiok_pos_android_app/components/variant_group.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const String baseUrl = 'https://wakuwaku.joydivisionpadel.com';
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
  List<Map<String, dynamic>> _stockItems = [];
  bool _isStockLoading = false;
  DateTime _selectedDate = DateTime.now();
  TextEditingController _searchController = TextEditingController();
  TextEditingController _qtyController = TextEditingController();
  TextEditingController _actualQtyController = TextEditingController();
  List<Map<String, dynamic>> _filteredStockItems = [];
  bool isRequired = false;
  int optionRequiredNo = 1;
  List<Map<String, dynamic>> confirmedOptions = [];

  // Employee Management
  List<Map<String, dynamic>> _employees = [];
  bool _isEmployeeLoading = false;
  TextEditingController _employeeSearchController = TextEditingController();

  List<String> _getSections(String tier) {
    final sections = [
      'POS Opening & Closing',
      'POS Card Terminal',
      'Item Group',
      'Item',
      'Variant',
      'Stock',
    ];

    // Only add Employee Management for tier 2 and above
    if (tier.toLowerCase() != 'tier1') {
      sections.add('Employee Management');
    }

    return sections;
  }

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _filteredStockItems = _stockItems;
    _qtyController = TextEditingController();
    _actualQtyController = TextEditingController();
    _employeeSearchController = TextEditingController();
    _loadStockItems(); // Load stock items when screen initializes
    _loadSavedConfig(); // Load saved config when widget initializes
    _loadVariantGroups();
    _loadEmployees(); // Load employees when screen initializes
  }

  @override
  void dispose() {
    _searchController.dispose();
    _qtyController.dispose();
    _actualQtyController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _employeeSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadVariantGroups() async {
    try {
      if (mounted) {
        setState(() => isLoading = true);
      }

      final response = await PosService().getVariantGroups();
      if (response['success'] == true) {
        if (mounted) {
          setState(() {
            variantGroups = (response['message'] as List)
                .map((json) => VariantGroup.fromJson(json))
                .toList();
            isLoading = false;
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

  Future<void> _loadStockItems() async {
    try {
      if (mounted) {
        setState(() => _isStockLoading = true);
      }

      final authState = ref.read(authProvider);

      await authState.when(
        authenticated: (sid,
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
            printKitchenOrder) async {
          final response = await PosService().getStockBalanceSummary(
            posProfile: posProfile,
            isPosItem: 1,
            date: DateFormat('yyyy-MM-dd').format(_selectedDate),
          );

          if (response['success'] == true) {
            final items =
                List<Map<String, dynamic>>.from(response['message'] ?? []);

            // Map the API response to the expected format
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
                  imageUrl = '$baseUrl/$rawImage'; // ensure slash consistency
                }
              }

              return {
                'item_code': item['item'] ?? '',
                'item_name': item['item'] ?? '',
                'actual_qty': (item['qty'] ?? 0).toDouble(),
                'reserved_qty': 0.0,
                'available_qty': (item['qty'] ?? 0).toDouble(),
                'value': (item['value'] ?? 0).toDouble(),
                'image': imageUrl, // Now contains full URL
              };
            }).toList();

            if (mounted) {
              setState(() {
                _stockItems = mappedItems;
                _filteredStockItems = mappedItems; // Update filtered list too
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
          _filteredStockItems = []; // Clear filtered list too
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isStockLoading = false);
      }
    }
  }

  Future<void> _stockInItems(
    List<Map<String, dynamic>> items,
    double quantityToAdd, // Changed from String to double
  ) async {
    try {
      setState(() => _isStockLoading = true);
      final authState = ref.read(authProvider);

      await authState.when(
        authenticated: (sid,
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
            printKitchenOrder) async {
          final itemsToStockIn = items.map((item) {
            return {
              'item_code': item['item_code'],
              'qty': quantityToAdd, // Use the quantity directly
            };
          }).toList();

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
            await _loadStockItems(); // Refresh the list
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
    } finally {
      setState(() => _isStockLoading = false);
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
        msg: "Please enter IP Address",
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

  Future<void> _loadEmployees() async {
    try {
      if (mounted) {
        setState(() => _isEmployeeLoading = true);
      }

      final authState = ref.read(authProvider);

      await authState.when(
        authenticated: (sid,
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
            printKitchenOrder) async {
          final response = await PosService().getEmployees();
          if (response['success'] == true) {
            if (mounted) {
              setState(() {
                _employees =
                    List<Map<String, dynamic>>.from(response['message'] ?? []);
              });
            }
          } else {
            throw Exception(response['message'] ?? 'Failed to load employees');
          }
        },
        initial: () => throw Exception('Not authenticated'),
        unauthenticated: () => throw Exception('Not authenticated'),
      );
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Error loading employees: ${e.toString()}',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
        setState(() {
          _employees = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isEmployeeLoading = false);
      }
    }
  }

  Future<void> _employeeCheckIn(String employeeId, String branch) async {
    try {
      setState(() => _isEmployeeLoading = true);
      final response = await PosService().employeeCheckIn(
        employee: employeeId,
        branch: branch,
      );

      if (response['success'] == true) {
        Fluttertoast.showToast(
          msg: 'Check-in successful',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
        await _loadEmployees(); // Refresh the list
      } else {
        throw Exception(response['message'] ?? 'Failed to check in');
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Error checking in: ${e.toString()}',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      setState(() => _isEmployeeLoading = false);
    }
  }

  Future<void> _employeeCheckOut(String employeeId, String branch) async {
    try {
      setState(() => _isEmployeeLoading = true);
      final response = await PosService().employeeCheckOut(
        employee: employeeId,
        branch: branch,
      );

      if (response['success'] == true) {
        Fluttertoast.showToast(
          msg: 'Check-out successful',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
        await _loadEmployees(); // Refresh the list
      } else {
        throw Exception(response['message'] ?? 'Failed to check out');
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Error checking out: ${e.toString()}',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      setState(() => _isEmployeeLoading = false);
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
        printKitchenOrder,
      ) {
        final sections = _getSections(tier);

        return Scaffold(
          body: Row(
            children: [
              // Navigation Drawer
              Container(
                width: 250,
                color: Colors.grey[100],
                child: ListView.builder(
                  itemCount: sections.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      title: Text(sections[index]),
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
                  child: _buildSectionContent(_selectedIndex, hasOpening, tier),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionContent(int index, bool hasOpening, String tier) {
    final sections = _getSections(tier);

    if (index >= sections.length) {
      return const Center(child: Text('Select a section'));
    }

    final section = sections[index];

    switch (section) {
      case 'POS Opening & Closing':
        return _buildPosOpeningClosingSection(hasOpening);
      case 'POS Card Terminal':
        return _buildPosTerminalSection();
      case 'Item Group':
        return _buildItemGroupSection();
      case 'Item':
        return _buildItemSection();
      case 'Variant':
        return _buildVariantSection();
      case 'Stock':
        return _buildStockSection();
      case 'Employee Management':
        return _buildEmployeeManagementSection();
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
        height: MediaQuery.of(context).size.height,
        child: ItemGroupManagement(),
      ),
    );
  }

  Widget _buildItemSection() {
    return SingleChildScrollView(
      child: Container(
        height: MediaQuery.of(context).size.height,
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
        required: isRequired ? 1 : 0,
        optionRequiredNo: 1,
        maximumSelection: 1,
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
          required: group.required,
          optionRequiredNo: group.optionRequiredNo,
          maximumSelection: group.maximumSelection);

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
    final descriptionController = TextEditingController();

    List<Map<String, dynamic>> confirmedOptions = (group.options ?? [])
        .map((o) => {
              "option": (o.option ?? "").toString(),
              "additional_cost": (o.additionalCost ?? 0).toDouble(),
            })
        .toList();

    bool isRequired = (group.required ?? 0) == 1;
    int optionRequiredNo = group.optionRequiredNo ?? 1;
    int maximumSelection = group.maximumSelection ?? 1; // Add this variable

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Edit Variant Group',
              style: TextStyle(fontWeight: FontWeight.bold)),
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
                                border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            controller: TextEditingController(
                                text: maximumSelection.toString()),
                            onChanged: (value) =>
                                maximumSelection = int.tryParse(value) ?? 1,
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

                    // Scrollable list of current variants
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.3,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: confirmedOptions.length,
                        itemBuilder: (_, i) {
                          final opt = confirmedOptions[i];
                          return ListTile(
                            dense: true,
                            title: Text(opt["option"]?.toString() ?? ""),
                            subtitle: Text(
                                "RM ${opt["additional_cost"].toStringAsFixed(2) ?? 0}"),
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

                await PosService().updateVariantGroup(
                  name: nameController.text.trim(),
                  required: isRequired ? 1 : 0,
                  optionRequiredNo: optionRequiredNo,
                  maximumSelection: maximumSelection, // Add this parameter
                  variantInfoTable: confirmedOptions,
                );

                Navigator.pop(context);
                if (mounted) {
                  setState(() {
                    _loadVariantGroups();
                  });
                }
              },
              child: const Text('Update',
                  style: TextStyle(fontWeight: FontWeight.bold)),
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
    int maximumSelection
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
        required: isRequired ? 1 : 0,
        optionRequiredNo: optionRequiredNo,
        maximumSelection: maximumSelection
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
        required: group.required,
        optionRequiredNo: group.optionRequiredNo,
        maximumSelection: group.maximumSelection
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
        required: group.required,
        optionRequiredNo: group.optionRequiredNo,
        maximumSelection: group.maximumSelection
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Stock Management',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),

        // Date Picker and Search
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search Items',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
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
                  surfaceTintColor: Colors.black),
              child: Text(
                DateFormat('yyyy-MM-dd').format(_selectedDate),
                style:
                    TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
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
        ),
        const SizedBox(height: 20),

        // Stock Items List
        Expanded(
            child: _isStockLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredStockItems.isEmpty
                    ? const Center(child: Text('No stock items found'))
                    : ListView.builder(
                        itemCount: _filteredStockItems.length,
                        itemBuilder: (context, index) {
                          final item = _filteredStockItems[index];
                          return StockItemCard(
                            itemCode: item['item_code'] ?? '',
                            itemName: item['item_name'] ?? '',
                            currentQty: (item['actual_qty'] ?? 0).toDouble(),
                            reservedQty: (item['reserved_qty'] ?? 0).toDouble(),
                            availableQty:
                                (item['available_qty'] ?? 0).toDouble(),
                            value: (item['value'] ?? 0).toDouble(),
                            image: item['image'],
                            onManageStock: () => _showManageStockDialog([item]),
                          );
                        },
                      )),
      ],
    );
  }

  Widget _buildEmployeeManagementSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Employee Management',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),

        // Search and Refresh
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _employeeSearchController,
                decoration: const InputDecoration(
                  labelText: 'Search Employees',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  // Implement search functionality if needed
                },
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _isEmployeeLoading ? null : _loadEmployees,
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
        ),
        const SizedBox(height: 20),

        // Employees List
        Expanded(
          child: _isEmployeeLoading
              ? const Center(child: CircularProgressIndicator())
              : _employees.isEmpty
                  ? const Center(child: Text('No employees found'))
                  : ListView.builder(
                      itemCount: _employees.length,
                      itemBuilder: (context, index) {
                        final employee = _employees[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: ListTile(
                            leading: const Icon(Icons.person),
                            title: Text(employee['employee_name'] ?? 'Unknown'),
                            subtitle: Text(employee['designation'] ?? ''),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (employee['status'] == 'Active')
                                  IconButton(
                                    icon: const Icon(Icons.login,
                                        color: Colors.green),
                                    onPressed: () {
                                      final authState = ref.read(authProvider);
                                      authState.when(
                                        authenticated: (sid,
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
                                            printKitchenOrder) {
                                          _employeeCheckIn(
                                              employee['name'], branch);
                                        },
                                        initial: () {},
                                        unauthenticated: () {},
                                      );
                                    },
                                    tooltip: 'Check In',
                                  ),
                                if (employee['status'] == 'Checked In')
                                  IconButton(
                                    icon: const Icon(Icons.logout,
                                        color: Colors.red),
                                    onPressed: () {
                                      final authState = ref.read(authProvider);
                                      authState.when(
                                        authenticated: (sid,
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
                                            printKitchenOrder) {
                                          _employeeCheckOut(
                                              employee['name'], branch);
                                        },
                                        initial: () {},
                                        unauthenticated: () {},
                                      );
                                    },
                                    tooltip: 'Check Out',
                                  ),
                                Text(
                                  employee['status'] ?? 'Unknown',
                                  style: TextStyle(
                                    color: employee['status'] == 'Checked In'
                                        ? Colors.green
                                        : Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
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
        authenticated: (sid,
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
            printKitchenOrder) async {
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

  void _showManageStockDialog(List<Map<String, dynamic>> items) {
    final item = items.first;
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
                  color: Colors.grey[600], fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: qtyController,
              decoration: const InputDecoration(
                labelText: 'Quantity to Add/Remove',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
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
              if (qtyController.text.isEmpty) {
                Fluttertoast.showToast(
                  msg: 'Please enter quantity',
                  gravity: ToastGravity.BOTTOM,
                  backgroundColor: Colors.orange,
                  textColor: Colors.white,
                );
                return;
              }

              final quantity = double.parse(qtyController.text);
              if (quantity <= 0) {
                Fluttertoast.showToast(
                  msg: 'Quantity must be greater than 0',
                  gravity: ToastGravity.BOTTOM,
                  backgroundColor: Colors.orange,
                  textColor: Colors.white,
                );
                return;
              }

              // Check if reduction would result in negative stock
              if (_wouldResultInNegativeStock(items.first, quantity)) {
                Fluttertoast.showToast(
                  msg: 'Cannot reduce more than current quantity',
                  gravity: ToastGravity.BOTTOM,
                  backgroundColor: Colors.red,
                  textColor: Colors.white,
                );
              } else {
                Navigator.pop(context);
                _reduceStock(items, quantity);
              }
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
              if (qtyController.text.isEmpty) {
                Fluttertoast.showToast(
                  msg: 'Please enter quantity',
                  gravity: ToastGravity.BOTTOM,
                  backgroundColor: Colors.orange,
                  textColor: Colors.white,
                );
                return;
              }

              final quantity = double.parse(qtyController.text);
              if (quantity <= 0) {
                Fluttertoast.showToast(
                  msg: 'Quantity must be greater than 0',
                  gravity: ToastGravity.BOTTOM,
                  backgroundColor: Colors.orange,
                  textColor: Colors.white,
                );
                return;
              }

              Navigator.pop(context);
              _stockInItems(items, quantity);
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

  Future<void> _reduceStock(
    List<Map<String, dynamic>> items,
    double quantityToRemove, // Changed from String to double
  ) async {
    try {
      setState(() => _isStockLoading = true);
      final authState = ref.read(authProvider);

      await authState.when(
        authenticated: (sid,
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
            printKitchenOrder) async {
          final itemsToAdjust = items.map((item) {
            // Calculate the new quantity by subtracting from current
            final currentQty = (item['actual_qty'] ?? 0).toDouble();
            final newQty = currentQty - quantityToRemove;

            // Ensure we don't go below zero
            final adjustedQty = newQty >= 0 ? newQty : 0;

            return {
              'item_code': item['item_code'],
              'actual_qty': adjustedQty,
            };
          }).toList();

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
            await _loadStockItems(); // Refresh the list
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
    } finally {
      setState(() => _isStockLoading = false);
    }
  }

  // Add this helper function to check if reduction would result in negative stock
  bool _wouldResultInNegativeStock(
      Map<String, dynamic> item, double quantityToRemove) {
    final currentQty = (item['actual_qty'] ?? 0).toDouble();
    return (currentQty - quantityToRemove) < 0;
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
