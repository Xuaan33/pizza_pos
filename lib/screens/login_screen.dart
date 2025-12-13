import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiok_pos_android_app/components/main_layout.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/secondary%20screen/customer_display_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  String enteredPin = "";
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _merchantIdController = TextEditingController();
  bool _isLoading = false;
  bool _showMerchantIdField = true;

  @override
  void initState() {
    super.initState();
    _checkStoredMerchantId();
  }

  Future<void> _checkStoredMerchantId() async {
    final prefs = await SharedPreferences.getInstance();
    final storedMerchantId = prefs.getString('merchant_id');

    if (storedMerchantId != null && storedMerchantId.isNotEmpty) {
      setState(() {
        _merchantIdController.text = storedMerchantId;
        _showMerchantIdField = false;
      });
    }
  }

  void _onKeyPress(String value) {
    if (enteredPin.length < 4) {
      setState(() {
        enteredPin += value;
      });
    }
  }

  Future<void> _validateCredentials() async {
    final username = _usernameController.text.trim();
    final merchantId = _merchantIdController.text.trim();

    if (username.isEmpty || enteredPin.isEmpty || merchantId.isEmpty) {
      Fluttertoast.showToast(
        msg: "Please enter username, PIN and merchant ID",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref
          .read(authProvider.notifier)
          .login(username, enteredPin, merchantId);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => MainLayout()),
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: e.toString(),
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      _clearPin();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _clearPin() {
    setState(() => enteredPin = "");
  }

  void _showMerchantIdInput() {
    setState(() {
      _showMerchantIdField = true;
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _merchantIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      CustomerDisplayController.showCustomerScreen();
    });

    return Scaffold(
      body: Row(
        children: [
          // LEFT SIDE
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFFFF0BF),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/bg-login.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  _buildLeftContent(),
                ],
              ),
            ),
          ),

          // RIGHT SIDE - PIN PAD
          Expanded(
            child: Container(
              color: const Color(0xFFFFE3FF),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(60),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Enter your PIN",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Neutas',
                          color: Color(0xFF00203A),
                        ),
                      ),
                      const SizedBox(height: 30),

                      // PIN DOTS
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(4, (index) {
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: index < enteredPin.length
                                  ? const Color(0xFF00203A)
                                  : Colors.grey.shade400,
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 40),

                      _buildPinPad(),
                      const SizedBox(height: 30),

                      SizedBox(
                        width: 300,
                        child: ElevatedButton(
                          onPressed: _isLoading || enteredPin.length != 4
                              ? null
                              : _validateCredentials,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF00203A),
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                              side: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF00203A),
                                  ),
                                )
                              : const Text(
                                  "Sign In",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Neutas',
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftContent() {
    return Padding(
      padding: const EdgeInsets.all(60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Logo
          Image.asset(
            'assets/logo-shiokpos-horizontal.png',
            height: 100,
          ),
          const SizedBox(height: 60),

          // Welcome text
          const Text(
            "Welcome!",
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              fontFamily: 'Neutas',
              color: Color(0xFF00203A),
            ),
          ),
          const SizedBox(height: 50),

          // Merchant ID Field
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: _showMerchantIdField
                ? TextField(
                    controller: _merchantIdController,
                    decoration: const InputDecoration(
                      labelText: 'Merchant ID',
                      border: InputBorder.none,
                      labelStyle: TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00203A),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Merchant ID',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _merchantIdController.text,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00203A),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: _showMerchantIdInput,
                        color: const Color(0xFF00203A),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 30),

          // Username Field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: InputBorder.none,
                labelStyle: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                ),
              ),
              style: const TextStyle(
                fontSize: 18,
                color: Color(0xFF00203A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinPad() {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['C', '0', '⌫']
    ];

    return Column(
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((key) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            if (key == '⌫') {
                              if (enteredPin.isNotEmpty) {
                                setState(() {
                                  enteredPin = enteredPin.substring(
                                      0, enteredPin.length - 1);
                                });
                              }
                            } else if (key == 'C') {
                              _clearPin();
                            } else {
                              _onKeyPress(key);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF00203A),
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                      elevation: 0,
                    ),
                    child: Text(
                      key,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Neutas',
                        color: Color(0xFF00203A),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}
