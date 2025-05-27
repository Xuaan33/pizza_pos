import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/components/opening_entry_dialog.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return authState.when(
        initial: () => const Center(child: CircularProgressIndicator()),
        unauthenticated: () => const Center(child: Text('Unauthorized')),
        authenticated: (sid, apiKey, apiSecret, username, email, fullName,
            posProfile, branch, paymentMethods, taxes, hasOpening) {
          return Container(
            color: Colors.grey[100],
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopSection(),
                const SizedBox(height: 30),
                if (true) _buildOpeningEntryButton(hasOpening),
              ],
            ),
          );
        });
  }

  Widget _buildTopSection() {
    return Row(
      children: [
        const Text(
          'System Settings',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildOpeningEntryButton(bool hasOpening) {
  final isDisabled = hasOpening;

  return SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: isDisabled ? null : () => _showOpeningEntryDialog(),
      style: ElevatedButton.styleFrom(
        backgroundColor:
            isDisabled ? Colors.grey[400] : const Color(0xFFE732A0),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(
        isDisabled ? 'Opened' : 'Create Opening Entry',
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
}


  void _showOpeningEntryDialog() {
    showDialog(
      context: context,
      builder: (context) => const OpeningEntryDialog(),
    );
  }
}
