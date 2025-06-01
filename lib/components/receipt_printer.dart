import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shiok_pos_android_app/service/pos_service.dart';

class ReceiptPrinter {
  static Future<void> printReceipt(Uint8List pdfBytes) async {
    try {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        usePrinterSettings: true,
      );
    } catch (e) {
      print('Printing error: $e');
      throw Exception('Failed to print receipt: $e');
    }
  }

  static Future<void> printReceiptFromApi(String orderName) async {
    try {
      final pdfBytes = await PosService().printReceipt(orderName);
      await printReceipt(pdfBytes);
    } catch (e) {
      print('Print receipt error: $e');
      rethrow;
    }
  }

  static Future<void> showPrintDialog(BuildContext context, String orderName) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Preparing receipt for printing...'),
            ],
          ),
        ),
      );

      await printReceiptFromApi(orderName);

      Navigator.of(context).pop();
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Receipt sent to printer successfully')),
      );
    } catch (e) {
      Navigator.of(context).pop();
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Failed to print receipt: $e')),
      );
    }
  }
}