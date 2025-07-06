import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/screens/login_screen.dart';
import 'package:shiok_pos_android_app/components/main_layout.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Shiok POS Android App',
      theme: ThemeData(primarySwatch: Colors.blue, fontFamily: 'Raleway'),
      home: authState.when(
        initial: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        unauthenticated: () => const LoginPage(),
        authenticated: (sid, apiKey, apiSecret, username, email, fullName, posProfile, branch, paymentMethods, taxes, hasOpening, tier) {
          return MainLayout();
        },
      ),
    );
  }
}