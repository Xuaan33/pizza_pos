import 'dart:typed_data';

import 'package:flutter/foundation.dart';

class PosHexGenerator {
  static String generatePurchaseHexMessage(
      String transactionId, double amount, String m1Value) {
    final formattedAmount = _formatAmount(amount);

    if (transactionId.length != 20) {
      throw ArgumentError('TRANSACTION_ID must be exactly 20 characters');
    }
    if (formattedAmount.length != 12) {
      throw ArgumentError(
          'AMOUNT must be exactly 12 characters after formatting');
    }
    if (m1Value.length != 2) {
      throw ArgumentError('M1_VALUE must be exactly 2 characters');
    }

    const originalMessage =
        "02 00 92 36 30 30 30 30 30 30 30 30 30 31 30 32 30 30 30 30 1C "
        "30 30 00 20 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 1C "
        "36 36 00 20 41 42 42 32 30 32 33 30 36 32 30 30 39 30 39 31 32 39 37 31 1C "
        "34 30 00 12 30 30 30 30 30 30 30 30 30 31 30 30 1C "
        "4D 31 00 02 30 30 1C "
        "03 DA";

    var tokens = originalMessage.split(' ');

    tokens = _normalizePresentationHeader(tokens, expectedLength: 24);
    tokens =
        _updateField(tokens, ['1C', '36', '36', '00', '20'], transactionId, 20);
    tokens = _updateField(
        tokens, ['1C', '34', '30', '00', '12'], formattedAmount, 12);
    tokens = _updateField(tokens, ['1C', '4D', '31', '00', '02'], m1Value, 2);
    tokens = _updateLrc(tokens);

    return tokens.join(' ');
  }

  static String generateVoidHexMessage({
    required String transactionId,
    required String invoiceNumber,
  }) {
    if (transactionId.length != 20) {
      throw ArgumentError('TRANSACTION_ID must be exactly 20 characters');
    }
    if (invoiceNumber.length != 6) {
      throw ArgumentError('INVOICE_NUMBER must be exactly 6 characters');
    }

    const originalMessage =
        "02 00 85 36 30 30 30 30 30 30 30 30 30 31 30 34 30 30 30 30 "
        "1C 30 30 00 20 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 "
        "1C 36 36 00 20 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 31 32 33 "
        "1C 36 35 00 06 30 30 30 30 37 30 "
        "1C 30 39 00 01 30 "
        "1C 03 93";

    var tokens = originalMessage.split(' ');

    tokens = _normalizePresentationHeader(tokens, expectedLength: 24);
    tokens =
        _updateField(tokens, ['1C', '36', '36', '00', '20'], transactionId, 20);
    tokens =
        _updateField(tokens, ['1C', '36', '35', '00', '06'], invoiceNumber, 6);
    tokens = _updateField(tokens, ['1C', '30', '39', '00', '01'], "1",
        1); // Set receipt required to '1'
    tokens = _updateLrc(tokens);

    return tokens.join(' ');
  }

  static String _formatAmount(double amount) {
    final value = (amount * 100).round();
    return value.toString().padLeft(12, '0');
  }

  static String generateVoidWalletQrHexMessage(String transactionId,{String? extendedInvoiceNumber}) {
    try {
      // Validate transaction ID length
      if (transactionId.length != 20) {
        throw ArgumentError("Transaction ID must be exactly 20 characters long.");
      }

      // Ensure extended invoice number is provided
      if (extendedInvoiceNumber == null || extendedInvoiceNumber.isEmpty) {
        throw ArgumentError("Extended Invoice Number must be provided.");
      }

      // Base HEX message template for VOID QR
      const originalMessage = "02 00 98 36 30 30 30 30 30 30 30 30 30 31 30 34 30 30 30 30 "
          "1C 30 30 00 20 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 "
          "1C 36 36 00 20 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 31 32 33 "
          "1C 36 35 00 06 30 30 30 30 37 30 "
          "1C 30 39 00 01 30 "
          "1C 03 93";

      // Step 1: Tokenize and normalize presentation header (Field 00)
      List<String> tokens = originalMessage.split(' ');
      tokens = _normalizePresentationHeader(tokens, expectedLength: 24);

      // Step 2: Update transaction ID in Field 66
      tokens = _updateField(
        tokens,
        ["1C", "36", "36", "00", "20"],
        transactionId,
        20,
      );

      // Step 3: Pad or truncate extended invoice number to exactly 25 characters
      final paddedExtendedInvoice = extendedInvoiceNumber.padLeft(25).substring(0, 25);

      // Step 4: Try to update Field 67 (Extended Invoice Number). If not found, insert it before ETX.
      try {
        tokens = _updateField(
          tokens,
          ["1C", "36", "37", "00", "25"],
          paddedExtendedInvoice,
          25,
        );
      } catch (e) {
        if (e.toString().contains("not found")) {
          // Find the position to insert Field 67 (before ETX field)
          int insertPos = _findLastSeparatorBeforeEtx(tokens);
          
          // Insert field 67 with encoded data before ETX
          final fieldHeader = ["1C", "36", "37", "00", "25"];
          final fieldData = _asciiToHexTokens(paddedExtendedInvoice);
          
          tokens = [
            ...tokens.sublist(0, insertPos),
            ...fieldHeader,
            ...fieldData,
            ...tokens.sublist(insertPos)
          ];
        } else {
          rethrow;
        }
      }

      // Step 5: Remove Field 65 (Invoice Number, not used for QR)
      tokens = _removeField(tokens, ["1C", "36", "35", "00", "06"], 6);

      // Step 6: Remove Field 09 (Receipt Required flag)
      tokens = _removeField(tokens, ["1C", "30", "39", "00", "01"], 1);

      // Step 7: Recalculate and update LRC
      tokens = _updateLrc(tokens);

      // Return final space-separated message
      return tokens.join(' ');
    } catch (e) {
      throw Exception("Error generating Void message: ${e.toString()}");
    }
  }

