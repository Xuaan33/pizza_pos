// providers/app_init_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shiok_pos_android_app/models/app_init_state.dart';
import 'package:shiok_pos_android_app/providers/auth_provider.dart';

class AppInitNotifier extends StateNotifier<AppInitState> {
  final Ref ref;
  
  AppInitNotifier(this.ref) : super(const AppInitState.initial()) {
    initializeApp();
  }

  Future<void> initializeApp() async {
    state = const AppInitState.loading();
    
    try {
      // Load session (this will trigger auto-login if needed)
      await ref.read(authProvider.notifier).loadSession();
      state = const AppInitState.completed();
    } catch (e) {
      state = AppInitState.error('App initialization failed: $e');
    }
  }

  Future<void> refreshSession() async {
    state = const AppInitState.loading();
    try {
      await ref.read(authProvider.notifier).loadSession(forceRefresh: true);
      state = const AppInitState.completed();
    } catch (e) {
      state = AppInitState.error('Refresh failed: $e');
    }
  }
}

final appInitProvider = StateNotifierProvider<AppInitNotifier, AppInitState>((ref) {
  return AppInitNotifier(ref);
});