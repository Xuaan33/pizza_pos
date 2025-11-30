// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'app_init_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$AppInitState {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function() loading,
    required TResult Function() completed,
    required TResult Function(String message) error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function()? loading,
    TResult? Function()? completed,
    TResult? Function(String message)? error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function()? loading,
    TResult Function()? completed,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(AppInitInitial value) initial,
    required TResult Function(AppInitLoading value) loading,
    required TResult Function(AppInitCompleted value) completed,
    required TResult Function(AppInitError value) error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(AppInitInitial value)? initial,
    TResult? Function(AppInitLoading value)? loading,
    TResult? Function(AppInitCompleted value)? completed,
    TResult? Function(AppInitError value)? error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(AppInitInitial value)? initial,
    TResult Function(AppInitLoading value)? loading,
    TResult Function(AppInitCompleted value)? completed,
    TResult Function(AppInitError value)? error,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AppInitStateCopyWith<$Res> {
  factory $AppInitStateCopyWith(
          AppInitState value, $Res Function(AppInitState) then) =
      _$AppInitStateCopyWithImpl<$Res, AppInitState>;
}

/// @nodoc
class _$AppInitStateCopyWithImpl<$Res, $Val extends AppInitState>
    implements $AppInitStateCopyWith<$Res> {
  _$AppInitStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AppInitState
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$AppInitInitialImplCopyWith<$Res> {
  factory _$$AppInitInitialImplCopyWith(_$AppInitInitialImpl value,
          $Res Function(_$AppInitInitialImpl) then) =
      __$$AppInitInitialImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$AppInitInitialImplCopyWithImpl<$Res>
    extends _$AppInitStateCopyWithImpl<$Res, _$AppInitInitialImpl>
    implements _$$AppInitInitialImplCopyWith<$Res> {
  __$$AppInitInitialImplCopyWithImpl(
      _$AppInitInitialImpl _value, $Res Function(_$AppInitInitialImpl) _then)
      : super(_value, _then);

  /// Create a copy of AppInitState
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$AppInitInitialImpl implements AppInitInitial {
  const _$AppInitInitialImpl();

  @override
  String toString() {
    return 'AppInitState.initial()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$AppInitInitialImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function() loading,
    required TResult Function() completed,
    required TResult Function(String message) error,
  }) {
    return initial();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function()? loading,
    TResult? Function()? completed,
    TResult? Function(String message)? error,
  }) {
    return initial?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function()? loading,
    TResult Function()? completed,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) {
    if (initial != null) {
      return initial();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(AppInitInitial value) initial,
    required TResult Function(AppInitLoading value) loading,
    required TResult Function(AppInitCompleted value) completed,
    required TResult Function(AppInitError value) error,
  }) {
    return initial(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(AppInitInitial value)? initial,
    TResult? Function(AppInitLoading value)? loading,
    TResult? Function(AppInitCompleted value)? completed,
    TResult? Function(AppInitError value)? error,
  }) {
    return initial?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(AppInitInitial value)? initial,
    TResult Function(AppInitLoading value)? loading,
    TResult Function(AppInitCompleted value)? completed,
    TResult Function(AppInitError value)? error,
    required TResult orElse(),
  }) {
    if (initial != null) {
      return initial(this);
    }
    return orElse();
  }
}

abstract class AppInitInitial implements AppInitState {
  const factory AppInitInitial() = _$AppInitInitialImpl;
}

/// @nodoc
abstract class _$$AppInitLoadingImplCopyWith<$Res> {
  factory _$$AppInitLoadingImplCopyWith(_$AppInitLoadingImpl value,
          $Res Function(_$AppInitLoadingImpl) then) =
      __$$AppInitLoadingImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$AppInitLoadingImplCopyWithImpl<$Res>
    extends _$AppInitStateCopyWithImpl<$Res, _$AppInitLoadingImpl>
    implements _$$AppInitLoadingImplCopyWith<$Res> {
  __$$AppInitLoadingImplCopyWithImpl(
      _$AppInitLoadingImpl _value, $Res Function(_$AppInitLoadingImpl) _then)
      : super(_value, _then);

  /// Create a copy of AppInitState
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$AppInitLoadingImpl implements AppInitLoading {
  const _$AppInitLoadingImpl();

  @override
  String toString() {
    return 'AppInitState.loading()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$AppInitLoadingImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function() loading,
    required TResult Function() completed,
    required TResult Function(String message) error,
  }) {
    return loading();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function()? loading,
    TResult? Function()? completed,
    TResult? Function(String message)? error,
  }) {
    return loading?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function()? loading,
    TResult Function()? completed,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) {
    if (loading != null) {
      return loading();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(AppInitInitial value) initial,
    required TResult Function(AppInitLoading value) loading,
    required TResult Function(AppInitCompleted value) completed,
    required TResult Function(AppInitError value) error,
  }) {
    return loading(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(AppInitInitial value)? initial,
    TResult? Function(AppInitLoading value)? loading,
    TResult? Function(AppInitCompleted value)? completed,
    TResult? Function(AppInitError value)? error,
  }) {
    return loading?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(AppInitInitial value)? initial,
    TResult Function(AppInitLoading value)? loading,
    TResult Function(AppInitCompleted value)? completed,
    TResult Function(AppInitError value)? error,
    required TResult orElse(),
  }) {
    if (loading != null) {
      return loading(this);
    }
    return orElse();
  }
}

