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
  // final TextEditingController _merchantIdController = TextEditingController();
  bool _isLoading = false;
  bool _showMerchantIdField = true;

  @override
  void initState() {
    super.initState();
    // _checkStoredMerchantId();
  }

  // Future<void> _checkStoredMerchantId() async {
  //   final prefs = await SharedPreferences.getInstance();
  //   final storedMerchantId = prefs.getString('merchant_id');

  //   if (storedMerchantId != null && storedMerchantId.isNotEmpty) {
  //     setState(() {
  //       _merchantIdController.text = storedMerchantId;
  //       _showMerchantIdField = false;
  //     });
  //   }
  // }

  void _onKeyPress(String value) {
    if (enteredPin.length < 4) {
      setState(() {
        enteredPin += value;
      });
    }
  }

  Future<void> _validateCredentials() async {
    final username = _usernameController.text.trim();
    // final merchantId = _merchantIdController.text.trim();

    if (username.isEmpty || enteredPin.isEmpty) {
      Fluttertoast.showToast(
        msg: "Please enter username and PIN",
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
          .login(username, enteredPin);
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
    // _merchantIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      CustomerDisplayController.showCustomerScreen();
    });
    // Get screen dimensions
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;
    final isTablet = screenSize.shortestSide > 600;
    final isSmallScreen = screenSize.shortestSide < 350;

    return Scaffold(
      body:
          _buildResponsiveLayout(context, isLandscape, isTablet, isSmallScreen),
    );
  }

  Widget _buildResponsiveLayout(BuildContext context, bool isLandscape,
      bool isTablet, bool isSmallScreen) {
    // For very small screens or landscape on small devices, use column layout
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;
    final isTablet = screenSize.shortestSide > 600;
    final isSmallScreen = screenSize.shortestSide < 350;
    if (isSmallScreen || (isLandscape && !isTablet)) {
      return SingleChildScrollView(
        child: Column(
          children: [
            // LEFT CONTENT (Top on small screens)
            Container(
              width: double.infinity,
              height: isLandscape
                  ? screenSize.height * 0.5
                  : screenSize.height * 0.4,
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
                  _buildLeftContent(isLandscape, isTablet, isSmallScreen),
                ],
              ),
            ),
            // RIGHT CONTENT (Bottom on small screens)
            Container(
              width: double.infinity,
              height: isLandscape
                  ? screenSize.height * 0.5
                  : screenSize.height * 0.6,
              color: const Color(0xFFFFE3FF),
              child: _buildPinSection(
                  context, isLandscape, isTablet, isSmallScreen),
            ),
          ],
        ),
      );
    }

    // For larger screens, use row layout
    return Row(
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
                _buildLeftContent(isLandscape, isTablet, isSmallScreen),
              ],
            ),
          ),
        ),
        // RIGHT SIDE - PIN PAD
        Expanded(
          child: Container(
            color: const Color(0xFFFFE3FF),
            child:
                _buildPinSection(context, isLandscape, isTablet, isSmallScreen),
          ),
        ),
      ],
    );
  }

  Widget _buildLeftContent(
      bool isLandscape, bool isTablet, bool isSmallScreen) {
    return Padding(
      padding: EdgeInsets.all(
          _getPaddingValue(isLandscape, isTablet, isSmallScreen)),
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height -
                (2 * _getPaddingValue(isLandscape, isTablet, isSmallScreen)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Logo
              SizedBox(
                height: _getSpacingValue(
                    isLandscape, isTablet, isSmallScreen, 10, 20, 30),
              ),
              Image.asset(
                'assets/logo-shiokpos-horizontal.png',
                height: _getHeightValue(
                    isLandscape, isTablet, isSmallScreen, 60, 80, 100),
                fit: BoxFit.contain,
              ),
              SizedBox(
                  height: _getSpacingValue(
                      isLandscape, isTablet, isSmallScreen, 20, 40, 60)),

              // Welcome text
              Text(
                "Welcome!",
                style: TextStyle(
                  fontSize: _getFontSizeValue(
                      isLandscape, isTablet, isSmallScreen, 32, 40, 48),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Meutas-Bold',
                  color: const Color(0xFF00203A),
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(
                  height: _getSpacingValue(
                      isLandscape, isTablet, isSmallScreen, 20, 30, 50)),

              // // Merchant ID Field
              // Container(
              //   width: double.infinity,
              //   padding: EdgeInsets.all(
              //       _getPaddingValue(isLandscape, isTablet, isSmallScreen)),
              //   decoration: BoxDecoration(
              //     color: Colors.white,
              //     borderRadius: BorderRadius.circular(_getBorderRadiusValue(
              //         isLandscape, isTablet, isSmallScreen)),
              //     border: Border.all(color: Colors.grey.shade300),
              //   ),
              //   child: _showMerchantIdField
              //       ? TextField(
              //           controller: _merchantIdController,
              //           decoration: InputDecoration(
              //             labelText: 'Merchant ID',
              //             border: InputBorder.none,
              //             labelStyle: TextStyle(
              //               color: Colors.grey,
              //               fontSize: _getFontSizeValue(isLandscape, isTablet,
              //                   isSmallScreen, 12, 13, 14),
              //             ),
              //           ),
              //           style: TextStyle(
              //             fontSize: _getFontSizeValue(
              //                 isLandscape, isTablet, isSmallScreen, 16, 17, 18),
              //             fontWeight: FontWeight.bold,
              //             color: const Color(0xFF00203A),
              //           ),
              //         )
              //       : Row(
              //           children: [
              //             Expanded(
              //               child: Column(
              //                 crossAxisAlignment: CrossAxisAlignment.start,
              //                 children: [
              //                   Text(
              //                     'Merchant ID',
              //                     style: TextStyle(
              //                       fontSize: _getFontSizeValue(isLandscape,
              //                           isTablet, isSmallScreen, 12, 13, 14),
              //                       color: Colors.grey[600],
              //                     ),
              //                   ),
              //                   SizedBox(height: 4),
              //                   Text(
              //                     _merchantIdController.text,
              //                     style: TextStyle(
              //                       fontSize: _getFontSizeValue(isLandscape,
              //                           isTablet, isSmallScreen, 16, 17, 18),
              //                       fontWeight: FontWeight.bold,
              //                       color: const Color(0xFF00203A),
              //                     ),
              //                   ),
              //                 ],
              //               ),
              //             ),
              //             IconButton(
              //               icon: Icon(Icons.edit,
              //                   size: _getIconSizeValue(
              //                       isLandscape, isTablet, isSmallScreen)),
              //               onPressed: _showMerchantIdInput,
              //               color: const Color(0xFF00203A),
              //             ),
              //           ],
              //         ),
              // ),
              // SizedBox(
              //     height: _getSpacingValue(
              //         isLandscape, isTablet, isSmallScreen, 15, 20, 30)),

              // Username Field
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal:
                      _getPaddingValue(isLandscape, isTablet, isSmallScreen),
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(_getBorderRadiusValue(
                      isLandscape, isTablet, isSmallScreen)),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: 'Username',
                    border: InputBorder.none,
                    labelStyle: TextStyle(
                      color: Colors.grey,
                      fontSize: _getFontSizeValue(
                          isLandscape, isTablet, isSmallScreen, 12, 13, 14),
                    ),
                  ),
                  style: TextStyle(
                    fontSize: _getFontSizeValue(
                        isLandscape, isTablet, isSmallScreen, 16, 17, 18),
                    color: const Color(0xFF00203A),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinSection(BuildContext context, bool isLandscape, bool isTablet,
      bool isSmallScreen) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(
            _getPaddingValue(isLandscape, isTablet, isSmallScreen)),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Enter your PIN",
                style: TextStyle(
                  fontSize: _getFontSizeValue(
                      isLandscape, isTablet, isSmallScreen, 24, 28, 32),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Meutas-Bold',
                  color: const Color(0xFF00203A),
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(
                  height: _getSpacingValue(
                      isLandscape, isTablet, isSmallScreen, 15, 20, 30)),

              // PIN DOTS
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  return Container(
                    margin: EdgeInsets.symmetric(
                        horizontal: _getMarginValue(
                            isLandscape, isTablet, isSmallScreen)),
                    width:
                        _getDotSizeValue(isLandscape, isTablet, isSmallScreen),
                    height:
                        _getDotSizeValue(isLandscape, isTablet, isSmallScreen),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index < enteredPin.length
                          ? const Color(0xFF00203A)
                          : Colors.grey.shade400,
                    ),
                  );
                }),
              ),
              SizedBox(
                  height: _getSpacingValue(
                      isLandscape, isTablet, isSmallScreen, 20, 30, 40)),

              _buildPinPad(isLandscape, isTablet, isSmallScreen),
              SizedBox(
                  height: _getSpacingValue(
                      isLandscape, isTablet, isSmallScreen, 15, 20, 30)),

              SizedBox(
                width:
                    _getButtonWidthValue(isLandscape, isTablet, isSmallScreen),
                child: ElevatedButton(
                  onPressed: _isLoading || enteredPin.length != 4
                      ? null
                      : _validateCredentials,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF00203A),
                    padding: EdgeInsets.symmetric(
                        vertical: _getButtonPaddingValue(
                            isLandscape, isTablet, isSmallScreen)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_getBorderRadiusValue(
                              isLandscape, isTablet, isSmallScreen) *
                          2),
                      side: BorderSide(
                        color: Colors.grey.shade300,
                      ),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? SizedBox(
                          height: _getLoadingIndicatorSize(
                              isLandscape, isTablet, isSmallScreen),
                          width: _getLoadingIndicatorSize(
                              isLandscape, isTablet, isSmallScreen),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF00203A),
                          ),
                        )
                      : Text(
                          "Sign In",
                          style: TextStyle(
                            fontSize: _getFontSizeValue(isLandscape, isTablet,
                                isSmallScreen, 16, 17, 18),
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Meutas-Bold',
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinPad(bool isLandscape, bool isTablet, bool isSmallScreen) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['C', '0', '⌫']
    ];

    final buttonSize = _getPinButtonSize(isLandscape, isTablet, isSmallScreen);
    final buttonFontSize =
        _getPinButtonFontSize(isLandscape, isTablet, isSmallScreen);

    return Column(
      children: keys.map((row) {
        return Padding(
          padding: EdgeInsets.symmetric(
              vertical: _getSpacingValue(
                  isLandscape, isTablet, isSmallScreen, 4, 6, 8)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((key) {
              return Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: _getSpacingValue(
                        isLandscape, isTablet, isSmallScreen, 6, 8, 12)),
                child: SizedBox(
                  width: buttonSize,
                  height: buttonSize,
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
                      style: TextStyle(
                        fontSize: buttonFontSize,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Meutas-Bold',
                        color: const Color(0xFF00203A),
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

  // Helper methods for responsive values
  double _getPaddingValue(bool isLandscape, bool isTablet, bool isSmallScreen) {
    if (isSmallScreen) return 16;
    if (isTablet) return 40;
    return 60;
  }

  double _getSpacingValue(bool isLandscape, bool isTablet, bool isSmallScreen,
      double small, double medium, double large) {
    if (isSmallScreen) return small;
    if (isTablet) return medium;
    return large;
  }

  double _getHeightValue(bool isLandscape, bool isTablet, bool isSmallScreen,
      double small, double medium, double large) {
    if (isSmallScreen) return small;
    if (isTablet) return medium;
    return large;
  }

  double _getFontSizeValue(bool isLandscape, bool isTablet, bool isSmallScreen,
      double small, double medium, double large) {
    if (isSmallScreen) return small;
    if (isTablet) return medium;
    return large;
  }

  double _getBorderRadiusValue(
      bool isLandscape, bool isTablet, bool isSmallScreen) {
    if (isSmallScreen) return 8;
    if (isTablet) return 12;
    return 15;
  }

  double _getIconSizeValue(
      bool isLandscape, bool isTablet, bool isSmallScreen) {
    if (isSmallScreen) return 16;
    if (isTablet) return 18;
    return 20;
  }

  double _getMarginValue(bool isLandscape, bool isTablet, bool isSmallScreen) {
    if (isSmallScreen) return 4;
    if (isTablet) return 6;
    return 8;
  }

  double _getDotSizeValue(bool isLandscape, bool isTablet, bool isSmallScreen) {
    if (isSmallScreen) return 12;
    if (isTablet) return 14;
    return 16;
  }

  double _getButtonWidthValue(
      bool isLandscape, bool isTablet, bool isSmallScreen) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (isSmallScreen) return screenWidth * 0.8;
    if (isTablet) return 350;
    return 300;
  }

  double _getButtonPaddingValue(
      bool isLandscape, bool isTablet, bool isSmallScreen) {
    if (isSmallScreen) return 14;
    if (isTablet) return 16;
    return 18;
  }

  double _getLoadingIndicatorSize(
      bool isLandscape, bool isTablet, bool isSmallScreen) {
    if (isSmallScreen) return 20;
    if (isTablet) return 22;
    return 24;
  }

  double _getPinButtonSize(
      bool isLandscape, bool isTablet, bool isSmallScreen) {
    if (isSmallScreen) return 60;
    if (isTablet) return 70;
    return 80;
  }

  double _getPinButtonFontSize(
      bool isLandscape, bool isTablet, bool isSmallScreen) {
    if (isSmallScreen) return 18;
    if (isTablet) return 22;
    return 24;
  }
}
