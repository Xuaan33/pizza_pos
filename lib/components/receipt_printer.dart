import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';
import 'dart:convert';

enum PrinterConnectionType {
  usbOnly,
  networkOnly,
  both,
}

class UsbPrinterConfig {
  final bool printReceipt;
  final bool printOrder;

  UsbPrinterConfig({
    this.printReceipt = true,
    this.printOrder = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'printReceipt': printReceipt,
      'printOrder': printOrder,
    };
  }

  factory UsbPrinterConfig.fromJson(Map<String, dynamic> json) {
    return UsbPrinterConfig(
      printReceipt: json['printReceipt'] ?? true,
      printOrder: json['printOrder'] ?? true,
    );
  }

  String get capabilities {
    if (printReceipt && printOrder) return 'Receipt & Order';
    if (printReceipt) return 'Receipt Only';
    if (printOrder) return 'Order Only';
    return 'None';
  }
}

class PrinterConfig {
  final String id;
  final String name;
  final String ip;
  final int port;
  final bool isEnabled;
  final bool printReceipt;
  final bool printOrder;

  PrinterConfig({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    this.isEnabled = true,
    this.printReceipt = true,
    this.printOrder = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ip': ip,
      'port': port,
      'isEnabled': isEnabled,
      'printReceipt': printReceipt,
      'printOrder': printOrder,
    };
  }

  factory PrinterConfig.fromJson(Map<String, dynamic> json) {
    return PrinterConfig(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      ip: json['ip'] ?? '',
      port: json['port'] ?? 9100,
      isEnabled: json['isEnabled'] ?? true,
      printReceipt: json['printReceipt'] ?? true,
      printOrder: json['printOrder'] ?? false,
    );
  }

  String get capabilities {
    if (printReceipt && printOrder) return 'Receipt & Order';
    if (printReceipt) return 'Receipt Only';
    if (printOrder) return 'Order Only';
    return 'None';
  }
}

class ReceiptPrinter {
  static final FlutterThermalPrinter _plugin = FlutterThermalPrinter.instance;

  static Printer? _currentPrinter;

  /// -------------------------------------------
  /// Get printer connection type from preferences
  /// -------------------------------------------
  static Future<PrinterConnectionType> _getPrinterConnectionType() async {
    final prefs = await SharedPreferences.getInstance();
    final type = prefs.getString('printer_connection_type') ?? 'network';
    
    switch (type) {
      case 'usb':
        return PrinterConnectionType.usbOnly;
      case 'network':
        return PrinterConnectionType.networkOnly;
      case 'both':
        return PrinterConnectionType.both;
      default:
        return PrinterConnectionType.networkOnly;
    }
  }

  /// -------------------------------------------
  /// Get USB printer configuration
  /// -------------------------------------------
  static Future<UsbPrinterConfig> getUsbPrinterConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final configJson = prefs.getString('usb_printer_config');
    
    if (configJson == null || configJson.isEmpty) {
      return UsbPrinterConfig(); // Default: both receipt and order
    }

