// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'auth_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$AuthState {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function(
            String sid,
            String apiKey,
            String apiSecret,
            String username,
            String email,
            String fullName,
            String posProfile,
            String branch,
            List<Map<String, dynamic>> paymentMethods,
            List<Map<String, dynamic>> taxes,
            bool hasOpening,
            String tier)
        authenticated,
    required TResult Function() unauthenticated,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function(
            String sid,
            String apiKey,
            String apiSecret,
            String username,
            String email,
            String fullName,
            String posProfile,
            String branch,
            List<Map<String, dynamic>> paymentMethods,
            List<Map<String, dynamic>> taxes,
            bool hasOpening,
            String tier)?
        authenticated,
    TResult? Function()? unauthenticated,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function(
            String sid,
            String apiKey,
            String apiSecret,
            String username,
            String email,
            String fullName,
            String posProfile,
            String branch,
            List<Map<String, dynamic>> paymentMethods,
            List<Map<String, dynamic>> taxes,
            bool hasOpening,
            String tier)?
        authenticated,
    TResult Function()? unauthenticated,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_Initial value) initial,
    required TResult Function(_Authenticated value) authenticated,
    required TResult Function(_Unauthenticated value) unauthenticated,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Initial value)? initial,
    TResult? Function(_Authenticated value)? authenticated,
    TResult? Function(_Unauthenticated value)? unauthenticated,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Initial value)? initial,
    TResult Function(_Authenticated value)? authenticated,
    TResult Function(_Unauthenticated value)? unauthenticated,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AuthStateCopyWith<$Res> {
  factory $AuthStateCopyWith(AuthState value, $Res Function(AuthState) then) =
      _$AuthStateCopyWithImpl<$Res, AuthState>;
}

/// @nodoc
class _$AuthStateCopyWithImpl<$Res, $Val extends AuthState>
    implements $AuthStateCopyWith<$Res> {
  _$AuthStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AuthState
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$InitialImplCopyWith<$Res> {
  factory _$$InitialImplCopyWith(
          _$InitialImpl value, $Res Function(_$InitialImpl) then) =
      __$$InitialImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$InitialImplCopyWithImpl<$Res>
    extends _$AuthStateCopyWithImpl<$Res, _$InitialImpl>
    implements _$$InitialImplCopyWith<$Res> {
  __$$InitialImplCopyWithImpl(
      _$InitialImpl _value, $Res Function(_$InitialImpl) _then)
      : super(_value, _then);

  /// Create a copy of AuthState
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$InitialImpl implements _Initial {
  const _$InitialImpl();

  @override
  String toString() {
    return 'AuthState.initial()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$InitialImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function(
            String sid,
            String apiKey,
            String apiSecret,
            String username,
            String email,
            String fullName,
            String posProfile,
            String branch,
            List<Map<String, dynamic>> paymentMethods,
            List<Map<String, dynamic>> taxes,
            bool hasOpening,
            String tier)
        authenticated,
    required TResult Function() unauthenticated,
  }) {
    return initial();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function(
            String sid,
            String apiKey,
            String apiSecret,
            String username,
            String email,
            String fullName,
            String posProfile,
            String branch,
            List<Map<String, dynamic>> paymentMethods,
            List<Map<String, dynamic>> taxes,
            bool hasOpening,
            String tier)?
        authenticated,
    TResult? Function()? unauthenticated,
  }) {
    return initial?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function(
            String sid,
            String apiKey,
            String apiSecret,
            String username,
            String email,
            String fullName,
            String posProfile,
            String branch,
            List<Map<String, dynamic>> paymentMethods,
            List<Map<String, dynamic>> taxes,
            bool hasOpening,
            String tier)?
        authenticated,
    TResult Function()? unauthenticated,
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
    required TResult Function(_Initial value) initial,
    required TResult Function(_Authenticated value) authenticated,
    required TResult Function(_Unauthenticated value) unauthenticated,
  }) {
    return initial(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Initial value)? initial,
    TResult? Function(_Authenticated value)? authenticated,
    TResult? Function(_Unauthenticated value)? unauthenticated,
  }) {
    return initial?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Initial value)? initial,
    TResult Function(_Authenticated value)? authenticated,
    TResult Function(_Unauthenticated value)? unauthenticated,
    required TResult orElse(),
  }) {
    if (initial != null) {
      return initial(this);
    }
    return orElse();
  }
}

