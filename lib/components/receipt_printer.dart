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

  static Future<void> printReceipt(Uint8List bytes, {bool isPdf = true}) async {
    try {
      if (isPdf) {
        // Use the print dialog instead of direct printing
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => bytes,
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
          // Use the print dialog instead of direct printing
          await Printing.layoutPdf(
            onLayout: (PdfPageFormat format) async => pdfBytes,
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

  static Future<void> printKitchenOrderOnly(String orderName) async {
    try {
      final kitchenOrderBytes = await PosService().printKitchenOrder(
        orderName: orderName,
      );
      await printReceipt(kitchenOrderBytes, isPdf: false);
      debugPrint('Kitchen order printed successfully');
    } catch (e) {
      debugPrint('Print kitchen order error: $e');
      // Don't rethrow - kitchen order printing failure shouldn't block the flow
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
                'Preparing receipt for printing...',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );

      // Only print receipt here (kitchen order is handled separately)
      await printReceiptFromApi(orderName);

      Navigator.of(context).pop();

      Fluttertoast.showToast(
        msg: "Receipt sent to print dialog",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );
    } catch (e) {
      Navigator.of(context).pop();
      Fluttertoast.showToast(
        msg: "Failed to prepare receipt: $e",
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
    await autoPrintReceipt(context, orderName);
  }
}