    try {
      final configMap = json.decode(configJson);
      return UsbPrinterConfig.fromJson(configMap);
    } catch (e) {
      debugPrint('Error parsing USB printer config: $e');
      return UsbPrinterConfig();
    }
  }

  /// -------------------------------------------
  /// Save USB printer configuration
  /// -------------------------------------------
  static Future<void> saveUsbPrinterConfig(UsbPrinterConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final configJson = json.encode(config.toJson());
    await prefs.setString('usb_printer_config', configJson);
    debugPrint('✅ USB printer config saved: ${config.capabilities}');
  }

  /// -------------------------------------------
  /// Check if USB printing is enabled
  /// -------------------------------------------
  static Future<bool> isUsbEnabled() async {
    final connectionType = await _getPrinterConnectionType();
    return connectionType == PrinterConnectionType.usbOnly || 
           connectionType == PrinterConnectionType.both;
  }

  /// -------------------------------------------
  /// Check if Network printing is enabled
  /// -------------------------------------------
  static Future<bool> isNetworkEnabled() async {
    final connectionType = await _getPrinterConnectionType();
    return connectionType == PrinterConnectionType.networkOnly || 
           connectionType == PrinterConnectionType.both;
  }

  /// -------------------------------------------
  /// Check if USB should print this job type
  /// -------------------------------------------
  static Future<bool> shouldUsbPrint({required bool isReceipt}) async {
    final usbEnabled = await isUsbEnabled();
    if (!usbEnabled) return false;

    final config = await getUsbPrinterConfig();
    return isReceipt ? config.printReceipt : config.printOrder;
  }

  /// -------------------------------------------
  /// Get all configured network printers
  /// -------------------------------------------
  static Future<List<PrinterConfig>> getConfiguredPrinters() async {
    final prefs = await SharedPreferences.getInstance();
    final printersJson = prefs.getString('network_printers');
    
    if (printersJson == null || printersJson.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> printersList = json.decode(printersJson);
      return printersList.map((json) => PrinterConfig.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error parsing printers: $e');
      return [];
    }
  }

  /// -------------------------------------------
  /// Save configured printers
  /// -------------------------------------------
  static Future<void> saveConfiguredPrinters(List<PrinterConfig> printers) async {
    final prefs = await SharedPreferences.getInstance();
    final printersJson = json.encode(printers.map((p) => p.toJson()).toList());
    await prefs.setString('network_printers', printersJson);
  }

  /// -------------------------------------------
  /// Get printers by capability (receipt or order)
  /// -------------------------------------------
  static Future<List<PrinterConfig>> getPrintersByCapability({
    required bool forReceipt,
  }) async {
    final allPrinters = await getConfiguredPrinters();
    return allPrinters.where((p) {
      if (!p.isEnabled) return false;
      
      if (forReceipt) return p.printReceipt;
      return p.printOrder;
    }).toList();
  }

  /// -------------------------------------------
  /// Internal: find & connect a USB printer
  /// -------------------------------------------
  static Future<Printer?> _ensureUsbPrinter(
      {bool forceReconnect = false}) async {
    if (!forceReconnect &&
        _currentPrinter != null &&
        (_currentPrinter!.isConnected ?? false)) {
      return _currentPrinter;
    }

    if (forceReconnect) {
      if (_currentPrinter != null && (_currentPrinter!.isConnected ?? false)) {
        await _plugin.disconnect(_currentPrinter!);
      }
      _currentPrinter = null;
    }

    final completer = Completer<List<Printer>>();
    late StreamSubscription<List<Printer>> sub;

    sub = _plugin.devicesStream.listen((devices) {
      if (!completer.isCompleted) {
        completer.complete(devices);
        sub.cancel();
      }
    });

    await _plugin.getPrinters(connectionTypes: [ConnectionType.USB]);

    final devices = await completer.future.timeout(
      Duration(seconds: 10),
      onTimeout: () {
        if (!completer.isCompleted) {
          completer.complete([]);
        }
        return [];
      },
    );

    if (devices.isEmpty) {
      debugPrint("❌ No USB printers found");
      return null;
    }

    for (final device in devices) {
      debugPrint(
          "🔍 Found printer: VID:${device.vendorId} PID:${device.productId} Name:${device.name} Connected:${device.isConnected}");
    }

    final printer = devices.firstWhere(
      (p) => p.vendorId == 8137 && p.productId == 8214,
      orElse: () => devices.firstWhere(
        (p) => p.name?.contains('Printer') ?? false,
        orElse: () => devices.first,
      ),
    );

    debugPrint(
        "🎯 Selected printer: VID:${printer.vendorId} PID:${printer.productId}");

    if (!(printer.isConnected ?? false)) {
      debugPrint("🔌 Attempting to connect to printer...");

      debugPrint("🔑 Requesting USB permission...");
      final permissionGranted = await requestUsbPermission(printer);

      if (!permissionGranted) {
        debugPrint("❌ USB permission denied by user");
        return null;
      }

      debugPrint("✅ USB permission granted");

      final connected = await _plugin.connect(printer).timeout(
        Duration(seconds: 10),
        onTimeout: () {
          debugPrint("⏰ Connection timeout");
          return false;
        },
      );

      if (!connected) {
        debugPrint("❌ Failed to connect to printer");
        return null;
      }
    }

    _currentPrinter = printer;
    debugPrint(
        "✅ Connected to printer VID:${printer.vendorId} PID:${printer.productId}");

    return printer;
  }

  static Future<bool> requestUsbPermission(printer) async {
    try {
      final completer = Completer<List<Printer>>();
      late StreamSubscription<List<Printer>> sub;

      sub = _plugin.devicesStream.listen((devices) {
        if (!completer.isCompleted) {
          completer.complete(devices);
          sub.cancel();
        }
      });

      await _plugin.getPrinters(connectionTypes: [ConnectionType.USB]);
      final devices = await completer.future.timeout(Duration(seconds: 10));

      if (devices.isNotEmpty) {
        final printer = devices.first;
        final permissionGranted = await _plugin.connect(printer);
        return permissionGranted;
      }
      return false;
    } catch (e) {
      debugPrint("❌ USB permission request error: $e");
      return false;
    }
  }

  /// -------------------------------------------
  /// Network printer: Send data via TCP socket
  /// -------------------------------------------
  static Future<void> _printViaNetwork(
    List<int> bytes,
    PrinterConfig printer,
  ) async {
    Socket? socket;
    try {
      debugPrint("🌐 Connecting to ${printer.name} at ${printer.ip}:${printer.port}");

      socket = await Socket.connect(
        printer.ip,
        printer.port,
        timeout: Duration(seconds: 10),
      );

      debugPrint("✅ Connected to ${printer.name}");

      socket.add(bytes);
      await socket.flush();

      debugPrint("📄 Data sent to ${printer.name} successfully");

      await Future.delayed(Duration(milliseconds: 500));
    } catch (e) {
      debugPrint("❌ Network printer error (${printer.name}): $e");
      throw Exception('Failed to connect to ${printer.name}: $e');
    } finally {
      socket?.destroy();
      debugPrint("🔌 Connection to ${printer.name} closed");
    }
  }

  /// -------------------------------------------
  /// Print to multiple network printers
  /// -------------------------------------------
  static Future<Map<String, bool>> _printViaMultipleNetworkPrinters(
    List<int> bytes,
    List<PrinterConfig> printers,
  ) async {
    final results = <String, bool>{};
    
    if (printers.isEmpty) {
      debugPrint("⚠️ No network printers available for this print job");
      return results;
    }

    debugPrint("🖨️ Printing to ${printers.length} network printer(s): ${printers.map((p) => p.name).join(', ')}");
    
    final printTasks = printers.map((printer) async {
      try {
        await _printViaNetwork(bytes, printer);
        results[printer.name] = true;
        debugPrint("✅ Successfully printed to ${printer.name}");
      } catch (e) {
        results[printer.name] = false;
        debugPrint("❌ Failed to print to ${printer.name}: $e");
      }
    });

    await Future.wait(printTasks);
    
    final successful = results.values.where((v) => v).length;
    debugPrint("📊 Network print job completed: $successful/${printers.length} printers successful");
    
    return results;
  }

  /// -------------------------------------------
  /// Print to USB printer
  /// -------------------------------------------
  static Future<bool> _printViaUsb(List<int> ticket) async {
    try {
      final printer = await _ensureUsbPrinter();
      if (printer == null) {
        debugPrint("❌ No USB printer found");
        return false;
      }

      final chunkSize = _calculateOptimalChunkSize(ticket.length);
      final totalChunks = (ticket.length / chunkSize).ceil();

      debugPrint("📄 Printing to USB printer in $totalChunks chunks");

      for (int i = 0; i < ticket.length; i += chunkSize) {
        final chunkNumber = (i / chunkSize).floor() + 1;
        if (totalChunks > 5) {
          debugPrint("📄 Sending chunk $chunkNumber/$totalChunks...");
        }

        final end =
            i + chunkSize <= ticket.length ? i + chunkSize : ticket.length;
        await _plugin.printData(
          printer,
          Uint8List.fromList(ticket.sublist(i, end)),
          longData: true,
        );
      }

      debugPrint("✅ USB print job completed successfully");
      return true;
    } catch (e) {
      debugPrint("❌ USB print error: $e");
      return false;
    }
  }

  /// -------------------------------------------
  /// Test network printer connection
  /// -------------------------------------------
  static Future<bool> testNetworkPrinterConnection(PrinterConfig printer) async {
    Socket? socket;
    try {
      debugPrint("🧪 Testing ${printer.name} at ${printer.ip}:${printer.port}");

      socket = await Socket.connect(
        printer.ip,
        printer.port,
        timeout: Duration(seconds: 5),
      );

      debugPrint("✅ Network printer connection test successful");
      return true;
    } catch (e) {
      debugPrint("❌ Network printer connection test failed: $e");
      return false;
    } finally {
      socket?.destroy();
    }
  }

  /// -------------------------------------------
  /// Test all configured printers
  /// -------------------------------------------
  static Future<Map<String, bool>> testAllPrinters() async {
    final printers = await getConfiguredPrinters();
    final results = <String, bool>{};

    for (final printer in printers) {
      if (printer.isEnabled) {
        results[printer.name] = await testNetworkPrinterConnection(printer);
      }
    }

    return results;
  }

  /// -------------------------------------------
  /// Cash drawer: ESC/POS pulse via USB or Network
  /// -------------------------------------------
  static Future<void> openCashDrawer({
    int pin = 0,
    bool showFeedback = false,
  }) async {
    try {
      final connectionType = await _getPrinterConnectionType();

      final List<int> drawerCommand = <int>[
        27,
        112,
        pin,
        50,
        50,
      ];

      bool usbSuccess = false;
      bool networkSuccess = false;

      // Try USB if enabled
      if (connectionType == PrinterConnectionType.usbOnly || 
          connectionType == PrinterConnectionType.both) {
        try {
          final printer = await _ensureUsbPrinter();
          if (printer != null) {
            await _plugin.printData(
              printer,
              drawerCommand,
              longData: false,
            );
            usbSuccess = true;
            debugPrint('💰 Cash drawer command sent via USB');
          }
        } catch (e) {
          debugPrint('❌ USB cash drawer error: $e');
        }
      }

      // Try Network if enabled
      if (connectionType == PrinterConnectionType.networkOnly || 
          connectionType == PrinterConnectionType.both) {
        try {
          final printers = await getPrintersByCapability(forReceipt: true);
          if (printers.isNotEmpty) {
            await _printViaNetwork(drawerCommand, printers.first);
            networkSuccess = true;
            debugPrint('💰 Cash drawer command sent via Network');
          }
        } catch (e) {
          debugPrint('❌ Network cash drawer error: $e');
        }
      }

      if (!usbSuccess && !networkSuccess) {
        throw Exception('Failed to open cash drawer on any printer');
      }

      if (showFeedback) {
        Fluttertoast.showToast(
          msg: "Cash drawer opened",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      }
    } catch (e) {
      debugPrint('❌ Open cash drawer error: $e');
      Fluttertoast.showToast(
        msg: "Failed to open cash drawer: $e",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  static Future<void> openCashDrawerWithDialog(BuildContext context) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text(
                'Opening cash drawer...',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );

      await openCashDrawer(showFeedback: false);

      Navigator.of(context).pop();

      Fluttertoast.showToast(
        msg: "Cash drawer opened successfully",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );
    } catch (e) {
      Navigator.of(context).pop();
      Fluttertoast.showToast(
        msg: "Failed to open cash drawer: $e",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  static Future<void> testCashDrawerPins(BuildContext context) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Test Cash Drawer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Try each pin to see which one opens the drawer.'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await openCashDrawer(pin: 0);
              },
              child: const Text('Test Pin 0 (Pin 2 - Most Common)'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await openCashDrawer(pin: 1);
              },
              child: const Text('Test Pin 1 (Pin 5)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// -------------------------------------------
  /// Core: print image bytes via ESC/POS
  /// Prints to USB and/or Network based on configuration
  /// -------------------------------------------
  static Future<void> printReceipt(
    Uint8List bytes, {
    bool isPdf = false,
    bool isReceipt = true,
  }) async {
    try {
      final connectionType = await _getPrinterConnectionType();

      // Process receipt image once
      final List<int> ticket = await _processReceiptImage(bytes);

      bool usbSuccess = false;
      bool networkSuccess = false;
      String errorMessages = '';

      // Check if USB should print this job type
      final shouldPrintUsb = await shouldUsbPrint(isReceipt: isReceipt);

      // Print to USB if enabled AND configured for this job type
      if ((connectionType == PrinterConnectionType.usbOnly || 
           connectionType == PrinterConnectionType.both) && shouldPrintUsb) {
        debugPrint("🖨️ Printing to USB printer (${isReceipt ? 'Receipt' : 'Order'})...");
        try {
          usbSuccess = await _printViaUsb(ticket);
        } catch (e) {
          errorMessages += 'USB: $e\n';
          debugPrint("❌ USB print failed: $e");
        }
      } else if (connectionType == PrinterConnectionType.usbOnly || 
                 connectionType == PrinterConnectionType.both) {
        debugPrint("⏭️ Skipping USB printer (not configured for ${isReceipt ? 'receipts' : 'orders'})");
      }

      // Print to Network if enabled
      if (connectionType == PrinterConnectionType.networkOnly || 
          connectionType == PrinterConnectionType.both) {
        debugPrint("🖨️ Printing to Network printer(s) (${isReceipt ? 'Receipt' : 'Order'})...");
        try {
          final printers = await getPrintersByCapability(forReceipt: isReceipt);
          
          if (printers.isNotEmpty) {
            final results = await _printViaMultipleNetworkPrinters(ticket, printers);
            
            final successful = results.values.where((v) => v).length;
            final failed = results.values.where((v) => !v).length;
            
            if (successful > 0) {
              networkSuccess = true;
            }
            
            if (failed > 0) {
              final failedPrinters = results.entries
                  .where((e) => !e.value)
                  .map((e) => e.key)
                  .join(', ');
              errorMessages += 'Network failed: $failedPrinters\n';
              
              if (successful > 0) {
                Fluttertoast.showToast(
                  msg: "Printed to $successful/${printers.length} network printers. Failed: $failedPrinters",
                  gravity: ToastGravity.BOTTOM,
                  backgroundColor: Colors.orange,
                  textColor: Colors.white,
                  toastLength: Toast.LENGTH_LONG,
                );
              }
            }
          } else {
            final type = isReceipt ? 'receipt' : 'order';
            debugPrint('⚠️ No network $type printers configured');
          }
        } catch (e) {
          errorMessages += 'Network: $e\n';
          debugPrint("❌ Network print failed: $e");
        }
      }

      // Check if at least one method succeeded
      if (!usbSuccess && !networkSuccess) {
        throw Exception('Print failed on all configured printers:\n$errorMessages');
      }

      // Show success message
      List<String> successMethods = [];
      if (usbSuccess) successMethods.add('USB');
      if (networkSuccess) successMethods.add('Network');
      
      debugPrint("🚀 Print job completed successfully via: ${successMethods.join(' & ')}");

    } catch (e) {
      debugPrint("❌ Failed to print: $e");
      throw Exception('Failed to print: $e');
    }
  }

  static int _calculateOptimalChunkSize(int dataLength) {
    if (dataLength > 500000) return 16384;
    if (dataLength > 100000) return 8192;
    return 4096;
  }

  static Future<List<int>> _processReceiptImage(Uint8List bytes) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);

    List<int> ticket = [];

    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception("Failed to decode image");

      final processedImage = img.grayscale(decoded);

      final resized = img.copyResize(
        processedImage,
        width: 576,
        interpolation: img.Interpolation.nearest,
      );

      ticket.addAll(generator.imageRaster(resized));

      ticket.addAll(generator.feed(2));
      ticket.addAll(generator.cut());

      return ticket;
    } catch (e) {
      debugPrint("Image processing error: $e");
      return bytes.toList();
    }
  }

  /// -------------------------------------------
  /// High-level APIs using PosService
  /// -------------------------------------------
  static Future<void> printReceiptFromApi(String orderName) async {
    try {
      final imageBytes = await PosService().printReceipt(orderName);
      await printReceipt(imageBytes, isPdf: false, isReceipt: true);
    } catch (e) {
      debugPrint('Print receipt error: $e');
      rethrow;
    }
  }

  static Future<void> printKitchenOrderOnly(String orderName) async {
    try {
      debugPrint('🖨️ Printing kitchen order for: $orderName');

      final kitchenOrderPages = await PosService().printKitchenOrder(
        orderName: orderName,
      );

      for (int i = 0; i < kitchenOrderPages.length; i++) {
        await printReceipt(
          kitchenOrderPages[i], 
          isPdf: false, 
          isReceipt: false,
        );
        debugPrint(
          '✅ Printed kitchen order page ${i + 1}/${kitchenOrderPages.length}',
        );
      }

      debugPrint(
        '🎉 Kitchen order printed successfully - ${kitchenOrderPages.length} page(s)',
      );
    } catch (e) {
      debugPrint('❌ Print kitchen order error: $e');
      final errorString = e.toString();

      if (errorString.contains('No additional items to print') ||
          (errorString.contains('"success":false') &&
              errorString.contains('No additional items')) ||
          (errorString.contains('HTTP 400') &&
              errorString.contains('No additional items'))) {
        debugPrint(
          'ℹ️ No additional items to print for kitchen order - this is normal',
        );
        return;
      }

      debugPrint('⚠️ Other kitchen order printing error, but continuing flow');
    }
  }

  static Future<void> printReceiptAndKitchenOrder(String orderName) async {
    try {
      final printResults = await PosService().printReceiptAndKitchenOrder(
        orderName: orderName,
        shouldPrintKitchenOrder: true,
      );

      if (printResults.containsKey('receipt')) {
        await printReceipt(
          printResults['receipt']!, 
          isPdf: false, 
          isReceipt: true,
        );
      }

      if (printResults.containsKey('kitchen_order')) {
        await printReceipt(
          printResults['kitchen_order']!, 
          isPdf: false, 
          isReceipt: false,
        );
      }
    } catch (e) {
      debugPrint('Print receipt and kitchen order error: $e');
      rethrow;
    }
  }

  static Future<void> autoPrintReceipt(
    BuildContext context,
    String orderName, {
    bool shouldPrintKitchenOrder = false,
  }) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Printing receipt...',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );

      await printReceiptFromApi(orderName);

      Navigator.of(context).pop();

      Fluttertoast.showToast(
        msg: "Receipt printed successfully",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );
    } catch (e) {
      Navigator.of(context).pop();
      Fluttertoast.showToast(
        msg: "Failed to print receipt: $e",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  static Future<void> printSelectedKitchenOrder(
    String posInvoice,
    List<String> selectedItems,
  ) async {
    try {
      debugPrint('🖨️ Printing selected kitchen order for: $posInvoice');
      debugPrint('📋 Selected items: ${selectedItems.join(", ")}');

      final imageBytes = await PosService().printSelectedKitchenOrder(
        posInvoice: posInvoice,
        items: selectedItems,
      );

      if (imageBytes.isEmpty) {
        throw Exception('No image data received from server');
      }

      debugPrint('✅ Received image data: ${imageBytes.length} bytes');

      await printReceipt(imageBytes, isPdf: false, isReceipt: false);

      debugPrint('✅ Selected kitchen order printed successfully');
    } catch (e) {
      debugPrint('❌ Print selected kitchen order error: $e');

      final errorMsg = e.toString();
      if (errorMsg.contains('FormatException') ||
          errorMsg.contains('Unexpected character')) {
        throw Exception(
          'Server returned invalid response format. Please check the API endpoint.',
        );
      } else if (errorMsg.contains('No image data')) {
        throw Exception('No printable content received from server.');
      } else if (errorMsg.contains('HTTP 4')) {
        throw Exception(
          'Server error: Invalid request or kitchen station configuration.',
        );
      } else if (errorMsg.contains('HTTP 5')) {
        throw Exception('Server error: Please try again later.');
      } else {
        rethrow;
      }
    }
  }

  static Future<void> showPrintDialog(
    BuildContext context,
    String orderName, {
    bool shouldPrintKitchenOrder = false,
  }) async {
    await autoPrintReceipt(context, orderName);
  }
}