abstract class _Initial implements AuthState {
  const factory _Initial() = _$InitialImpl;
}

/// @nodoc
abstract class _$$AuthenticatedImplCopyWith<$Res> {
  factory _$$AuthenticatedImplCopyWith(
          _$AuthenticatedImpl value, $Res Function(_$AuthenticatedImpl) then) =
      __$$AuthenticatedImplCopyWithImpl<$Res>;
  @useResult
  $Res call(
      {String sid,
      String apiKey,
      String apiSecret,
      String username,
      String email,
      String fullName,
      String posProfile,
      String branch,
      List<Map<String, dynamic>> paymentMethods,
      List<Map<String, dynamic>> taxes,
      bool hasOpening,
      String tier});
}

/// @nodoc
class __$$AuthenticatedImplCopyWithImpl<$Res>
    extends _$AuthStateCopyWithImpl<$Res, _$AuthenticatedImpl>
    implements _$$AuthenticatedImplCopyWith<$Res> {
  __$$AuthenticatedImplCopyWithImpl(
      _$AuthenticatedImpl _value, $Res Function(_$AuthenticatedImpl) _then)
      : super(_value, _then);

  /// Create a copy of AuthState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sid = null,
    Object? apiKey = null,
    Object? apiSecret = null,
    Object? username = null,
    Object? email = null,
    Object? fullName = null,
    Object? posProfile = null,
    Object? branch = null,
    Object? paymentMethods = null,
    Object? taxes = null,
    Object? hasOpening = null,
    Object? tier = null,
  }) {
    return _then(_$AuthenticatedImpl(
      sid: null == sid
          ? _value.sid
          : sid // ignore: cast_nullable_to_non_nullable
              as String,
      apiKey: null == apiKey
          ? _value.apiKey
          : apiKey // ignore: cast_nullable_to_non_nullable
              as String,
      apiSecret: null == apiSecret
          ? _value.apiSecret
          : apiSecret // ignore: cast_nullable_to_non_nullable
              as String,
      username: null == username
          ? _value.username
          : username // ignore: cast_nullable_to_non_nullable
              as String,
      email: null == email
          ? _value.email
          : email // ignore: cast_nullable_to_non_nullable
              as String,
      fullName: null == fullName
          ? _value.fullName
          : fullName // ignore: cast_nullable_to_non_nullable
              as String,
      posProfile: null == posProfile
          ? _value.posProfile
          : posProfile // ignore: cast_nullable_to_non_nullable
              as String,
      branch: null == branch
          ? _value.branch
          : branch // ignore: cast_nullable_to_non_nullable
              as String,
      paymentMethods: null == paymentMethods
          ? _value._paymentMethods
          : paymentMethods // ignore: cast_nullable_to_non_nullable
              as List<Map<String, dynamic>>,
      taxes: null == taxes
          ? _value._taxes
          : taxes // ignore: cast_nullable_to_non_nullable
              as List<Map<String, dynamic>>,
      hasOpening: null == hasOpening
          ? _value.hasOpening
          : hasOpening // ignore: cast_nullable_to_non_nullable
              as bool,
      tier: null == tier
          ? _value.tier
          : tier // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$AuthenticatedImpl implements _Authenticated {
  const _$AuthenticatedImpl(
      {required this.sid,
      required this.apiKey,
      required this.apiSecret,
      required this.username,
      required this.email,
      required this.fullName,
      required this.posProfile,
      required this.branch,
      required final List<Map<String, dynamic>> paymentMethods,
      required final List<Map<String, dynamic>> taxes,
      required this.hasOpening,
      required this.tier})
      : _paymentMethods = paymentMethods,
        _taxes = taxes;

  @override
  final String sid;
  @override
  final String apiKey;
  @override
  final String apiSecret;
  @override
  final String username;
  @override
  final String email;
  @override
  final String fullName;
  @override
  final String posProfile;
  @override
  final String branch;
  final List<Map<String, dynamic>> _paymentMethods;
  @override
  List<Map<String, dynamic>> get paymentMethods {
    if (_paymentMethods is EqualUnmodifiableListView) return _paymentMethods;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_paymentMethods);
  }

  final List<Map<String, dynamic>> _taxes;
  @override
  List<Map<String, dynamic>> get taxes {
    if (_taxes is EqualUnmodifiableListView) return _taxes;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_taxes);
  }

  @override
  final bool hasOpening;
  @override
  final String tier;

  @override
  String toString() {
    return 'AuthState.authenticated(sid: $sid, apiKey: $apiKey, apiSecret: $apiSecret, username: $username, email: $email, fullName: $fullName, posProfile: $posProfile, branch: $branch, paymentMethods: $paymentMethods, taxes: $taxes, hasOpening: $hasOpening, tier: $tier)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AuthenticatedImpl &&
            (identical(other.sid, sid) || other.sid == sid) &&
            (identical(other.apiKey, apiKey) || other.apiKey == apiKey) &&
            (identical(other.apiSecret, apiSecret) ||
                other.apiSecret == apiSecret) &&
            (identical(other.username, username) ||
                other.username == username) &&
            (identical(other.email, email) || other.email == email) &&
            (identical(other.fullName, fullName) ||
                other.fullName == fullName) &&
            (identical(other.posProfile, posProfile) ||
                other.posProfile == posProfile) &&
            (identical(other.branch, branch) || other.branch == branch) &&
            const DeepCollectionEquality()
                .equals(other._paymentMethods, _paymentMethods) &&
            const DeepCollectionEquality().equals(other._taxes, _taxes) &&
            (identical(other.hasOpening, hasOpening) ||
                other.hasOpening == hasOpening) &&
            (identical(other.tier, tier) || other.tier == tier));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      sid,
      apiKey,
      apiSecret,
      username,
      email,
      fullName,
      posProfile,
      branch,
      const DeepCollectionEquality().hash(_paymentMethods),
      const DeepCollectionEquality().hash(_taxes),
      hasOpening,
      tier);

  /// Create a copy of AuthState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AuthenticatedImplCopyWith<_$AuthenticatedImpl> get copyWith =>
      __$$AuthenticatedImplCopyWithImpl<_$AuthenticatedImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function(
            String sid,
            String apiKey,
            String apiSecret,
            String username,
            String email,
            String fullName,
            String posProfile,
            String branch,
            List<Map<String, dynamic>> paymentMethods,
            List<Map<String, dynamic>> taxes,
            bool hasOpening,
            String tier)
        authenticated,
    required TResult Function() unauthenticated,
  }) {
    return authenticated(sid, apiKey, apiSecret, username, email, fullName,
        posProfile, branch, paymentMethods, taxes, hasOpening, tier);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function(
            String sid,
            String apiKey,
            String apiSecret,
            String username,
            String email,
            String fullName,
            String posProfile,
            String branch,
            List<Map<String, dynamic>> paymentMethods,
            List<Map<String, dynamic>> taxes,
            bool hasOpening,
            String tier)?
        authenticated,
    TResult? Function()? unauthenticated,
  }) {
    return authenticated?.call(sid, apiKey, apiSecret, username, email,
        fullName, posProfile, branch, paymentMethods, taxes, hasOpening, tier);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function(
            String sid,
            String apiKey,
            String apiSecret,
            String username,
            String email,
            String fullName,
            String posProfile,
            String branch,
            List<Map<String, dynamic>> paymentMethods,
            List<Map<String, dynamic>> taxes,
            bool hasOpening,
            String tier)?
        authenticated,
    TResult Function()? unauthenticated,
    required TResult orElse(),
  }) {
    if (authenticated != null) {
      return authenticated(sid, apiKey, apiSecret, username, email, fullName,
          posProfile, branch, paymentMethods, taxes, hasOpening, tier);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_Initial value) initial,
    required TResult Function(_Authenticated value) authenticated,
    required TResult Function(_Unauthenticated value) unauthenticated,
  }) {
    return authenticated(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Initial value)? initial,
    TResult? Function(_Authenticated value)? authenticated,
    TResult? Function(_Unauthenticated value)? unauthenticated,
  }) {
    return authenticated?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Initial value)? initial,
    TResult Function(_Authenticated value)? authenticated,
    TResult Function(_Unauthenticated value)? unauthenticated,
    required TResult orElse(),
  }) {
    if (authenticated != null) {
      return authenticated(this);
    }
    return orElse();
  }
}

