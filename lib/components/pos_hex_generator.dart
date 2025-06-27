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
      throw ArgumentError('AMOUNT must be exactly 12 characters after formatting');
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
    tokens = _updateField(tokens, ['1C', '36', '36', '00', '20'], transactionId, 20);
    tokens = _updateField(tokens, ['1C', '34', '30', '00', '12'], formattedAmount, 12);
    tokens = _updateField(tokens, ['1C', '4D', '31', '00', '02'], m1Value, 2);
    tokens = _updateLrc(tokens);

    return tokens.join(' ');
  }

  static String _formatAmount(double amount) {
    final value = (amount * 100).round();
    return value.toString().padLeft(12, '0');
  }

  static List<String> _normalizePresentationHeader(List<String> tokens, {required int expectedLength}) {
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
      headerTokens = tokens.sublist(firstSep + 1, firstSep + 1 + expectedLength);
    }

    return tokens.sublist(0, firstSep + 1) + headerTokens + tokens.sublist(secondSep);
  }

  static List<String> _updateField(
    List<String> tokens, List<String> pattern, String newValueStr, int expectedLength) {
  
  // Normalize case for comparison
  final normalizedPattern = pattern.map((e) => e.toUpperCase()).toList();
  final normalizedTokens = tokens.map((e) => e.toUpperCase()).toList();

  int? idx;
  for (var i = 0; i < normalizedTokens.length - normalizedPattern.length; i++) {
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
    throw ArgumentError("Field with pattern '${pattern.join(' ')}' not found in message");
  }

  final dataIndex = idx + pattern.length;
  final newTokens = _asciiToHexTokens(newValueStr);

  if (newTokens.length != expectedLength) {
    throw ArgumentError('New value must produce exactly $expectedLength tokens');
  }

  final newList = List<String>.from(tokens);
  newList.replaceRange(dataIndex, dataIndex + expectedLength, newTokens);
  return newList;
}

  static List<String> _asciiToHexTokens(String input) {
    return input.codeUnits.map((c) => c.toRadixString(16).toUpperCase().padLeft(2, '0')).toList();
  }

  static List<String> _updateLrc(List<String> tokens) {
    final dataTokens = tokens.sublist(1, tokens.length - 1); // exclude STX and old LRC
    final dataBytes = Uint8List.fromList(
        dataTokens.map((token) => int.parse(token, radix: 16)).toList());
    final lrc = _computeLrc(dataBytes);
    final updated = List<String>.from(tokens);
    updated[updated.length - 1] = lrc.toRadixString(16).toUpperCase().padLeft(2, '0');
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
