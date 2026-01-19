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

  // Printer Configuration
  String _selectedPrinterType = 'network'; // 'network' or 'usb'
  List<Map<String, dynamic>> _networkPrinters = [];
  bool _isLoadingPrinters = false;
  bool _isTestingPrinter = false;
  String? _testingPrinterId;

// Add/Edit Printer Dialog Controllers
  final TextEditingController _printerNameController = TextEditingController();
  final TextEditingController _printerIpController = TextEditingController();
  final TextEditingController _printerPortController =
      TextEditingController(text: '9100');
  bool _printReceipt = true;
  bool _printOrder = false;
  String? _editingPrinterId;

  // Employee Management
  List<Map<String, dynamic>> _employees = [];
  bool _isEmployeeLoading = false;
  TextEditingController _employeeSearchController = TextEditingController();

  List<String> _getSections(String tier) {
    final sections = [
      'POS Opening & Closing',
      'POS Card Terminal',
      'Printer Configuration',
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
    _loadSavedConfig();
    _loadEmployees();
    _loadConfiguration();
    _loadPrinterConfiguration();
    _loadNetworkPrinters();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _employeeSearchController.dispose();
    _printerNameController.dispose();
    _printerIpController.dispose();
    _printerPortController.dispose();
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

  // ============== Printer Configuration Methods ==============

  Future<void> _loadPrinterConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedPrinterType =
          prefs.getString('printer_connection_type') ?? 'network';
    });
  }

  Future<void> _loadNetworkPrinters() async {
    setState(() => _isLoadingPrinters = true);

    try {
      final printers = await ReceiptPrinter.getConfiguredPrinters();
      setState(() {
        _networkPrinters = printers
            .map((p) => <String, dynamic>{
                  'id': p.id,
                  'name': p.name,
                  'ip': p.ip,
                  'port': p.port,
                  'isEnabled': p.isEnabled,
                  'printReceipt': p.printReceipt,
                  'printOrder': p.printOrder,
                })
            .toList();
      });
    } catch (e) {
      debugPrint('Error loading printers: $e');
    } finally {
      setState(() => _isLoadingPrinters = false);
    }
  }

  Future<void> _savePrinterConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('printer_connection_type', _selectedPrinterType);

      Fluttertoast.showToast(
        msg: "Printer configuration saved successfully",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Failed to save printer configuration: $e",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  Future<void> _saveNetworkPrinters() async {
    try {
      final printers = _networkPrinters
          .map((p) => PrinterConfig(
                id: p['id'],
                name: p['name'],
                ip: p['ip'],
                port: p['port'],
                isEnabled: p['isEnabled'],
                printReceipt: p['printReceipt'],
                printOrder: p['printOrder'],
              ))
          .toList();

      await ReceiptPrinter.saveConfiguredPrinters(printers);

      Fluttertoast.showToast(
        msg: "Printers saved successfully",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Failed to save printers: $e",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  Future<void> _testPrinter(String printerId) async {
    setState(() {
      _isTestingPrinter = true;
      _testingPrinterId = printerId;
    });

    try {
      final printer = _networkPrinters.firstWhere((p) => p['id'] == printerId);
      final printerConfig = PrinterConfig(
        id: printer['id'],
        name: printer['name'],
        ip: printer['ip'],
        port: printer['port'],
        isEnabled: printer['isEnabled'],
        printReceipt: printer['printReceipt'],
        printOrder: printer['printOrder'],
      );

      final result =
          await ReceiptPrinter.testNetworkPrinterConnection(printerConfig);

      Fluttertoast.showToast(
        msg: result
            ? '${printer['name']}: Connection successful!'
            : '${printer['name']}: Connection failed',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: result ? Colors.green : Colors.red,
        textColor: Colors.white,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Test failed: $e',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      setState(() {
        _isTestingPrinter = false;
        _testingPrinterId = null;
      });
    }
  }

  Future<void> _testAllPrinters() async {
    setState(() => _isTestingPrinter = true);

    try {
      final results = await ReceiptPrinter.testAllPrinters();

      final successful = results.values.where((v) => v).length;
      final total = results.length;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Test Results'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tested $total printer(s)'),
              Text('✅ Successful: $successful'),
              Text('❌ Failed: ${total - successful}'),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              ...results.entries.map((entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          entry.value ? Icons.check_circle : Icons.cancel,
                          color: entry.value ? Colors.green : Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(entry.key)),
                      ],
                    ),
                  )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Test failed: $e',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      setState(() => _isTestingPrinter = false);
    }
  }

  void _showAddEditPrinterDialog({Map<String, dynamic>? printer}) {
    final isEditing = printer != null;

    if (isEditing) {
      _editingPrinterId = printer['id'];
      _printerNameController.text = printer['name'];
      _printerIpController.text = printer['ip'];
      _printerPortController.text = printer['port'].toString();
      _printReceipt = printer['printReceipt'];
      _printOrder = printer['printOrder'];
    } else {
      _editingPrinterId = null;
      _printerNameController.clear();
      _printerIpController.clear();
      _printerPortController.text = '9100';

      // Default behavior based on number of existing printers
      if (_networkPrinters.isEmpty) {
        // First printer: default to both
        _printReceipt = true;
        _printOrder = true;
      } else {
        // Additional printers: default to receipt only
        _printReceipt = true;
        _printOrder = false;
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            isEditing ? 'Edit Printer' : 'Add Printer',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.white,
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _printerNameController,
                  decoration: const InputDecoration(
                    labelText: 'Printer Name',
                    hintText: 'e.g., Kitchen Printer',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _printerIpController,
                  decoration: const InputDecoration(
                    labelText: 'IP Address',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _printerPortController,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    hintText: '9100',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 20),
                const Text(
                  'What should this printer print?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text(
                    'Print Receipt',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text('Customer receipts'),
                  value: _printReceipt,
                  onChanged: (value) {
                    setState(() {
                      _printReceipt = value ?? true;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  title: const Text(
                    'Print Order',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text('Kitchen orders'),
                  value: _printOrder,
                  onChanged: (value) {
                    setState(() {
                      _printOrder = value ?? false;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                if (!_printReceipt && !_printOrder)
                  Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning,
                            color: Colors.orange[700], size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'At least one option must be selected',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
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
              onPressed: (!_printReceipt && !_printOrder)
                  ? null
                  : () {
                      _savePrinter(isEditing);
                      Navigator.pop(context);
                    },
              child: Text(
                isEditing ? 'Save' : 'Add',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _savePrinter(bool isEditing) {
    final name = _printerNameController.text.trim();
    final ip = _printerIpController.text.trim();
    final port = int.tryParse(_printerPortController.text.trim()) ?? 9100;

    if (name.isEmpty || ip.isEmpty) {
      Fluttertoast.showToast(
        msg: "Please fill in all fields",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    if (!_printReceipt && !_printOrder) {
      Fluttertoast.showToast(
        msg: "Please select at least one print option",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    if (isEditing) {
      // Update existing printer
      final index =
          _networkPrinters.indexWhere((p) => p['id'] == _editingPrinterId);
      if (index != -1) {
        setState(() {
          _networkPrinters[index] = <String, dynamic>{
            'id': _editingPrinterId!,
            'name': name,
            'ip': ip,
            'port': port,
            'isEnabled': _networkPrinters[index]['isEnabled'],
            'printReceipt': _printReceipt,
            'printOrder': _printOrder,
          };
        });
      }
    } else {
      // Add new printer
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      setState(() {
        _networkPrinters.add(<String, dynamic>{
          'id': id,
          'name': name,
          'ip': ip,
          'port': port,
          'isEnabled': true,
          'printReceipt': _printReceipt,
          'printOrder': _printOrder,
        });
      });
    }

    _saveNetworkPrinters();
  }

  void _deletePrinter(String printerId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Printer'),
        content: const Text('Are you sure you want to delete this printer?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                _networkPrinters.removeWhere((p) => p['id'] == printerId);
              });
              _saveNetworkPrinters();
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _togglePrinterEnabled(String printerId, bool enabled) {
    final index = _networkPrinters.indexWhere((p) => p['id'] == printerId);
    if (index != -1) {
      setState(() {
        _networkPrinters[index]['isEnabled'] = enabled;
      });
      _saveNetworkPrinters();
    }
  }

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
          final response = await MainLayout.of(context)!
              .safeExecuteAPICall(() => PosService().getEmployees());
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
      final response = await MainLayout.of(context)!
          .safeExecuteAPICall(() => PosService().employeeCheckIn(
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
      final response = await MainLayout.of(context)!
          .safeExecuteAPICall(() => PosService().employeeCheckOut(
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
      case 'Printer Configuration':
        return _buildPrinterConfigurationSection();
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

  Widget _buildPrinterConfigurationSection() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Printer Configuration',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (_selectedPrinterType == 'network' &&
                  _networkPrinters.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: _isTestingPrinter ? null : _testAllPrinters,
                  icon: _isTestingPrinter
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.playlist_add_check, size: 20),
                  label: const Text('Test All'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _buildPrinterTypeSelector(),
          const SizedBox(height: 20),
          if (_selectedPrinterType == 'network')
            _buildNetworkPrintersManagement()
          else
            _buildUsbPrinterInfo(),
        ],
      ),
    );
  }

  Widget _buildPrinterTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Printer Connection Type',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ListTile(
                title: const Text('Network (Wireless)'),
                subtitle: const Text('Multiple printers via WiFi/LAN'),
                leading: Radio<String>(
                  value: 'network',
                  groupValue: _selectedPrinterType,
                  onChanged: (value) {
                    setState(() => _selectedPrinterType = value!);
                    _savePrinterConfig();
                  },
                ),
              ),
            ),
            Expanded(
              child: ListTile(
                title: const Text('USB (Wired)'),
                subtitle: const Text('Direct USB connection'),
                leading: Radio<String>(
                  value: 'usb',
                  groupValue: _selectedPrinterType,
                  onChanged: (value) {
                    setState(() => _selectedPrinterType = value!);
                    _savePrinterConfig();
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNetworkPrintersManagement() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Network Printers',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            ElevatedButton.icon(
              onPressed: () => _showAddEditPrinterDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Add Printer', style: TextStyle(fontWeight: FontWeight.bold),),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_isLoadingPrinters)
          const Center(child: CircularProgressIndicator())
        else if (_networkPrinters.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              children: [
                Icon(Icons.print_disabled, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No printers configured',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Click "Add Printer" to configure your first printer',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _networkPrinters.length,
            itemBuilder: (context, index) {
              final printer = _networkPrinters[index];
              return _buildPrinterCard(printer);
            },
          ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Text(
                    'Printer Configuration Tips',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTipItem(
                  'If you have only 1 printer, check both Receipt and Order'),
              _buildTipItem(
                  'For multiple printers, configure each one\'s purpose'),
              _buildTipItem('Receipt printers: Print customer receipts'),
              _buildTipItem('Order printers: Print kitchen orders'),
              _buildTipItem(
                  'Multiple printers with same purpose will print simultaneously'),
              _buildTipItem(
                  'Default port is usually 9100 for ESC/POS printers'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPrinterCard(Map<String, dynamic> printer) {
    final isEnabled = printer['isEnabled'] as bool;
    final isTesting = _isTestingPrinter && _testingPrinterId == printer['id'];
    final printReceipt = printer['printReceipt'] as bool;
    final printOrder = printer['printOrder'] as bool;

    return Card(
      margin: const EdgeInsets.only(bottom: 12, left: 5, right: 5),
      elevation: isEnabled ? 2 : 0,
      color: isEnabled
          ? const Color.fromARGB(255, 253, 252, 239)
          : Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.print, color: Colors.blue[700]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        printer['name'],
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isEnabled ? Colors.black : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${printer['ip']}:${printer['port']}',
                        style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isEnabled,
                  onChanged: (value) =>
                      _togglePrinterEnabled(printer['id'], value),
                  activeColor: Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Print capabilities chips
            Wrap(
              spacing: 8,
              children: [
                if (printReceipt)
                  Chip(
                    label: const Text('Receipt'),
                    avatar: const Icon(Icons.receipt_long, size: 16),
                    backgroundColor: Colors.green[50],
                    labelStyle: TextStyle(
                        color: Colors.green[700],
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                if (printOrder)
                  Chip(
                    label: const Text('Order'),
                    avatar: const Icon(Icons.restaurant, size: 16),
                    backgroundColor: Colors.orange[50],
                    labelStyle: TextStyle(
                        color: Colors.orange[700],
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
              ],
            ),

            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        isTesting ? null : () => _testPrinter(printer['id']),
                    icon: isTesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_find, size: 16),
                    label: Text(
                      isTesting ? 'Testing...' : 'Test',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _showAddEditPrinterDialog(printer: printer),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text(
                      'Edit',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _deletePrinter(printer['id']),
                    icon: const Icon(Icons.delete, size: 16),
                    label: const Text(
                      'Delete',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsbPrinterInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'USB Printer Settings',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.usb, color: Colors.grey[700], size: 32),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'USB Printer Mode',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildTipItem('Connect your thermal printer via USB cable'),
              _buildTipItem(
                  'The app will automatically detect the USB printer'),
              _buildTipItem('USB printer will print both receipts and orders'),
              _buildTipItem('For multiple printers, use Network mode'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTipItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 16)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
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
                              final dateTime =
                                  DateTime.parse(checkedInOutAt.toString());
                              formattedTime = DateFormat('hh:mm a MM/dd/yy')
                                  .format(dateTime);
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
                                  if (employee['designation'] != null &&
                                      employee['designation']
                                          .toString()
                                          .isNotEmpty)
                                    Text(employee['designation']),
                                  if (formattedTime.isNotEmpty)
                                    Text(
                                      isCheckedIn
                                          ? 'Clocked in: $formattedTime'
                                          : 'Clocked out: $formattedTime',
                                      style: TextStyle(
                                        color: isCheckedIn
                                            ? Colors.green
                                            : Colors.grey,
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
          final response = await MainLayout.of(context)!
              .safeExecuteAPICall(() => PosService().requestClosingVoucher(
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
