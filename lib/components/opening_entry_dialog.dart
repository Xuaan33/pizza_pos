import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shiok_pos_android_app/components/no_stretch_scroll_behavior.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';

class OpeningEntryDialog extends ConsumerStatefulWidget {
  const OpeningEntryDialog({Key? key}) : super(key: key);

  @override
  _OpeningEntryDialogState createState() => _OpeningEntryDialogState();
}

class _OpeningEntryDialogState extends ConsumerState<OpeningEntryDialog> {
  final List<TextEditingController> _amountControllers = [];
  final List<FocusNode> _focusNodes = [];
  bool _isSubmitting = false;

  @override
  void dispose() {
    for (var controller in _amountControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return authState.when(
      initial: () => const Center(child: CircularProgressIndicator()),
      unauthenticated: () => const Center(child: Text('Unauthorized')),
      authenticated: (sid, apiKey, apiSecret, username, email, fullName,
          posProfile, branch, paymentMethods, taxes, hasOpening) {
        // Initialize controllers if not done yet
        if (_amountControllers.isEmpty) {
          _amountControllers.addAll(
            List.generate(
              paymentMethods.length,
              (index) => TextEditingController(text: '0'),
            ),
          );
          _focusNodes.addAll(
            List.generate(
              paymentMethods.length,
              (index) {
                final focusNode = FocusNode();
                focusNode.addListener(() {
                  final controller = _amountControllers[index];
                  if (focusNode.hasFocus && controller.text == '0') {
                    controller.clear();
                  }
                });
                return focusNode;
              },
            ),
          );
        }

        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: const Text(
            'Create Opening Entry',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: ScrollConfiguration(
            behavior: NoStretchScrollBehavior(),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    'POS Profile: $posProfile',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ...List.generate(paymentMethods.length, (index) {
                    final method = paymentMethods[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            method['name'],
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _amountControllers[index],
                            focusNode: _focusNodes[index],
                            decoration: const InputDecoration(
                              labelText: 'Opening Amount',
                              border: OutlineInputBorder(),
                              prefixText: 'RM ',
                            ),
                            keyboardType:
                                TextInputType.numberWithOptions(decimal: true),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _isSubmitting ? null : () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: _isSubmitting
                  ? null
                  : () => _submitOpeningEntry(posProfile, paymentMethods),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE732A0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Submit',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submitOpeningEntry(
      String posProfile, List<Map<String, dynamic>> paymentMethods) async {
    setState(() => _isSubmitting = true);

    try {
      // Prepare balance details
      final balanceDetails = <Map<String, dynamic>>[];

      for (int i = 0; i < paymentMethods.length; i++) {
        final input = _amountControllers[i].text.trim();
        final regex = RegExp(r'^\d+(\.\d{1,2})?$');
        if (!regex.hasMatch(input)) {
          Fluttertoast.showToast(
            msg:
                "Invalid amount for ${paymentMethods[i]['name']} (max 2 decimal places)",
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.red,
            textColor: Colors.white,
          );
          setState(() => _isSubmitting = false);
          return;
        }

        final amount = double.parse(input);
        balanceDetails.add({
          'mode_of_payment': paymentMethods[i]['name'],
          'opening_amount': amount,
        });
      }

      final response = await PosService().createOpeningVoucher(
        posProfile: posProfile,
        balanceDetails: balanceDetails,
      );

      print(response);

      //to be confirmed
      if (response['message']["status"] == "Open") {
        if (mounted) {
          Navigator.pop(context);
          Fluttertoast.showToast(
            msg: "Opening entry created successfully",
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.green,
            textColor: Colors.white,
          );
        }
      } else {
        throw Exception(
            response['message'] ?? 'Failed to create opening entry');
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: "Error: ${e.toString()}",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}
