import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shiok_pos_android_app/service/pos_service.dart';
import 'package:image/image.dart' as img;

class ReceiptPrinter {
  static Future<bool> canPrint() async {
    try {
      final printers = await Printing.listPrinters();
      return printers.isNotEmpty;
    } catch (e) {
      print('Printer detection error: $e');
      return false;
    }
  }

  static Future<Printer?> getDefaultPrinter() async {
    try {
      final printers = await Printing.listPrinters();
      if (printers.isEmpty) {
        return null;
      }
      
      // Look for a default printer
      final defaultPrinter = printers.firstWhere(
        (printer) => printer.isDefault,
        orElse: () => printers.first,
      );
      
      return defaultPrinter;
    } catch (e) {
      print('Error getting default printer: $e');
      return null;
    }
  }

  static Future<void> printReceipt(Uint8List bytes, {bool isPdf = true}) async {
    try {
      // Check if printers are available first
      final canPrint = await ReceiptPrinter.canPrint();
      if (!canPrint) {
        throw Exception('No printer detected');
      }

      // Get the default printer
      final printer = await getDefaultPrinter();
      if (printer == null) {
        throw Exception('No printer available');
      }

      if (isPdf) {
        await Printing.directPrintPdf(
          printer: printer,
          onLayout: (PdfPageFormat format) async => bytes,
          usePrinterSettings: true,
        );
      } else {
        // Convert image to PDF for printing
        final pdf = pw.Document();
        final image = img.decodeImage(bytes);
        
        if (image != null) {
          pdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              build: (pw.Context context) {
                return pw.Center(
                  child: pw.Image(
                    pw.MemoryImage(bytes),
                    fit: pw.BoxFit.contain,
                  ),
                );
              },
            ),
          );
          
          final pdfBytes = await pdf.save();
          await Printing.directPrintPdf(
            printer: printer,
            onLayout: (PdfPageFormat format) async => pdfBytes,
            usePrinterSettings: true,
          );
        } else {
          throw Exception('Failed to decode image');
        }
      }
    } catch (e) {
      print('Printing error: $e');
      throw Exception('Failed to print receipt: $e');
    }
  }

  static Future<void> printReceiptFromApi(String orderName) async {
    try {
      final imageBytes = await PosService().printReceipt(orderName);
      await printReceipt(imageBytes, isPdf: false);
    } catch (e) {
      print('Print receipt error: $e');
      rethrow;
    }
  }

  static Future<void> printReceiptAndKitchenOrder(String orderName) async {
    try {
      // Use the combined method from PosService that prints both
      final printResults = await PosService().printReceiptAndKitchenOrder(
        orderName: orderName,
        shouldPrintKitchenOrder: true,
      );

      // Print receipt
      if (printResults.containsKey('receipt')) {
        await printReceipt(printResults['receipt']!, isPdf: false);
      }

      // Print kitchen order if available
      if (printResults.containsKey('kitchen_order')) {
        await printReceipt(printResults['kitchen_order']!, isPdf: false);
      }
    } catch (e) {
      print('Print receipt and kitchen order error: $e');
      rethrow;
    }
  }

  static Future<void> autoPrintReceipt(
    BuildContext context, 
    String orderName, {
    bool shouldPrintKitchenOrder = false,
  }) async {
    try {
      // Check if printer is available first
      final canPrint = await ReceiptPrinter.canPrint();
      if (!canPrint) {
        Fluttertoast.showToast(
          msg: "No printer detected",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.orange,
          textColor: Colors.white,
        );
        return;
      }

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
              Text(
                shouldPrintKitchenOrder 
                  ? 'Printing receipt and kitchen order...'
                  : 'Printing receipt...',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );

      if (shouldPrintKitchenOrder) {
        await printReceiptAndKitchenOrder(orderName);
      } else {
        await printReceiptFromApi(orderName);
      }

      Navigator.of(context).pop();

      Fluttertoast.showToast(
        msg: shouldPrintKitchenOrder 
          ? "Receipt and kitchen order printed successfully"
          : "Receipt printed successfully",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );
    } catch (e) {
      Navigator.of(context).pop();
      Fluttertoast.showToast(
        msg: shouldPrintKitchenOrder 
          ? "Failed to print receipt and kitchen order: $e"
          : "Failed to print receipt: $e",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  // Keep the original showPrintDialog for manual printing if needed
  static Future<void> showPrintDialog(
    BuildContext context, 
    String orderName, {
    bool shouldPrintKitchenOrder = false,
  }) async {
    // This can remain the same as your original implementation
    // or you can redirect to autoPrintReceipt if you prefer
    await autoPrintReceipt(context, orderName, 
      shouldPrintKitchenOrder: shouldPrintKitchenOrder);
  }
}