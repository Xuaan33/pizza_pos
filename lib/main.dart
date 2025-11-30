// main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shiok_pos_android_app/models/auth_state.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';
import 'package:shiok_pos_android_app/providers/app_init_provider.dart';
import 'package:shiok_pos_android_app/screens/login_screen.dart';
import 'package:shiok_pos_android_app/components/main_layout.dart';
import 'package:shiok_pos_android_app/screens/welcome_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appInitState = ref.watch(appInitProvider);
    final authState = ref.watch(authProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Shiok POS Android App',
      theme: ThemeData(primarySwatch: Colors.blue, fontFamily: 'Raleway'),
      home: appInitState.when(
        initial: () => const WelcomeScreen(),
        loading: () => const WelcomeScreen(),
        completed: () => _buildAppContent(authState),
        error: (error) {
          print('App initialization error: $error');
          return _buildAppContent(authState);
        },
      ),
    );
  }

  Widget _buildAppContent(AuthState authState) {
    return authState.when(
      initial: () => const WelcomeScreen(),
      unauthenticated: () => const LoginPage(),
      authenticated: (
        sid,
        apiKey,
        apiSecret,
        username,
        email,
        fullName,
        posProfile,
        branch,
        paymentMethods,
        taxes,
        hasOpening,
        tier,
        printKitchenOrder,
        openingDate,
        itemsGroups,
        baseUrl, 
        merchantId,
      ) {
        return MainLayout();
      },
    );
  }
}