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
    final paymentReconciliation =
        (_closingData['message']['payment_reconciliation'] as List?) ?? [];

    // Initialize controllers if not done yet
    if (_amountControllers.isEmpty) {
      _amountControllers.addAll(
        paymentReconciliation.map(
          (payment) => TextEditingController(
              text: payment['expected_amount'].toString()),
        ),
      );

      _focusNodes.addAll(
        paymentReconciliation.map((_) {
          final focusNode = FocusNode();
          focusNode.addListener(() {
            final index = _focusNodes.indexOf(focusNode);
            if (focusNode.hasFocus && _amountControllers[index].text == '0') {
              _amountControllers[index].clear();
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
                'POS Profile: ${_closingData['message']['pos_profile']}',
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
                        payment['mode_of_payment'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Expected Amount: RM ${payment['expected_amount']}',
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
      // Prepare payment reconciliation details
      final paymentReconciliation = <Map<String, dynamic>>[];
      final originalPayments =
          (_closingData['message']['payment_reconciliation'] as List)
              .cast<Map<String, dynamic>>();

      for (int i = 0; i < originalPayments.length; i++) {
        final input = _amountControllers[i].text.trim();
        final regex = RegExp(r'^\d+(\.\d{1,2})?$');

        if (!regex.hasMatch(input)) {
          Fluttertoast.showToast(
            msg: "Invalid amount for ${originalPayments[i]['mode_of_payment']}",
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.red,
            textColor: Colors.white,
          );
          setState(() => _isSubmitting = false);
          return;
        }

        final amount = double.parse(input);
        paymentReconciliation.add({
          'mode_of_payment': originalPayments[i]['mode_of_payment'],
          'closing_amount': amount,
        });
      }

      final response = await MainLayout.of(context)!.safeExecuteAPICall(() => PosService().submitClosingVoucher(
        name: _closingData['message']['name'],
        paymentReconciliation: paymentReconciliation,
      ));

      if (response['message']["status"] == "Submitted") {
        ref.read(authProvider.notifier).markOpeningClosed();

        if (mounted) {
          Navigator.pop(context);
          Fluttertoast.showToast(
            msg: "Closing entry submitted successfully",
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.green,
            textColor: Colors.white,
          );
        }
      } else {
        throw Exception(
            response['message'] ?? 'Failed to submit closing entry');
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
