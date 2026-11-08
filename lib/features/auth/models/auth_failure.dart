import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/l10n.dart';

/// Everything that can go wrong in an auth flow, independent of language.
/// Screens keep the enum and localize at build time, so a language change
/// re-translates an error that is already on screen.
enum AuthFailure {
  invalidCredentials,
  emailNotConfirmed,
  emailTaken,
  invalidEmail,
  weakPassword,
  samePassword,
  kakaoCancelled,
  kakaoConfig,
  deepLinkMissing,
  sessionExpired,
  linkExpired,
  rateLimited,
  network,
  timeout,
  passwordResetFailed,
  profileLoadFailed,
  permissionDenied,
  nicknameInvalid,
  nicknameSaveFailed,
  unknown;

  String message(AppLocalizations l10n) => switch (this) {
    invalidCredentials => l10n.authErrInvalidCredentials,
    emailNotConfirmed => l10n.authErrEmailNotConfirmed,
    emailTaken => l10n.authErrEmailTaken,
    invalidEmail => l10n.authErrInvalidEmail,
    weakPassword => l10n.authErrWeakPassword,
    samePassword => l10n.authErrSamePassword,
    kakaoCancelled => l10n.authErrKakaoCancelled,
    kakaoConfig => l10n.authErrKakaoConfig,
    deepLinkMissing => l10n.authErrDeepLinkMissing,
    sessionExpired => l10n.authErrSessionExpired,
    linkExpired => l10n.authErrLinkExpired,
    rateLimited => l10n.authErrRateLimited,
    network => l10n.authErrNetwork,
    timeout => l10n.authErrTimeout,
    passwordResetFailed => l10n.authErrPasswordReset,
    profileLoadFailed => l10n.authErrProfileLoad,
    permissionDenied => l10n.errPermissionDenied,
    nicknameInvalid => l10n.nicknameErrInvalidChars,
    nicknameSaveFailed => l10n.nicknameSaveFailed,
    unknown => l10n.authErrUnknown,
  };

  /// Worth offering a "try again" button for.
  bool get retryable => switch (this) {
    network ||
    timeout ||
    rateLimited ||
    profileLoadFailed ||
    kakaoCancelled ||
    deepLinkMissing ||
    unknown => true,
    _ => false,
  };
}

/// Translates whatever the Supabase SDK threw into an [AuthFailure].
/// Never exposes the raw message to the UI (it may contain internals).
AuthFailure authFailureFrom(Object error) {
  if (error is AuthWeakPasswordException) return AuthFailure.weakPassword;
  if (error is AuthRetryableFetchException) return AuthFailure.network;
  if (error is AuthPKCEGrantCodeExchangeError) {
    return AuthFailure.linkExpired;
  }
  if (error is AuthException) {
    final code = (error.code ?? '').toLowerCase();
    final msg = error.message.toLowerCase();
    bool has(String s) => msg.contains(s);

    switch (code) {
      case 'invalid_credentials':
        return AuthFailure.invalidCredentials;
      case 'email_not_confirmed':
        return AuthFailure.emailNotConfirmed;
      case 'user_already_exists':
      case 'email_exists':
        return AuthFailure.emailTaken;
      case 'weak_password':
        return AuthFailure.weakPassword;
      case 'same_password':
        return AuthFailure.samePassword;
      case 'email_address_invalid':
        return AuthFailure.invalidEmail;
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
        return AuthFailure.rateLimited;
      case 'otp_expired':
      case 'flow_state_expired':
      case 'flow_state_not_found':
        return AuthFailure.linkExpired;
      case 'session_expired':
      case 'session_not_found':
      case 'refresh_token_not_found':
      case 'refresh_token_already_used':
        return AuthFailure.sessionExpired;
      case 'provider_disabled':
      case 'oauth_provider_not_supported':
      case 'bad_oauth_callback':
      case 'bad_oauth_state':
      case 'invalid_scope': // KOE205: a consent item is not enabled in Kakao
      case 'server_error':
      case 'unauthorized_client':
        return AuthFailure.kakaoConfig;
      case 'access_denied':
        return AuthFailure.kakaoCancelled;
    }

    if (has('invalid login credentials')) return AuthFailure.invalidCredentials;
    if (has('email not confirmed')) return AuthFailure.emailNotConfirmed;
    if (has('already registered') || has('already been registered')) {
      return AuthFailure.emailTaken;
    }
    if (has('password should be') || has('weak password')) {
      return AuthFailure.weakPassword;
    }
    if (has('different from the old password')) {
      return AuthFailure.samePassword;
    }
    if (has('unable to validate email') || has('invalid email')) {
      return AuthFailure.invalidEmail;
    }
    if (has('rate limit') || has('too many requests')) {
      return AuthFailure.rateLimited;
    }
    if (has('expired') || has('invalid or has expired')) {
      return AuthFailure.linkExpired;
    }
    if (has('refresh token') || has('jwt expired')) {
      return AuthFailure.sessionExpired;
    }
    if (has('external code') ||
        (has('provider') && (has('not enabled') || has('disabled')))) {
      return AuthFailure.kakaoConfig;
    }
    if (error.statusCode == '429') return AuthFailure.rateLimited;
    return AuthFailure.unknown;
  }
  if (error is TimeoutException) return AuthFailure.timeout;
  // flutter_web_auth_2 reports the user closing the system sheet this way.
  if (error is PlatformException && error.code == 'CANCELED') {
    return AuthFailure.kakaoCancelled;
  }
  if (error is PostgrestException) {
    if (error.code == '42501') return AuthFailure.permissionDenied;
    if (error.code == '23514') return AuthFailure.nicknameInvalid;
    return AuthFailure.profileLoadFailed;
  }
  final name = error.runtimeType.toString();
  if (name.contains('SocketException') ||
      name.contains('ClientException') ||
      name.contains('HandshakeException')) {
    return AuthFailure.network;
  }
  return AuthFailure.unknown;
}
