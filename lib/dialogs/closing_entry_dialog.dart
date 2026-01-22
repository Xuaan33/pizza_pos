import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shiok_pos_android_app/components/main_layout.dart';
import 'package:shiok_pos_android_app/components/no_stretch_scroll_behavior.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/service/pos_service.dart';

class ClosingEntryDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> closingData;

  const ClosingEntryDialog({Key? key, required this.closingData})
      : super(key: key);

  @override
  _ClosingEntryDialogState createState() => _ClosingEntryDialogState();
}

class _ClosingEntryDialogState extends ConsumerState<ClosingEntryDialog> {
  final List<TextEditingController> _amountControllers = [];
  final List<FocusNode> _focusNodes = [];
  bool _isSubmitting = false;
  late Map<String, dynamic> _closingData;

  @override
  void initState() {
    super.initState();
    _closingData = widget.closingData;
  }

  @override
  void dispose() {
    for (var controller in _amountControllers) {
      controller.dispose();
    }
    for (var focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ============ IMPROVED NULL SAFETY ============
    final messageData = _closingData['message'];
    if (messageData == null) {
      return AlertDialog(
        title: const Text('Error'),
        content: const Text('Invalid closing data'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }

    final paymentReconciliation =
        (messageData['payment_reconciliation'] as List?) ?? [];

    // Initialize controllers if not done yet
    if (_amountControllers.isEmpty && paymentReconciliation.isNotEmpty) {
      _amountControllers.addAll(
        paymentReconciliation.map(
          (payment) => TextEditingController(
              text: payment['expected_amount']?.toString() ?? '0'),
        ),
      );

      _focusNodes.addAll(
        paymentReconciliation.map((_) {
          final focusNode = FocusNode();
          focusNode.addListener(() {
            final index = _focusNodes.indexOf(focusNode);
            if (index >= 0 && index < _amountControllers.length) {
              if (focusNode.hasFocus && _amountControllers[index].text == '0') {
                _amountControllers[index].clear();
              }
            }
          });
          return focusNode;
        }),
      );
    }

    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      title: const Text(
        'Submit Closing Entry',
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
                'POS Profile: ${messageData['pos_profile'] ?? 'N/A'}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),
              ...List.generate(paymentReconciliation.length, (index) {
                final payment = paymentReconciliation[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        payment['mode_of_payment']?.toString() ?? 'Unknown',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Expected Amount: RM ${payment['expected_amount']?.toString() ?? '0.00'}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _amountControllers[index],
                        focusNode: _focusNodes[index],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Closing Amount',
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
          onPressed: _isSubmitting ? null : () => _submitClosingEntry(),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
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
  }

  Future<void> _submitClosingEntry() async {
    setState(() => _isSubmitting = true);

    try {
      // ============ IMPROVED NULL SAFETY ============
      final messageData = _closingData['message'];
      if (messageData == null) {
        throw Exception('Invalid closing data: missing message');
      }

      final closingName = messageData['name']?.toString();
      if (closingName == null || closingName.isEmpty) {
        throw Exception('Invalid closing data: missing name');
      }

      final originalPayments =
          (messageData['payment_reconciliation'] as List?)
              ?.cast<Map<String, dynamic>>() ?? [];

      if (originalPayments.isEmpty) {
        throw Exception('No payment methods to reconcile');
      }

      // Prepare payment reconciliation details
      final paymentReconciliation = <Map<String, dynamic>>[];

      for (int i = 0; i < originalPayments.length; i++) {
        final input = _amountControllers[i].text.trim();
        
        // Handle empty input
        if (input.isEmpty) {
          Fluttertoast.showToast(
            msg: "Please enter amount for ${originalPayments[i]['mode_of_payment'] ?? 'payment method'}",
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.orange,
            textColor: Colors.white,
          );
          setState(() => _isSubmitting = false);
          return;
        }

        // Validate format
        final regex = RegExp(r'^\d+(\.\d{1,2})?$');
        if (!regex.hasMatch(input)) {
          Fluttertoast.showToast(
            msg: "Invalid amount for ${originalPayments[i]['mode_of_payment'] ?? 'payment method'} (max 2 decimal places)",
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.red,
            textColor: Colors.white,
          );
          setState(() => _isSubmitting = false);
          return;
        }

        final amount = double.parse(input);
        paymentReconciliation.add({
          'mode_of_payment': originalPayments[i]['mode_of_payment'] ?? '',
          'closing_amount': amount,
        });
      }

      print('📝 Submitting closing entry: $closingName');
      print('📝 Payment reconciliation: $paymentReconciliation');

      // ============ FIXED: Handle null MainLayout ============
      Map<String, dynamic> response;
      
      final mainLayout = MainLayout.of(context);
      if (mainLayout != null) {
        // Use API queue if MainLayout is available
        print('✅ Using MainLayout API queue');
        response = await mainLayout.safeExecuteAPICall(() => 
          PosService().submitClosingVoucher(
            name: closingName,
            paymentReconciliation: paymentReconciliation,
          )
        );
      } else {
        // Direct call if MainLayout is not available
        print('⚠️ MainLayout not available, calling API directly');
        response = await PosService().submitClosingVoucher(
          name: closingName,
          paymentReconciliation: paymentReconciliation,
        );
      }

      print('📥 Closing entry response: $response');

      // ============ IMPROVED NULL SAFETY ============
      
      // Check if response is null
      if (response == null) {
        throw Exception('No response received from server');
      }

      // Check for success flag
      final success = response['success'];
      if (success == false) {
        final errorMessage = response['message'];
        throw Exception(errorMessage ?? 'Failed to submit closing entry');
      }

      // Check message structure
      final responseMessage = response['message'];
      if (responseMessage == null) {
        throw Exception('Invalid response format: missing message');
      }

      // Handle different response formats
      String? status;
      
      // Check if responseMessage is a Map
      if (responseMessage is Map) {
        status = responseMessage['status']?.toString();
      } 
      // Check if responseMessage is a String
      else if (responseMessage is String) {
        // Sometimes the API returns just a string message
        if (responseMessage.toLowerCase().contains('success') || 
            responseMessage.toLowerCase().contains('submitted')) {
          status = 'Submitted';
        }
      }

      print('📊 Closing entry status: $status');

      // Check if closing was successful
      if (status == 'Submitted' || status == 'submitted' || success == true) {
        // Mark opening as closed
        ref.read(authProvider.notifier).markOpeningClosed();

        if (mounted) {
          Navigator.pop(context);
          Fluttertoast.showToast(
            msg: "Closing entry submitted successfully",
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.green,
            textColor: Colors.white,
            toastLength: Toast.LENGTH_LONG,
          );
        }
      } else {
        throw Exception(
          'Closing entry submission failed. Status: $status'
        );
      }

    } catch (e) {
      print('❌ Error submitting closing entry: $e');
      
      if (mounted) {
        Fluttertoast.showToast(
          msg: "Error: ${e.toString().replaceAll('Exception: ', '')}",
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
          toastLength: Toast.LENGTH_LONG,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}