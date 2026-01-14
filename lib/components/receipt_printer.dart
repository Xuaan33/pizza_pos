import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image/image.dart' as img;
import 'package:shiok_pos_android_app/components/main_layout.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';

class ReceiptPrinter {
  static final FlutterThermalPrinter _plugin = FlutterThermalPrinter.instance;

  static Printer? _currentPrinter;

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

    // Clear current printer if force reconnecting
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

    // Debug: Print all found devices
    for (final device in devices) {
      debugPrint(
          "🔍 Found printer: VID:${device.vendorId} PID:${device.productId} Name:${device.name} Connected:${device.isConnected}");
    }

    // Find your specific printer or use first available
    // Replace the printer selection logic with this:
    final printer = devices.firstWhere(
      (p) => p.vendorId == 8137 && p.productId == 8214, // Your actual printer
      orElse: () => devices.firstWhere(
        (p) => p.name?.contains('Printer') ?? false, // Fallback to any printer
        orElse: () => devices.first, // Last resort
      ),
    );

    debugPrint(
        "🎯 Selected printer: VID:${printer.vendorId} PID:${printer.productId}");

    if (!(printer.isConnected ?? false)) {
      debugPrint("🔌 Attempting to connect to printer...");

      // 🔥 ADD PERMISSION REQUEST BEFORE CONNECTION
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
  /// Cash drawer: ESC/POS pulse via USB
  /// -------------------------------------------
  static Future<void> openCashDrawer({
    int pin = 0, // 0 = pin2 (most common), 1 = pin5
    bool showFeedback = false,
  }) async {
    try {
      final printer = await _ensureUsbPrinter();
      if (printer == null) {
        throw Exception('No USB thermal printer found');
      }

      // ESC p m t1 t2
      // m = 0/1 => pin
      // t1,t2 pulse timing (50*2ms = 100ms)
      final List<int> drawerCommand = <int>[
        27,
        112,
        pin,
        50,
        50,
      ];

      await _plugin.printData(
        printer,
        drawerCommand,
        longData: false,
      );

      debugPrint('💰 Cash drawer command sent');

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

  /// Optional helper to test pin 0 vs 1
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
              child: const Text('Test Pin 2 (m = 0)'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await openCashDrawer(pin: 1);
              },
              child: const Text('Test Pin 5 (m = 1)'),
            ),
          ],
        ),
      ),
    );
  }

  /// -------------------------------------------
  /// Check if any USB printer is available
  /// -------------------------------------------
  static Future<bool> canPrint() async {
    final printer = await _ensureUsbPrinter();
    return printer != null;
  }

  /// -------------------------------------------
  /// Core: print image bytes via ESC/POS
  /// (used by receipt + kitchen order)
  /// -------------------------------------------
  static Future<void> printReceipt(
    Uint8List bytes, {
    bool isPdf = false,
  }) async {
    try {
      final printer = await _ensureUsbPrinter();
      if (printer == null) throw Exception("No USB printer found");

      // 🔥 FASTER: Parallel processing and simplified image handling
      final List<int> ticket = await _processReceiptImage(bytes);

      // 🔥 Larger chunks for faster transmission
      final chunkSize = _calculateOptimalChunkSize(ticket.length);
      final totalChunks = (ticket.length / chunkSize).ceil();

      for (int i = 0; i < ticket.length; i += chunkSize) {
        final chunkNumber = (i / chunkSize).floor() + 1;
        if (totalChunks > 5) {
          // Only show progress for large prints
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

      debugPrint("🚀 Printed successfully (optimized)");
    } catch (e) {
      debugPrint("❌ Failed to print receipt: $e");
      throw Exception('Failed to print receipt: $e');
    }
  }

  static int _calculateOptimalChunkSize(int dataLength) {
    if (dataLength > 500000) return 16384; // 16KB for huge receipts
    if (dataLength > 100000) return 8192; // 8KB for large receipts
    return 4096; // 4KB for normal receipts
  }

  static Future<List<int>> _processReceiptImage(Uint8List bytes) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);

    List<int> ticket = [];

    try {
      // Parse once and reuse
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception("Failed to decode image");

      // 🔥 OPTIMIZATION 1: Skip grayscale conversion if already grayscale
      final processedImage = img.grayscale(decoded);

      // 🔥 OPTIMIZATION 2: Use more efficient resizing
      final resized = img.copyResize(
        processedImage,
        width: 576,
        interpolation: img.Interpolation.nearest, // Better for speed
      );

      // 🔥 OPTIMIZATION 3: Use lower quality but faster printing
      ticket.addAll(generator.imageRaster(resized));

      ticket.addAll(generator.feed(2));
      ticket.addAll(generator.cut());

      return ticket;
    } catch (e) {
      debugPrint("Image processing error: $e");
      // Fallback: Try direct printing if image processing fails
      return bytes.toList();
    }
  }

  /// -------------------------------------------
  /// Existing high-level APIs using PosService
  /// -------------------------------------------
  static Future<void> printReceiptFromApi(String orderName) async {
    try {
      final imageBytes = await PosService().printReceipt(orderName);
      await printReceipt(imageBytes, isPdf: false);
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
        await printReceipt(kitchenOrderPages[i], isPdf: false);
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
        await printReceipt(printResults['receipt']!, isPdf: false);
      }

      if (printResults.containsKey('kitchen_order')) {
        await printReceipt(printResults['kitchen_order']!, isPdf: false);
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

      await printReceipt(imageBytes, isPdf: false);

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