  static int _findLastSeparatorBeforeEtx(List<String> tokens) {
    // Look for the ETX field (1C 03) and find the separator before it
    for (int i = tokens.length - 3; i >= 0; i--) {
      if (tokens[i] == "1C" && tokens[i + 1] == "03") {
        return i;
      }
    }
    throw ArgumentError("ETX field not found in message");
  }

  static List<String> _removeField(
      List<String> tokens, List<String> pattern, int dataLength) {
    final normalizedPattern = pattern.map((e) => e.toUpperCase()).toList();
    final normalizedTokens = tokens.map((e) => e.toUpperCase()).toList();

    int? idx;
    for (var i = 0;
        i < normalizedTokens.length - normalizedPattern.length;
        i++) {
      var match = true;
      for (var j = 0; j < normalizedPattern.length; j++) {
        if (normalizedTokens[i + j] != normalizedPattern[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        idx = i;
        break;
      }
    }

    if (idx == null) {
      return tokens; // Field not found, return original tokens
    }

    // Remove the field header and data
    return [
      ...tokens.sublist(0, idx),
      ...tokens.sublist(idx + pattern.length + dataLength)
    ];
  }

  static List<String> _normalizePresentationHeader(List<String> tokens,
      {required int expectedLength}) {
    int? firstSep;
    int? secondSep;

    for (var i = 0; i < tokens.length; i++) {
      if (tokens[i].toUpperCase() == '1C') {
        if (firstSep == null) {
          firstSep = i;
        } else {
          secondSep = i;
          break;
        }
      }
    }

    if (firstSep == null || secondSep == null) {
      throw ArgumentError('Presentation header markers (1C) not found');
    }

    final currentLength = secondSep - (firstSep + 1);
    List<String> headerTokens;

    if (currentLength < expectedLength) {
      headerTokens = tokens.sublist(firstSep + 1, secondSep) +
          List.filled(expectedLength - currentLength, '30');
    } else {
      headerTokens =
          tokens.sublist(firstSep + 1, firstSep + 1 + expectedLength);
    }

    return tokens.sublist(0, firstSep + 1) +
        headerTokens +
        tokens.sublist(secondSep);
  }

  static List<String> _updateField(List<String> tokens, List<String> pattern,
      String newValueStr, int expectedLength) {
    // Normalize case for comparison
    final normalizedPattern = pattern.map((e) => e.toUpperCase()).toList();
    final normalizedTokens = tokens.map((e) => e.toUpperCase()).toList();

    int? idx;
    for (var i = 0;
        i < normalizedTokens.length - normalizedPattern.length;
        i++) {
      var match = true;
      for (var j = 0; j < normalizedPattern.length; j++) {
        if (normalizedTokens[i + j] != normalizedPattern[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        idx = i;
        break;
      }
    }

    if (idx == null) {
      debugPrint('Tokens: ${tokens.join(' ')}');
      debugPrint('Searching for: ${pattern.join(' ')}');
      throw ArgumentError(
          "Field with pattern '${pattern.join(' ')}' not found in message");
    }

    final dataIndex = idx + pattern.length;
    final newTokens = _asciiToHexTokens(newValueStr);

    if (newTokens.length != expectedLength) {
      throw ArgumentError(
          'New value must produce exactly $expectedLength tokens');
    }

    final newList = List<String>.from(tokens);
    newList.replaceRange(dataIndex, dataIndex + expectedLength, newTokens);
    return newList;
  }

  static List<String> _asciiToHexTokens(String input) {
    return input.codeUnits
        .map((c) => c.toRadixString(16).toUpperCase().padLeft(2, '0'))
        .toList();
  }

  static List<String> _updateLrc(List<String> tokens) {
    final dataTokens =
        tokens.sublist(1, tokens.length - 1); // exclude STX and old LRC
    final dataBytes = Uint8List.fromList(
        dataTokens.map((token) => int.parse(token, radix: 16)).toList());
    final lrc = _computeLrc(dataBytes);
    final updated = List<String>.from(tokens);
    updated[updated.length - 1] =
        lrc.toRadixString(16).toUpperCase().padLeft(2, '0');
    return updated;
  }

  static int _computeLrc(Uint8List bytes) {
    int lrc = 0x00;
    for (final b in bytes) {
      lrc ^= b;
    }
    return lrc;
  }
}