abstract class _Authenticated implements AuthState {
  const factory _Authenticated(
      {required final String sid,
      required final String apiKey,
      required final String apiSecret,
      required final String username,
      required final String email,
      required final String fullName,
      required final String posProfile,
      required final String branch,
      required final List<Map<String, dynamic>> paymentMethods,
      required final List<Map<String, dynamic>> taxes,
      required final bool hasOpening,
      required final String tier}) = _$AuthenticatedImpl;

  String get sid;
  String get apiKey;
  String get apiSecret;
  String get username;
  String get email;
  String get fullName;
  String get posProfile;
  String get branch;
  List<Map<String, dynamic>> get paymentMethods;
  List<Map<String, dynamic>> get taxes;
  bool get hasOpening;
  String get tier;

  /// Create a copy of AuthState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AuthenticatedImplCopyWith<_$AuthenticatedImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$UnauthenticatedImplCopyWith<$Res> {
  factory _$$UnauthenticatedImplCopyWith(_$UnauthenticatedImpl value,
          $Res Function(_$UnauthenticatedImpl) then) =
      __$$UnauthenticatedImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$UnauthenticatedImplCopyWithImpl<$Res>
    extends _$AuthStateCopyWithImpl<$Res, _$UnauthenticatedImpl>
    implements _$$UnauthenticatedImplCopyWith<$Res> {
  __$$UnauthenticatedImplCopyWithImpl(
      _$UnauthenticatedImpl _value, $Res Function(_$UnauthenticatedImpl) _then)
      : super(_value, _then);

  /// Create a copy of AuthState
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$UnauthenticatedImpl implements _Unauthenticated {
  const _$UnauthenticatedImpl();

  @override
  String toString() {
    return 'AuthState.unauthenticated()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$UnauthenticatedImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function(
            String sid,
            String apiKey,
            String apiSecret,
            String username,
            String email,
            String fullName,
            String posProfile,
            String branch,
            List<Map<String, dynamic>> paymentMethods,
            List<Map<String, dynamic>> taxes,
            bool hasOpening,
            String tier)
        authenticated,
    required TResult Function() unauthenticated,
  }) {
    return unauthenticated();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function(
            String sid,
            String apiKey,
            String apiSecret,
            String username,
            String email,
            String fullName,
            String posProfile,
            String branch,
            List<Map<String, dynamic>> paymentMethods,
            List<Map<String, dynamic>> taxes,
            bool hasOpening,
            String tier)?
        authenticated,
    TResult? Function()? unauthenticated,
  }) {
    return unauthenticated?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function(
            String sid,
            String apiKey,
            String apiSecret,
            String username,
            String email,
            String fullName,
            String posProfile,
            String branch,
            List<Map<String, dynamic>> paymentMethods,
            List<Map<String, dynamic>> taxes,
            bool hasOpening,
            String tier)?
        authenticated,
    TResult Function()? unauthenticated,
    required TResult orElse(),
  }) {
    if (unauthenticated != null) {
      return unauthenticated();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_Initial value) initial,
    required TResult Function(_Authenticated value) authenticated,
    required TResult Function(_Unauthenticated value) unauthenticated,
  }) {
    return unauthenticated(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Initial value)? initial,
    TResult? Function(_Authenticated value)? authenticated,
    TResult? Function(_Unauthenticated value)? unauthenticated,
  }) {
    return unauthenticated?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Initial value)? initial,
    TResult Function(_Authenticated value)? authenticated,
    TResult Function(_Unauthenticated value)? unauthenticated,
    required TResult orElse(),
  }) {
    if (unauthenticated != null) {
      return unauthenticated(this);
    }
    return orElse();
  }
}

abstract class _Unauthenticated implements AuthState {
  const factory _Unauthenticated() = _$UnauthenticatedImpl;
}
