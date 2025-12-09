import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiok_pos_android_app/components/main_layout.dart';
import 'package:shiok_pos_android_app/components/no_stretch_scroll_behavior.dart';
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
      backgroundColor: Colors.pink[50],
      body: Center(
        child: ScrollConfiguration(
          behavior: NoStretchScrollBehavior(),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 490),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),
                  Image.asset('assets/logo-shiokpos.png', height: 80),
                  const SizedBox(height: 20),
                  const Text("Welcome!",
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),

                  // Username field
                  TextField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 15),

                  // Merchant ID field - conditionally shown
                  if (_showMerchantIdField) ...[
                    TextField(
                      controller: _merchantIdController,
                      decoration: InputDecoration(
                        labelText: 'Merchant ID',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 15),
                  ] else ...[
                    // Show merchant ID as read-only with edit option
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Merchant ID',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                Text(
                                  _merchantIdController.text,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: _showMerchantIdInput,
                            tooltip: 'Change Merchant ID',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                  ],

                  const Text("Enter your PIN",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),

                  // PIN Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (index) {
                      return Container(
                        margin: const EdgeInsets.all(5),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index < enteredPin.length
                              ? Colors.black
                              : Colors.grey,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 15),

                  _buildPinPad(),
                  const SizedBox(height: 15),

                  // Sign In Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading || enteredPin.length != 4
                          ? null
                          : _validateCredentials,
                      style: ButtonStyle(
                        backgroundColor:
                            MaterialStateProperty.resolveWith<Color>((states) {
                          if (states.contains(MaterialState.pressed)) {
                            return const Color(0xFFE732A0); // Pink when pressed
                          }
                          return Colors.white; // Default background
                        }),
                        foregroundColor:
                            MaterialStateProperty.resolveWith<Color>((states) {
                          if (states.contains(MaterialState.pressed)) {
                            return Colors.white; // White text when pressed
                          }
                          return Colors.black; // Default text color
                        }),
                        shape:
                            MaterialStateProperty.all<RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30.0),
                            side: const BorderSide(
                                color: Color.fromARGB(255, 26, 10, 10)),
                          ),
                        ),
                        padding: MaterialStateProperty.all<EdgeInsetsGeometry>(
                          const EdgeInsets.symmetric(
                              horizontal: 40, vertical: 12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              "Sign In",
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
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
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((key) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
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
                  style: ButtonStyle(
                    backgroundColor:
                        MaterialStateProperty.resolveWith<Color>((states) {
                      if (states.contains(MaterialState.pressed)) {
                        return const Color(0xFFE732A0); // Pink when pressed
                      }
                      return Colors.white; // Default background
                    }),
                    foregroundColor:
                        MaterialStateProperty.resolveWith<Color>((states) {
                      if (states.contains(MaterialState.pressed)) {
                        return Colors.white; // White text when pressed
                      }
                      return Colors.black; // Default text color
                    }),
                    shape: MaterialStateProperty.all<CircleBorder>(
                        const CircleBorder()),
                    padding: MaterialStateProperty.all<EdgeInsetsGeometry>(
                      const EdgeInsets.all(25), // Adjust button size
                    ),
                  ),
                  child: SizedBox(
                    width: 24,
                    child: Center(
                      child: Text(
                        key,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
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
