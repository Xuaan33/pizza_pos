import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_state.freezed.dart';

@freezed
class AuthState with _$AuthState {
  const factory AuthState.initial() = _Initial;
  const factory AuthState.authenticated({
    required String sid,
    required String apiKey,
    required String apiSecret,
    required String username,
    required String email,
    required String fullName,
    required String posProfile,
    required String branch,
  }) = _Authenticated;
  const factory AuthState.unauthenticated() = _Unauthenticated;
}