abstract class AppInitLoading implements AppInitState {
  const factory AppInitLoading() = _$AppInitLoadingImpl;
}

/// @nodoc
abstract class _$$AppInitCompletedImplCopyWith<$Res> {
  factory _$$AppInitCompletedImplCopyWith(_$AppInitCompletedImpl value,
          $Res Function(_$AppInitCompletedImpl) then) =
      __$$AppInitCompletedImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$AppInitCompletedImplCopyWithImpl<$Res>
    extends _$AppInitStateCopyWithImpl<$Res, _$AppInitCompletedImpl>
    implements _$$AppInitCompletedImplCopyWith<$Res> {
  __$$AppInitCompletedImplCopyWithImpl(_$AppInitCompletedImpl _value,
      $Res Function(_$AppInitCompletedImpl) _then)
      : super(_value, _then);

  /// Create a copy of AppInitState
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$AppInitCompletedImpl implements AppInitCompleted {
  const _$AppInitCompletedImpl();

  @override
  String toString() {
    return 'AppInitState.completed()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$AppInitCompletedImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function() loading,
    required TResult Function() completed,
    required TResult Function(String message) error,
  }) {
    return completed();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function()? loading,
    TResult? Function()? completed,
    TResult? Function(String message)? error,
  }) {
    return completed?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function()? loading,
    TResult Function()? completed,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) {
    if (completed != null) {
      return completed();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(AppInitInitial value) initial,
    required TResult Function(AppInitLoading value) loading,
    required TResult Function(AppInitCompleted value) completed,
    required TResult Function(AppInitError value) error,
  }) {
    return completed(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(AppInitInitial value)? initial,
    TResult? Function(AppInitLoading value)? loading,
    TResult? Function(AppInitCompleted value)? completed,
    TResult? Function(AppInitError value)? error,
  }) {
    return completed?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(AppInitInitial value)? initial,
    TResult Function(AppInitLoading value)? loading,
    TResult Function(AppInitCompleted value)? completed,
    TResult Function(AppInitError value)? error,
    required TResult orElse(),
  }) {
    if (completed != null) {
      return completed(this);
    }
    return orElse();
  }
}

abstract class AppInitCompleted implements AppInitState {
  const factory AppInitCompleted() = _$AppInitCompletedImpl;
}

/// @nodoc
abstract class _$$AppInitErrorImplCopyWith<$Res> {
  factory _$$AppInitErrorImplCopyWith(
          _$AppInitErrorImpl value, $Res Function(_$AppInitErrorImpl) then) =
      __$$AppInitErrorImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String message});
}

/// @nodoc
class __$$AppInitErrorImplCopyWithImpl<$Res>
    extends _$AppInitStateCopyWithImpl<$Res, _$AppInitErrorImpl>
    implements _$$AppInitErrorImplCopyWith<$Res> {
  __$$AppInitErrorImplCopyWithImpl(
      _$AppInitErrorImpl _value, $Res Function(_$AppInitErrorImpl) _then)
      : super(_value, _then);

  /// Create a copy of AppInitState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? message = null,
  }) {
    return _then(_$AppInitErrorImpl(
      null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$AppInitErrorImpl implements AppInitError {
  const _$AppInitErrorImpl(this.message);

  @override
  final String message;

  @override
  String toString() {
    return 'AppInitState.error(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AppInitErrorImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  /// Create a copy of AppInitState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AppInitErrorImplCopyWith<_$AppInitErrorImpl> get copyWith =>
      __$$AppInitErrorImplCopyWithImpl<_$AppInitErrorImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function() loading,
    required TResult Function() completed,
    required TResult Function(String message) error,
  }) {
    return error(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function()? loading,
    TResult? Function()? completed,
    TResult? Function(String message)? error,
  }) {
    return error?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function()? loading,
    TResult Function()? completed,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) {
    if (error != null) {
      return error(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(AppInitInitial value) initial,
    required TResult Function(AppInitLoading value) loading,
    required TResult Function(AppInitCompleted value) completed,
    required TResult Function(AppInitError value) error,
  }) {
    return error(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(AppInitInitial value)? initial,
    TResult? Function(AppInitLoading value)? loading,
    TResult? Function(AppInitCompleted value)? completed,
    TResult? Function(AppInitError value)? error,
  }) {
    return error?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(AppInitInitial value)? initial,
    TResult Function(AppInitLoading value)? loading,
    TResult Function(AppInitCompleted value)? completed,
    TResult Function(AppInitError value)? error,
    required TResult orElse(),
  }) {
    if (error != null) {
      return error(this);
    }
    return orElse();
  }
}

abstract class AppInitError implements AppInitState {
  const factory AppInitError(final String message) = _$AppInitErrorImpl;

  String get message;

  /// Create a copy of AppInitState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AppInitErrorImplCopyWith<_$AppInitErrorImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
