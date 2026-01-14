import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiok_pos_android_app/components/main_layout.dart';
import 'package:shiok_pos_android_app/components/no_stretch_scroll_behavior.dart';
import 'package:shiok_pos_android_app/components/pos_terminal_manager.dart';
import 'package:shiok_pos_android_app/components/receipt_printer.dart';
import 'package:shiok_pos_android_app/dialogs/closing_entry_dialog.dart';
import 'package:shiok_pos_android_app/dialogs/opening_entry_dialog.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/screens/Settings%20Screen/item.dart';
import 'package:shiok_pos_android_app/screens/Settings%20Screen/item_group.dart';
import 'package:shiok_pos_android_app/screens/Settings%20Screen/stock.dart';
import 'package:shiok_pos_android_app/screens/Settings%20Screen/variant.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';
import 'package:usb_serial/usb_serial.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SettingsScreen> createState() => SettingsScreenState();
}

class SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _selectedIndex = 0;
  bool _isPosConnected = false;
  bool _isTesting = false;
  bool _isSaving = false; // Add this for save button loading state
  final TextEditingController _ipController =
      TextEditingController(text: '192.168.');
  final TextEditingController _portController =
      TextEditingController(text: '8800');
  bool isLoading = true;
  bool isRequired = false;
  int optionRequiredNo = 1;
  List<Map<String, dynamic>> confirmedOptions = [];
  bool _isLoadingClosing = false;

  // For debug reporting
  final List<Map<String, dynamic>> _connectionLogs = [];
  bool _isGeneratingReport = false;

  // Pos Terminal Management
  final PosTerminalManager _terminalManager = PosTerminalManager();
  List<UsbDevice> _availableUsbDevices = [];
  UsbDevice? _selectedUsbDevice;
  String _selectedConnectionType = 'TCP/IP'; // 'TCP/IP' or 'Wired'

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
      'Finished Goods',
    ];

    // Only add Employee Management for tier 2 and above
    if (tier.toLowerCase() != 'tier 1') {
      sections.add('Employee Management');
    }

    return sections;
  }

  @override
  void initState() {
    super.initState();
    _employeeSearchController = TextEditingController();
    _loadSavedConfig(); // Load saved config when widget initializes
    _loadEmployees(); // Load employees when screen initializes
    _loadConfiguration();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _employeeSearchController.dispose();
    super.dispose();
  }

  void showSection(int index) {
    if (mounted) {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  Future<void> _loadSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ipController.text = prefs.getString('pos_ip') ?? '192.168';
      _portController.text = prefs.getInt('pos_port')?.toString() ?? '8800';
    });
  }

  // Future<void> _loadConfiguration() async {
  //   await _terminalManager.loadConfiguration();
  //   setState(() {
  //     _selectedConnectionType =
  //         _terminalManager.currentConnectionType == ConnectionType.tcpip
  //             ? 'TCP/IP'
  //             : 'Wired';
  //     _isPosConnected = _terminalManager.isConnected;
  //   });

  //   if (_selectedConnectionType == 'Wired') {
  //     await _discoverUsbDevices();
  //   }
  // }

  Future<void> _discoverUsbDevices() async {
    try {
      final devices = await _terminalManager.discoverUsbDevices();
      setState(() {
        _availableUsbDevices = devices;
        if (devices.isNotEmpty && _selectedUsbDevice == null) {
          _selectedUsbDevice = devices.first;
          _terminalManager.setUsbDevice(devices.first);
        }
      });
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Error discovering USB devices: $e',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  // Future<void> _saveConfig() async {
  //   setState(() => _isSaving = true);

  //   try {
  //     if (_selectedConnectionType == 'TCP/IP') {
  //       final posIp = _ipController.text.trim();
  //       final posPort = int.tryParse(_portController.text.trim()) ?? 8800;

  //       if (posIp.isEmpty) {
  //         throw Exception('Please enter IP Address');
  //       }

  //       await _terminalManager.saveConfiguration(
  //         type: ConnectionType.tcpip,
  //         ip: posIp,
  //         port: posPort,
  //       );

  //       Fluttertoast.showToast(
  //         msg: "TCP/IP configuration saved successfully",
  //         gravity: ToastGravity.BOTTOM,
  //         backgroundColor: Colors.green,
  //         textColor: Colors.white,
  //       );
  //     } else {
  //       if (_selectedUsbDevice == null) {
  //         throw Exception('Please select a USB device');
  //       }

  //       await _terminalManager.saveConfiguration(
  //         type: ConnectionType.wired,
  //         usbDevice: _selectedUsbDevice,
  //       );

  //       Fluttertoast.showToast(
  //         msg: "USB configuration saved successfully",
  //         gravity: ToastGravity.BOTTOM,
  //         backgroundColor: Colors.green,
  //         textColor: Colors.white,
  //       );
  //     }
  //   } catch (e) {
  //     Fluttertoast.showToast(
  //       msg: "Failed to save configuration: $e",
  //       gravity: ToastGravity.BOTTOM,
  //       backgroundColor: Colors.red,
  //       textColor: Colors.white,
  //     );
  //   } finally {
  //     setState(() => _isSaving = false);
  //   }
  // }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);

    try {
      final result = await _terminalManager.testConnection();

      setState(() {
        _isPosConnected = result;
        _isTesting = false;
      });

      Fluttertoast.showToast(
        msg: result
            ? 'Connection successful! ${_terminalManager.getConnectionStatusMessage()}'
            : 'Connection failed',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: result ? Colors.green : Colors.red,
        textColor: Colors.white,
      );
    } catch (e) {
      setState(() => _isTesting = false);
      Fluttertoast.showToast(
        msg: 'Connection error: $e',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  // In the _buildConnectionTypeSelector() method, modify the Wired connection radio button:
  Widget _buildConnectionTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Connection Type',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ListTile(
                title: const Text('TCP/IP (Wireless)'),
                leading: Radio<String>(
                  value: 'TCP/IP',
                  groupValue: _selectedConnectionType,
                  onChanged: (value) async {
                    setState(() {
                      _selectedConnectionType = value!;
                      _isPosConnected = false;
                    });
                  },
                ),
              ),
            ),
            Expanded(
              child: ListTile(
                title: const Text('USB (Wired)'),
                leading: Radio<String>(
                  value: 'Wired',
                  groupValue: _selectedConnectionType,
                  onChanged: (value) async {
                    // Show toast message that wired connection is not supported
                    Fluttertoast.showToast(
                      msg: 'Wired connection currently not supported',
                      gravity: ToastGravity.BOTTOM,
                      backgroundColor: Colors.orange,
                      textColor: Colors.white,
                    );
                    // Don't change the selection
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

// Comment out the entire _buildWiredConnectionForm() method:
/*
Widget _buildWiredConnectionForm() {
  return Column(
    children: [
      const Text(
        'USB/Wired Connection',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 10),

      // USB Device Selector
      if (_availableUsbDevices.isEmpty)
        Column(
          children: [
            const Text(
              'No USB devices found. Please connect your POS terminal and refresh.',
              style: TextStyle(color: Colors.orange),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _discoverUsbDevices,
              icon: const Icon(Icons.refresh),
              label: const Text('Discover USB Devices'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        )
      else
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select USB Device:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<UsbDevice>(
                value: _selectedUsbDevice,
                isExpanded: true,
                underline: const SizedBox(),
                items: _availableUsbDevices.map((device) {
                  return DropdownMenuItem<UsbDevice>(
                    value: device,
                    child: Text(
                      '${device.productName ?? 'Unknown Device'} (VID: ${device.vid}, PID: ${device.pid})',
                    ),
                  );
                }).toList(),
                onChanged: (device) {
                  setState(() {
                    _selectedUsbDevice = device;
                    _terminalManager.setUsbDevice(device!);
                  });
                },
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _discoverUsbDevices,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh Devices'),
            ),
          ],
        ),

      const SizedBox(height: 16),
      const Text(
        'Make sure your POS terminal is properly connected via USB cable.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 16),

      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isSaving ? null : _saveConfig,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2196F3),
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
                  'Save USB Configuration',
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
*/

// Comment out the _saveWiredConfig() method:
/*
Future<void> _saveWiredConfig() async {
  setState(() => _isSaving = true);

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('connection_type', 'Wired');

    Fluttertoast.showToast(
      msg: "Wired configuration saved successfully",
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
*/

// In the _loadConfiguration() method, comment out the wired connection discovery:
  Future<void> _loadConfiguration() async {
    await _terminalManager.loadConfiguration();
    setState(() {
      _selectedConnectionType =
          _terminalManager.currentConnectionType == ConnectionType.tcpip
              ? 'TCP/IP'
              : 'Wired';
      _isPosConnected = _terminalManager.isConnected;
    });

    // Comment out USB device discovery
    /*
  if (_selectedConnectionType == 'Wired') {
    await _discoverUsbDevices();
  }
  */
  }

// Comment out the _discoverUsbDevices() method:
/*
Future<void> _discoverUsbDevices() async {
  try {
    final devices = await _terminalManager.discoverUsbDevices();
    setState(() {
      _availableUsbDevices = devices;
      if (devices.isNotEmpty && _selectedUsbDevice == null) {
        _selectedUsbDevice = devices.first;
        _terminalManager.setUsbDevice(devices.first);
      }
    });
  } catch (e) {
    Fluttertoast.showToast(
      msg: 'Error discovering USB devices: $e',
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.red,
      textColor: Colors.white,
    );
  }
}
*/

// In the _saveConfig() method, modify to only handle TCP/IP:
  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);

    try {
      // Only handle TCP/IP connection
      if (_selectedConnectionType == 'TCP/IP') {
        final posIp = _ipController.text.trim();
        final posPort = int.tryParse(_portController.text.trim()) ?? 8800;

        if (posIp.isEmpty) {
          throw Exception('Please enter IP Address');
        }

        await _terminalManager.saveConfiguration(
          type: ConnectionType.tcpip,
          ip: posIp,
          port: posPort,
        );

        Fluttertoast.showToast(
          msg: "TCP/IP configuration saved successfully",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      } else {
        // Show message for wired connection
        throw Exception('Wired connection currently not supported');
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Failed to save configuration: $e",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

// In the build method section for POS Terminal, modify to only show TCP/IP form:
// In _buildPosTerminalSection() method, replace the connection forms section with:
// Show different connection forms based on selection

  Widget _buildConnectionStatusIndicator() {
    return Row(
      children: [
        Icon(
          _isPosConnected ? Icons.check_circle : Icons.error,
          color: _isPosConnected ? Colors.green : Colors.red,
          size: 24,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isPosConnected ? 'Connected' : 'Not Connected',
                style: TextStyle(
                  fontSize: 16,
                  color: _isPosConnected ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_isPosConnected)
                Text(
                  _terminalManager.getConnectionStatusMessage(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _selectedConnectionType == 'TCP/IP'
                ? Colors.blue.withOpacity(0.1)
                : Colors.purple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _selectedConnectionType == 'TCP/IP'
                  ? Colors.blue
                  : Colors.purple,
            ),
          ),
          child: Text(
            _selectedConnectionType,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _selectedConnectionType == 'TCP/IP'
                  ? Colors.blue
                  : Colors.purple,
            ),
          ),
        ),
      ],
    );
  }

// Save wired configuration
  Future<void> _saveWiredConfig() async {
    setState(() => _isSaving = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('connection_type', 'Wired');

      Fluttertoast.showToast(
        msg: "Wired configuration saved successfully",
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
          cashDrawerPinNeeded,
          cashDrawerPin,
        ) async {
          final response = await MainLayout.of(context)!.safeExecuteAPICall(() => PosService().getEmployees());
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
      final response = await MainLayout.of(context)!.safeExecuteAPICall(() => PosService().employeeCheckIn(
        employee: employeeId,
        branch: branch,
      ));

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
      final response = await MainLayout.of(context)!.safeExecuteAPICall(() => PosService().employeeCheckOut(
        employee: employeeId,
        branch: branch,
      ));

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
        openingDate,
        itemsGroups,
        baseUrl,
        merchantId,
        printMerchantReceiptCopy,
        enableFiuu,
        cashDrawerPinNeeded,
        cashDrawerPin,
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
      case 'Finished Goods':
        return _buildStockManagementSection();
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
        Text(
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
        const SizedBox(height: 30),
        Text(
          'Cash Drawer',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 30),
        _buildCashDrawerButton(),
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

        // Connection Type Selection
        _buildConnectionTypeSelector(),
        const SizedBox(height: 20),

        _buildConnectionStatusIndicator(),
        const SizedBox(height: 20),

        // Show different connection forms based on selection
        if (_selectedConnectionType == 'TCP/IP')
          _buildTcpConnectionForm()
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(
              children: [
                Icon(Icons.info_outline, color: Colors.orange, size: 48),
                SizedBox(height: 16),
                Text(
                  'Wired Connection Not Supported',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  'Please use TCP/IP connection for now. Wired connection support will be added in a future update.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),

        const SizedBox(height: 20),
        _buildTestButton(),
        const SizedBox(height: 20),

        // Add debug report button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isGeneratingReport ? null : _generateDebugReport,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: _isGeneratingReport
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Generate Debug Report',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
        ),

        // Show recent connection attempts
        if (_connectionLogs.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text(
            'Recent Connection Attempts:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ..._connectionLogs.reversed
              .take(3)
              .map((log) => Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        log['success'] == true
                            ? Icons.check_circle
                            : Icons.error,
                        color:
                            log['success'] == true ? Colors.green : Colors.red,
                      ),
                      title: Text(
                        log['message'] ?? 'Unknown',
                        style: TextStyle(
                          color: log['success'] == true
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                      subtitle: Text(
                        '${log['timestamp']?.split('.').first ?? ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ))
              .toList(),
        ],
      ],
    );
  }

  Widget _buildItemGroupSection() {
    return ScrollConfiguration(
      behavior: NoStretchScrollBehavior(),
      child: SingleChildScrollView(
        child: Container(
          height: MediaQuery.of(context).size.height,
          child: ItemGroupManagement(),
        ),
      ),
    );
  }

  Widget _buildItemSection() {
    return ScrollConfiguration(
      behavior: NoStretchScrollBehavior(),
      child: SingleChildScrollView(
        child: Container(
          height: MediaQuery.of(context).size.height,
          child: ItemManagement(),
        ),
      ),
    );
  }

  Widget _buildStockManagementSection() {
    return ScrollConfiguration(
      behavior: NoStretchScrollBehavior(),
      child: SingleChildScrollView(
        child: Container(
          height: MediaQuery.of(context).size.height,
          child: StockManagementSection(),
        ),
      ),
    );
  }

  Widget _buildVariantSection() {
    return ScrollConfiguration(
      behavior: NoStretchScrollBehavior(),
      child: SingleChildScrollView(
        child: Container(
          height: MediaQuery.of(context).size.height,
          child: VariantSection(),
        ),
      ),
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
                  : ScrollConfiguration(
                      behavior: NoStretchScrollBehavior(),
                      child: ListView.builder(
                        itemCount: _employees.length,
                        itemBuilder: (context, index) {
                          final employee = _employees[index];
                          debugPrint("EMPLOYEE TEST: $employee");
                          
                          final status = employee['status'] ?? 'Unknown';
                          final isCheckedIn = status == 'Checked In';
                          final checkedInOutAt = employee['checked_in_out_at'];
                          
                          // Format the timestamp
                          String formattedTime = '';
                          if (checkedInOutAt != null) {
                            try {
                              final dateTime = DateTime.parse(checkedInOutAt.toString());
                              formattedTime = DateFormat('hh:mm a MM/dd/yy').format(dateTime);
                            } catch (e) {
                              formattedTime = checkedInOutAt.toString();
                            }
                          }
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            child: ListTile(
                              leading: const Icon(Icons.person),
                              title:
                                  Text(employee['employee_name'] ?? 'Unknown'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (employee['designation'] != null && employee['designation'].toString().isNotEmpty)
                                    Text(employee['designation']),
                                  if (formattedTime.isNotEmpty)
                                    Text(
                                      isCheckedIn 
                                          ? 'Clocked in: $formattedTime'
                                          : 'Clocked out: $formattedTime',
                                      style: TextStyle(
                                        color: isCheckedIn ? Colors.green : Colors.grey,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.login,
                                        color: Colors.green),
                                    onPressed: () {
                                      final authState = ref.read(authProvider);
                                      authState.when(
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
                                          cashDrawerPinNeeded,
                                          cashDrawerPin,
                                        ) {
                                          _employeeCheckIn(
                                              employee['name'], branch);
                                        },
                                        initial: () {},
                                        unauthenticated: () {},
                                      );
                                    },
                                    tooltip: 'Check In',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.logout,
                                        color: Colors.red),
                                    onPressed: () {
                                      final authState = ref.read(authProvider);
                                      authState.when(
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
                                          cashDrawerPinNeeded,
                                          cashDrawerPin,
                                        ) {
                                          _employeeCheckOut(
                                              employee['name'], branch);
                                        },
                                        initial: () {},
                                        unauthenticated: () {},
                                      );
                                    },
                                    tooltip: 'Check Out',
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
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
    final isDisabled = !hasOpening || _isLoadingClosing;

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
        child: _isLoadingClosing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                isDisabled && !_isLoadingClosing
                    ? 'No Opening Entry'
                    : 'Create Closing Entry',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Future<void> _showClosingEntryDialog() async {
    setState(() => _isLoadingClosing = true);
    try {
      final authState = ref.read(authProvider);

      await authState.whenOrNull(
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
          cashDrawerPinNeeded,
          cashDrawerPin,
        ) async {
          final response = await MainLayout.of(context)!.safeExecuteAPICall(() => PosService().requestClosingVoucher(
            posProfile: posProfile,
          ));

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
    } finally {
      if (mounted) {
        setState(() => _isLoadingClosing = false);
      }
    }
  }

  Widget _buildCashDrawerButton() {
    final isOpeningCashDrawer = ref.read(authProvider).maybeWhen(
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
            cashDrawerPinNeeded,
            cashDrawerPin,
          ) {
            return cashDrawerPinNeeded == 1;
          },
          orElse: () => false,
        );
    return SizedBox(
      width: 435,
      child: ElevatedButton(
        onPressed: isOpeningCashDrawer == true
            ? _showCashDrawerPinDialog
            : ReceiptPrinter.openCashDrawer,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFE732A0),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Text(
          'Open Cash Drawer',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Future<void> _showCashDrawerPinDialog() async {
    final TextEditingController pinController = TextEditingController();
    bool isLoading = false;
    final cashDrawerPin = ref.read(authProvider).maybeWhen(
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
            cashDrawerPinNeeded,
            cashDrawerPin,
          ) {
            return cashDrawerPin;
          },
          orElse: () => false,
        );

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text(
                'Enter Cash Drawer PIN',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Please enter 4-digit PIN to open cash drawer',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: pinController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      letterSpacing: 8,
                    ),
                    decoration: const InputDecoration(
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    onChanged: (value) {
                      if (value.length == 4) {
                        FocusScope.of(context).unfocus();
                      }
                    },
                  ),
                  if (isLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 16.0),
                      child: CircularProgressIndicator(),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          Navigator.pop(context);
                        },
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          final enteredPin = pinController.text.trim();

                          if (enteredPin.length != 4) {
                            Fluttertoast.showToast(
                              msg: 'Please enter 4-digit PIN',
                              gravity: ToastGravity.BOTTOM,
                              backgroundColor: Colors.red,
                              textColor: Colors.white,
                            );
                            return;
                          }

                          setState(() => isLoading = true);

                          await Future.delayed(
                              const Duration(milliseconds: 500));

                          if (enteredPin == cashDrawerPin) {
                            Navigator.pop(context);
                            await ReceiptPrinter.openCashDrawer();
                          } else {
                            setState(() => isLoading = false);
                            Fluttertoast.showToast(
                              msg: 'Invalid PIN. Please try again.',
                              gravity: ToastGravity.BOTTOM,
                              backgroundColor: Colors.red,
                              textColor: Colors.white,
                            );
                          }
                        },
                  child: const Text(
                    'Confirm',
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

  Widget _buildTcpConnectionForm() {
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
        TextField(
          controller: _portController,
          decoration: const InputDecoration(
            labelText: 'Port Number',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.numbers),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(5),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveConfig,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
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
                    'Save TCP/IP Configuration',
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
        onPressed: _isTesting ? null : _testConnection,
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
            : Text(
                'Test ${_selectedConnectionType} Connection',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Future<bool> _isHostReachable(String ip) async {
    try {
      final result = await InternetAddress.lookup(ip);
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
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

  Future<void> _generateDebugReport() async {
    setState(() => _isGeneratingReport = true);

    try {
      final String timestamp =
          DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final String fileName = 'POS_Debug_Report_$timestamp.txt';

      final String report = await _buildDebugReport();

      // Save to Documents folder
      await _saveToDocumentsFolder(fileName, report);
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Failed to save report: $e",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      setState(() => _isGeneratingReport = false);
    }
  }

  Future<void> _saveToDocumentsFolder(String fileName, String content) async {
    try {
      // For Android, we need to use the external storage public directory
      final Directory? externalDir = await getExternalStorageDirectory();

      if (externalDir == null) {
        throw Exception('Could not access device storage');
      }

      // Navigate to the actual public Documents folder
      // This path should be: /storage/emulated/0/Documents/
      final String publicDocumentsPath = externalDir.path.replaceAll(
          '/Android/data/com.nicholas.shiok_pos_android_app/files', '');

      final Directory publicDocumentsDir =
          Directory('$publicDocumentsPath/Documents');
      if (!await publicDocumentsDir.exists()) {
        await publicDocumentsDir.create(recursive: true);
      }

      // Create our POS Reports folder
      final Directory posReportsDir =
          Directory('${publicDocumentsDir.path}/POS Debug Reports');
      if (!await posReportsDir.exists()) {
        await posReportsDir.create(recursive: true);
      }

      // Save the file
      final File file = File('${posReportsDir.path}/$fileName');
      await file.writeAsString(content);

      // Show success with clear instructions
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 10),
                Text('Report Saved to Documents'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                      'The debug report has been saved to your public Documents folder.'),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Location:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Internal Storage → Documents → POS Debug Reports',
                          style: TextStyle(
                            color: Colors.green[800],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'File: $fileName',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'How to access:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _buildStep('1. Open your "Files" app'),
                  _buildStep('2. Go to "Internal storage"'),
                  _buildStep('3. Open "Documents" folder'),
                  _buildStep('4. Open "POS Debug Reports" folder'),
                  _buildStep('5. Find your file'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }

      debugPrint('=== DEBUG REPORT SAVED TO PUBLIC DOCUMENTS ===');
      debugPrint('Public Path: ${file.path}');
      debugPrint('============================================');
    } catch (e) {
      debugPrint('Error saving to public Documents: $e');
      // Fallback to showing in dialog
      await _showReportInDialog(content);
    }
  }

  Widget _buildStep(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Future<void> _showReportInDialog(String content) async {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Debug Report'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                content,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              Fluttertoast.showToast(msg: 'Full report copied to clipboard');
            },
            child: const Text('Copy All'),
          ),
        ],
      ),
    );
  }

  Future<String> _buildDebugReport() async {
    // Made async
    final buffer = StringBuffer();

    buffer.writeln('=== POS TERMINAL CONNECTION DEBUG REPORT ===');
    buffer.writeln('Generated: ${DateTime.now()}');
    buffer.writeln('App Version: 1.1.13');
    buffer.writeln('Platform: ${Platform.operatingSystem}');
    buffer.writeln('');

    // Configuration Details
    buffer.writeln('--- CONFIGURATION ---');
    buffer.writeln('IP Address: ${_ipController.text}');
    buffer.writeln('Port: ${_portController.text}');
    buffer.writeln(
        'Connection Status: ${_isPosConnected ? "Connected" : "Disconnected"}');
    buffer.writeln('');

    // Network Information
    buffer.writeln('--- NETWORK INFO ---');
    buffer.writeln(
        'Host Reachable: ${await _isHostReachable(_ipController.text.trim())}');
    buffer.writeln('');

    // Connection Logs
    buffer.writeln('--- CONNECTION ATTEMPTS (${_connectionLogs.length}) ---');
    if (_connectionLogs.isEmpty) {
      buffer.writeln('No connection attempts recorded');
    } else {
      for (int i = 0; i < _connectionLogs.length; i++) {
        final log = _connectionLogs[i];
        buffer.writeln('Attempt ${i + 1}: ${log['timestamp']}');
        buffer.writeln('  Status: ${log['success'] ? 'SUCCESS' : 'FAILED'}');
        buffer.writeln('  Message: ${log['message']}');
        if (log['error'] != null) {
          buffer.writeln('  Error: ${log['error']}');
        }
        if (log['response'] != null) {
          buffer.writeln('  Response: ${log['response']}');
        }
        buffer.writeln('');
      }
    }

    // Environment Details
    buffer.writeln('--- ENVIRONMENT ---');
    buffer.writeln('Flutter Version: ${Platform.version}');
    buffer.writeln('');

    // Troubleshooting Steps
    buffer.writeln('--- TROUBLESHOOTING STEPS ---');
    buffer.writeln('1. Verify POS terminal is powered on');
    buffer.writeln('2. Ensure device and POS terminal are on same network');
    buffer.writeln('3. Check firewall settings');
    buffer.writeln('4. Verify IP address and port configuration');
    buffer.writeln('5. Test with ping command from device');

    return buffer.toString();
  }
}