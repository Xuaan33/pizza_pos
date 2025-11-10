import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class TcpConnectionService {
  Socket? _socket;
  bool _isConnected = false;
  final List<Map<String, dynamic>> _connectionLogs = [];

  bool get isConnected => _isConnected;
  List<Map<String, dynamic>> get connectionLogs => _connectionLogs;

  // Test if host is reachable
  Future<bool> isHostReachable(String ip) async {
    try {
      final result = await InternetAddress.lookup(ip);
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // Connect to TCP/IP
  Future<bool> connect(String ip, int port) async {
    try {
      _socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
      _socket!.setOption(SocketOption.tcpNoDelay, true);
      _isConnected = true;
      
      _logConnection(true, 'Connected to $ip:$port');
      debugPrint('TCP/IP connection established to $ip:$port');
      return true;
    } on SocketException catch (e) {
      _logConnection(false, 'Connection failed: ${e.message}', error: e.toString());
      _isConnected = false;
      return false;
    } catch (e) {
      _logConnection(false, 'Connection error', error: e.toString());
      _isConnected = false;
      return false;
    }
  }

  // Send data
  Future<bool> sendData(List<int> data) async {
    if (_socket == null || !_isConnected) {
      debugPrint('TCP socket not connected');
      return false;
    }

    try {
      _socket!.add(data);
      debugPrint('Data sent via TCP: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      return true;
    } catch (e) {
      debugPrint('Error sending data via TCP: $e');
      return false;
    }
  }

  // Listen for responses
  Stream<List<int>> get responseStream {
    if (_socket == null) {
      return Stream.empty();
    }
    return _socket!.asBroadcastStream();
  }

  // Test connection with ping
  Future<bool> testConnection(String ip, int port) async {
    try {
      if (!await isHostReachable(ip)) {
        _logConnection(false, 'Host $ip is unreachable');
        return false;
      }

      final connected = await connect(ip, port);
      if (!connected) {
        return false;
      }

      const pingHexMessage = "02 00 18 36 30 30 30 30 30 30 30 30 30 31 30 46 46 30 30 30 1C 03 30";
      final pingBytes = _hexStringToBytes(pingHexMessage);

      final completer = Completer<bool>();
      Timer? timeoutTimer;
      StreamSubscription<List<int>>? subscription;

      timeoutTimer = Timer(const Duration(seconds: 10), () {
        subscription?.cancel();
        if (!completer.isCompleted) {
          _logConnection(false, 'Response timeout');
          completer.complete(false);
        }
      });

      subscription = responseStream.listen((data) {
        debugPrint('TCP Response: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        timeoutTimer?.cancel();
        subscription?.cancel();

        if (!completer.isCompleted) {
          // Check for ACK (06) or valid response
          if (data.isNotEmpty && (data[0] == 0x06 || data[0] == 0x02)) {
            _logConnection(true, 'Connection test successful', response: data);
            completer.complete(true);
          } else {
            _logConnection(false, 'Invalid response');
            completer.complete(false);
          }
        }
      });

      await sendData(pingBytes);
      return await completer.future;
    } catch (e) {
      _logConnection(false, 'Test connection error', error: e.toString());
      return false;
    }
  }

  // Process payment via TCP/IP
  Future<Map<String, dynamic>> processPayment({
    required double amount,
    String transactionType = 'SALE',
  }) async {
    if (!_isConnected || _socket == null) {
      return {
        'success': false,
        'message': 'TCP/IP not connected',
      };
    }

    try {
      // Format amount (e.g., 10.50 -> 000000001050)
      final amountStr = (amount * 100).toInt().toString().padLeft(12, '0');
      
      // Build payment message (adapt to your protocol)
      final message = '02 00 36 $amountStr 1C 03 B2'; // Replace XX with proper values
      final messageBytes = _hexStringToBytes(message);
      
      await sendData(messageBytes);
      
      // Wait for response
      final completer = Completer<Map<String, dynamic>>();
      Timer? timeoutTimer;
      StreamSubscription<List<int>>? subscription;

      timeoutTimer = Timer(const Duration(seconds: 30), () {
        subscription?.cancel();
        if (!completer.isCompleted) {
          completer.complete({
            'success': false,
            'message': 'Transaction timeout',
          });
        }
      });

      subscription = responseStream.listen((data) {
        debugPrint('Payment response: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        timeoutTimer?.cancel();
        subscription?.cancel();
        
        if (!completer.isCompleted) {
          final result = _parsePaymentResponse(data);
          completer.complete(result);
        }
      });

      return await completer.future;
    } catch (e) {
      debugPrint('Error processing TCP payment: $e');
      return {
        'success': false,
        'message': 'Payment error: $e',
      };
    }
  }

  // Disconnect
  Future<void> disconnect() async {
    try {
      await _socket?.close();
      _socket = null;
      _isConnected = false;
      debugPrint('TCP connection closed');
    } catch (e) {
      debugPrint('Error disconnecting TCP: $e');
    }
  }

  // Helper methods
  List<int> _hexStringToBytes(String hexString) {
    return hexString
        .split(' ')
        .map((hex) => int.parse(hex, radix: 16))
        .toList();
  }

  void _logConnection(bool success, String message, {String? error, List<int>? response}) {
    _connectionLogs.add({
      'timestamp': DateTime.now().toIso8601String(),
      'success': success,
      'message': message,
      'error': error,
      'response': response?.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' '),
    });
  }

  Map<String, dynamic> _parsePaymentResponse(List<int> data) {
    try {
      if (data.isEmpty) {
        return {'success': false, 'message': 'Empty response'};
      }

      if (data.length == 1 && data[0] == 0x06) {
        return {'success': true, 'message': 'Payment approved'};
      }

      if (data.length >= 5 && data[0] == 0x02 && data[data.length - 2] == 0x03) {
        return {
          'success': true,
          'message': 'Transaction successful',
          'raw_response': data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' '),
        };
      }

      return {'success': false, 'message': 'Invalid response format'};
    } catch (e) {
      return {'success': false, 'message': 'Parse error: $e'};
    }
  }
}