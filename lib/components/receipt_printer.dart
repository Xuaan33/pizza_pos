import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shiok_pos_android_app/service/pos_service.dart';
import 'package:image/image.dart' as img;

class ReceiptPrinter {
  static Future<void> printReceipt(Uint8List bytes, {bool isPdf = true}) async {
    try {
      if (isPdf) {
        await Printing.layoutPdf(
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
          await Printing.layoutPdf(
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

  static Future<void> showPrintDialog(
      BuildContext context, String orderName) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          backgroundColor: Colors.white,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Preparing receipt for printing...',
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
}