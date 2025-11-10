import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';

class UsbConnectionService {
  UsbPort? _port;
  StreamSubscription<String>? _subscription;
  List<UsbDevice> _availableDevices = [];
  bool _isConnected = false;

  bool get isConnected => _isConnected;
  List<UsbDevice> get availableDevices => _availableDevices;

  // Discover USB devices
  Future<List<UsbDevice>> discoverDevices() async {
    try {
      _availableDevices = await UsbSerial.listDevices();
      debugPrint('Found ${_availableDevices.length} USB devices');
      return _availableDevices;
    } catch (e) {
      debugPrint('Error discovering USB devices: $e');
      return [];
    }
  }

  // Connect to a specific USB device
  // The key change: device.create() handles permission request automatically
  Future<bool> connect(UsbDevice device) async {
    try {
      debugPrint('Attempting to connect to USB device: ${device.productName}');
      debugPrint('Device ID: ${device.deviceId}, VID: ${device.vid}, PID: ${device.pid}');
      
      // CRITICAL: device.create() will automatically request permission if needed
      // This is where the permission dialog appears
      _port = await device.create();
      
      if (_port == null) {
        debugPrint('Failed to create USB port - permission may have been denied');
        return false;
      }

      debugPrint('USB port created successfully, attempting to open...');
      
      bool openResult = await _port!.open();
      if (!openResult) {
        debugPrint('Failed to open USB port');
        _port = null;
        return false;
      }

      debugPrint('USB port opened, configuring parameters...');
      
      await _port!.setDTR(true);
      await _port!.setRTS(true);
      await _port!.setPortParameters(
        115200, // baudRate
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      _isConnected = true;
      debugPrint('USB connection established successfully');
      return true;
    } catch (e) {
      debugPrint('Error connecting to USB device: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      _isConnected = false;
      _port = null;
      return false;
    }
  }

  // Send data to USB device
  Future<bool> sendData(List<int> data) async {
    if (_port == null || !_isConnected) {
      debugPrint('USB port not connected');
      return false;
    }

    try {
      await _port!.write(Uint8List.fromList(data));
      debugPrint('Data sent via USB: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      return true;
    } catch (e) {
      debugPrint('Error sending data via USB: $e');
      return false;
    }
  }

  // Listen for incoming data
  Stream<String> get inputStream {
    if (_port == null) {
      return Stream.empty();
    }
    return _port!.inputStream!.map((data) {
      return String.fromCharCodes(data);
    });
  }

  // Listen for raw bytes
  Stream<Uint8List>? get inputStreamRaw {
    return _port?.inputStream;
  }

  // Test connection with ping
  Future<bool> testConnection() async {
    if (_port == null || !_isConnected) {
      debugPrint('USB port not connected');
      return false;
    }

    try {
      // Send ping message
      const pingHexMessage = "02 00 18 36 30 30 30 30 30 30 30 30 30 31 30 46 46 30 30 30 1C 03 30";
      final pingBytes = _hexStringToBytes(pingHexMessage);
      
      await sendData(pingBytes);
      
      // Wait for response (with timeout)
      final completer = Completer<bool>();
      Timer? timeoutTimer;
      StreamSubscription<Uint8List>? subscription;

      timeoutTimer = Timer(const Duration(seconds: 5), () {
        subscription?.cancel();
        if (!completer.isCompleted) {
          completer.complete(false);
        }
      });

      subscription = inputStreamRaw?.listen((data) {
        debugPrint('USB Response received: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        timeoutTimer?.cancel();
        subscription?.cancel();
        if (!completer.isCompleted) {
          // Check for ACK (06) or valid response
          if (data.isNotEmpty && (data[0] == 0x06 || data[0] == 0x02)) {
            completer.complete(true);
          } else {
            completer.complete(false);
          }
        }
      });

      return await completer.future;
    } catch (e) {
      debugPrint('Error testing USB connection: $e');
      return false;
    }
  }

  // Disconnect from USB device
  Future<void> disconnect() async {
    try {
      await _subscription?.cancel();
      _subscription = null;
      
      if (_port != null) {
        await _port!.close();
        _port = null;
      }
      
      _isConnected = false;
      debugPrint('USB connection closed');
    } catch (e) {
      debugPrint('Error disconnecting USB: $e');
    }
  }

  // Helper method to convert hex string to bytes
  List<int> _hexStringToBytes(String hexString) {
    return hexString
        .split(' ')
        .map((hex) => int.parse(hex, radix: 16))
        .toList();
  }

  // Process payment via USB
  Future<Map<String, dynamic>> processPayment({
    required double amount,
    String transactionType = 'SALE',
  }) async {
    if (!_isConnected || _port == null) {
      return {
        'success': false,
        'message': 'USB not connected',
      };
    }

    try {
      // Format amount (e.g., 10.50 -> 000000001050)
      final amountStr = (amount * 100).toInt().toString().padLeft(12, '0');
      
      // Build payment message (this is a simplified example)
      // You'll need to adapt this to your actual POS terminal protocol
      final message = '02 00 92 36 $amountStr 1C 03 B2'; // Replace XX with proper values
      final messageBytes = _hexStringToBytes(message);
      
      await sendData(messageBytes);
      
      // Wait for response
      final completer = Completer<Map<String, dynamic>>();
      Timer? timeoutTimer;
      StreamSubscription<Uint8List>? subscription;

      timeoutTimer = Timer(const Duration(seconds: 30), () {
        subscription?.cancel();
        if (!completer.isCompleted) {
          completer.complete({
            'success': false,
            'message': 'Transaction timeout',
          });
        }
      });

      subscription = inputStreamRaw?.listen((data) {
        debugPrint('Payment response: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        timeoutTimer?.cancel();
        subscription?.cancel();
        
        if (!completer.isCompleted) {
          // Parse response (adapt to your protocol)
          final result = _parsePaymentResponse(data);
          completer.complete(result);
        }
      });

      return await completer.future;
    } catch (e) {
      debugPrint('Error processing USB payment: $e');
      return {
        'success': false,
        'message': 'Payment error: $e',
      };
    }
  }

  // Parse payment response
  Map<String, dynamic> _parsePaymentResponse(Uint8List data) {
    try {
      // This is a simplified parser - adapt to your actual protocol
      if (data.isEmpty) {
        return {'success': false, 'message': 'Empty response'};
      }

      // Check for ACK
      if (data.length == 1 && data[0] == 0x06) {
        return {'success': true, 'message': 'Payment approved'};
      }

      // Check for proper message format
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