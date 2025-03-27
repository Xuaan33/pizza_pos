import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shiok_pos_android_app/screens/home_screen.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String enteredPin = "";
  final String correctPin = "1234";

  void _onKeyPress(String value) {
    setState(() {
      if (enteredPin.length < 4) {
        enteredPin += value;
      }
    });
  }

  void _validatePin() {
    if (enteredPin == correctPin) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen()),
      );
    } else {
      Fluttertoast.showToast(
        msg: "Incorrect PIN. Please try again.",
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      setState(() {
        enteredPin = "";
      });
    }
  }

  void _clearPin() {
    setState(() {
      enteredPin = "";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.pink[50], // Light pink background
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/logo-shiokpos.png', height: 80),
          const SizedBox(height: 20),
          const Text(
            "Welcome, ABC",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
              return Container(
                margin: const EdgeInsets.all(5),
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index < enteredPin.length ? Colors.black : Colors.grey,
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          _buildPinPad(),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: enteredPin.length == 4 ? _validatePin : null,
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
                  shape: MaterialStateProperty.all<RoundedRectangleBorder>(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30.0),
                      side: const BorderSide(
                          color: Color.fromARGB(255, 26, 10, 10)),
                    ),
                  ),
                  padding: MaterialStateProperty.all<EdgeInsetsGeometry>(
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  ),
                ),
                child: const Text("Sign In",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPinPad() {
    return Column(
      children: [
        for (var row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['C', '0', '⌫']
        ])
          Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 6), // Increase spacing
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: row.map((number) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12), // Increase horizontal spacing
                  child: ElevatedButton(
                    onPressed: () {
                      if (number == '⌫') {
                        setState(() {
                          if (enteredPin.isNotEmpty) {
                            enteredPin =
                                enteredPin.substring(0, enteredPin.length - 1);
                          }
                        });
                      } else if (number == 'C') {
                        _clearPin();
                      } else {
                        _onKeyPress(number);
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
                      width: 24, // Ensuring uniform width for all buttons
                      child: Center(
                        child: Text(number,
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
