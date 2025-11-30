import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_init_state.freezed.dart';

@freezed
class AppInitState with _$AppInitState {
  const factory AppInitState.initial() = AppInitInitial;
  const factory AppInitState.loading() = AppInitLoading;
  const factory AppInitState.completed() = AppInitCompleted;
  const factory AppInitState.error(String message) = AppInitError;
}