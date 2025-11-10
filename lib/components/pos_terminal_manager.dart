import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiok_pos_android_app/service/tcp_connection_service.dart';
import 'package:shiok_pos_android_app/service/usb_connection_service.dart';
import 'package:usb_serial/usb_serial.dart';

enum ConnectionType { tcpip, wired }

class PosTerminalManager {
  static final PosTerminalManager _instance = PosTerminalManager._internal();
  factory PosTerminalManager() => _instance;
  PosTerminalManager._internal();

  final TcpConnectionService _tcpService = TcpConnectionService();
  final UsbConnectionService _usbService = UsbConnectionService();

  ConnectionType _currentConnectionType = ConnectionType.tcpip;
  String _savedIp = '192.168.1.1';
  int _savedPort = 8800;
  UsbDevice? _savedUsbDevice;

  // Getters
  ConnectionType get currentConnectionType => _currentConnectionType;
  bool get isConnected => _currentConnectionType == ConnectionType.tcpip
      ? _tcpService.isConnected
      : _usbService.isConnected;

  TcpConnectionService get tcpService => _tcpService;
  UsbConnectionService get usbService => _usbService;

  // Load saved configuration
  Future<void> loadConfiguration() async {
    final prefs = await SharedPreferences.getInstance();

    final connectionTypeStr = prefs.getString('connection_type') ?? 'TCP/IP';
    _currentConnectionType = connectionTypeStr == 'Wired'
        ? ConnectionType.wired
        : ConnectionType.tcpip;

    _savedIp = prefs.getString('pos_ip') ?? '192.168.1.1';
    _savedPort = prefs.getInt('pos_port') ?? 8800;

    // Note: USB device needs to be selected each time as device IDs can change
  }

  // Save configuration
  Future<void> saveConfiguration({
    required ConnectionType type,
    String? ip,
    int? port,
    UsbDevice? usbDevice,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    _currentConnectionType = type;
    await prefs.setString(
        'connection_type', type == ConnectionType.tcpip ? 'TCP/IP' : 'Wired');

    if (type == ConnectionType.tcpip && ip != null && port != null) {
      _savedIp = ip;
      _savedPort = port;
      await prefs.setString('pos_ip', ip);
      await prefs.setInt('pos_port', port);
    } else if (type == ConnectionType.wired && usbDevice != null) {
      _savedUsbDevice = usbDevice;
      // USB devices can't be reliably saved, need to be selected each time
    }
  }

  // Test connection
  Future<bool> testConnection() async {
    if (_currentConnectionType == ConnectionType.tcpip) {
      return await _tcpService.testConnection(_savedIp, _savedPort);
    } else {
      if (_savedUsbDevice == null) {
        return false;
      }

      // device.create() will automatically request permission if needed
      final connected = await _usbService.connect(_savedUsbDevice!);
      if (connected) {
        return await _usbService.testConnection();
      }
      return false;
    }
  }

  // Connect with saved configuration
  Future<bool> connect() async {
    if (_currentConnectionType == ConnectionType.tcpip) {
      return await _tcpService.connect(_savedIp, _savedPort);
    } else {
      if (_savedUsbDevice == null) {
        // Try to auto-discover and connect to first available device
        final devices = await _usbService.discoverDevices();
        if (devices.isEmpty) {
          return false;
        }
        _savedUsbDevice = devices.first;
      }

      // device.create() will automatically request permission if needed
      return await _usbService.connect(_savedUsbDevice!);
    }
  }

  // Disconnect
  Future<void> disconnect() async {
    if (_currentConnectionType == ConnectionType.tcpip) {
      await _tcpService.disconnect();
    } else {
      await _usbService.disconnect();
    }
  }

  // Process payment using current connection
  Future<Map<String, dynamic>> processPayment({
    required double amount,
    String transactionType = 'SALE',
  }) async {
    // Ensure connected
    if (!isConnected) {
      final connected = await connect();
      if (!connected) {
        return {
          'success': false,
          'message': 'Failed to connect to POS terminal',
        };
      }
    }

    if (_currentConnectionType == ConnectionType.tcpip) {
      return await _tcpService.processPayment(
        amount: amount,
        transactionType: transactionType,
      );
    } else {
      return await _usbService.processPayment(
        amount: amount,
        transactionType: transactionType,
      );
    }
  }

  // Get connection status message
  String getConnectionStatusMessage() {
    if (isConnected) {
      return _currentConnectionType == ConnectionType.tcpip
          ? 'Connected via TCP/IP ($_savedIp:$_savedPort)'
          : 'Connected via USB';
    } else {
      return 'Not connected';
    }
  }

  // Discover USB devices
  Future<List<UsbDevice>> discoverUsbDevices() async {
    return await _usbService.discoverDevices();
  }

  // Set USB device for wired connection
  void setUsbDevice(UsbDevice device) {
    _savedUsbDevice = device;
  }
}
