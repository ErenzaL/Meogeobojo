import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_language.dart';
import '../../../core/l10n/language_controller.dart';
import '../models/auth_failure.dart';
import '../models/auth_snapshot.dart';
import '../../profile/models/nickname.dart';
import '../models/user_profile.dart';
import '../repositories/profile_repository.dart';
import '../services/auth_gateway.dart';

final authGatewayProvider = Provider<AuthGateway>(
  (ref) => SupabaseAuthGateway.instance(),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => SupabaseProfileRepository(Supabase.instance.client),
);

/// Single source of truth for "who is using the app". Everything else
/// (favorites, MY, onboarding routing) derives from this.
final authControllerProvider = NotifierProvider<AuthController, AuthSnapshot>(
  AuthController.new,
);

/// The signed-in user, or null for guests (and during email verification,
/// when no session exists yet).
final currentUserProvider = Provider<User?>(
  (ref) => ref.watch(authControllerProvider.select((s) => s.user)),
);

/// How long to wait after the app returns from the Kakao browser before
/// concluding that no callback is coming. A provider so tests can shorten it.
final kakaoCallbackGraceProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 6),
);

class AuthController extends Notifier<AuthSnapshot> {
  int _loadSeq = 0;
  Timer? _callbackTimer;
  bool _kakaoInFlight = false;
  DateTime? _lastAdoptAt;

  AuthGateway get _gateway => ref.read(authGatewayProvider);

  @override
  AuthSnapshot build() {
    final gateway = ref.watch(authGatewayProvider);
    final sub = gateway.events.listen(_onEvent, onError: _onStreamError);
    ref.onDispose(() {
      sub.cancel();
      _callbackTimer?.cancel();
    });

    // Push the language to the account when the user changes it while signed in.
    ref.listen<LanguageSetting>(languageProvider, (prev, next) {
      final id = state.user?.id;
      if (id == null || !next.explicit) return;
      if (prev?.language == next.language) return;
      // Already what the account has (e.g. we just restored it from there).
      if (state.profile?.preferredLanguage == next.language.code) return;
      _pushLanguage(id, next.language);
    });

    listenSelf((prev, next) {
      if (prev?.status != next.status || prev?.user?.id != next.user?.id) {
        _trace('status ${prev?.status.name} -> ${next.status.name}');
      }
    });

    // supabase_flutter restores the stored session before runApp, so this is
    // synchronous. The profile (and so onboarding status) follows.
    final user = gateway.currentUser;
    if (user == null) return const AuthSnapshot.guest();
    scheduleMicrotask(() => _loadProfile(user));
    return AuthSnapshot(status: AuthStatus.initializing, user: user);
  }

  /// Debug-only breadcrumbs for diagnosing sign-in problems. Event names and
  /// error codes only: never tokens, URLs or user data.
  void _trace(String message) {
    if (kDebugMode) debugPrint('[auth] $message');
  }

  // ---- stream handling ----------------------------------------------------

  void _onEvent(AuthState data) {
    final user = data.session?.user;
    _trace('event ${data.event.name} session=${data.session != null}');
    switch (data.event) {
      case AuthChangeEvent.signedOut:
      // ignore: deprecated_member_use
      case AuthChangeEvent.userDeleted:
        _callbackTimer?.cancel();
        _loadSeq++;
        state = AuthSnapshot(status: AuthStatus.guest, failure: state.failure);
      case AuthChangeEvent.passwordRecovery:
        state = state.copyWith(recoveryActive: true);
        if (user != null) _adopt(user);
      case AuthChangeEvent.initialSession:
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.tokenRefreshed:
      case AuthChangeEvent.userUpdated:
      case AuthChangeEvent.mfaChallengeVerified:
        if (user != null) _adopt(user);
    }
  }

  void _onStreamError(Object error, StackTrace _) {
    final failure = authFailureFrom(error);
    _trace(
      'stream error code=${error is AuthException ? error.code : error.runtimeType} -> ${failure.name}',
    );
    final signedIn = state.user != null;
    // A flaky connection during background refresh must not nag or sign out.
    if (signedIn &&
        (failure == AuthFailure.network || failure == AuthFailure.timeout)) {
      return;
    }
    // A second delivery of a callback we already exchanged is rejected by
    // Supabase (the code is single-use). It is not a real failure.
    if (signedIn &&
        failure == AuthFailure.linkExpired &&
        _lastAdoptAt != null &&
        DateTime.now().difference(_lastAdoptAt!) <
            const Duration(seconds: 15)) {
      _trace('ignoring duplicate callback error right after sign-in');
      return;
    }
    _callbackTimer?.cancel();
    if (failure == AuthFailure.sessionExpired && signedIn) {
      _loadSeq++;
      _trace('signing out because the session expired');
      unawaited(_gateway.signOut().catchError((_) {}));
      state = AuthSnapshot(status: AuthStatus.guest, failure: failure);
      return;
    }
    state = state.copyWith(
      status: state.status == AuthStatus.authenticating
          ? AuthStatus.guest
          : state.status,
      failure: () => failure,
    );
  }

  /// Applies a session's user. Idempotent: repeated events for the same user
  /// (token refresh, resume, duplicate callbacks) never reload or re-route.
  void _adopt(User user) {
    _callbackTimer?.cancel();
    _lastAdoptAt = DateTime.now();
    final sameUser = state.user?.id == user.id;
    if (sameUser) {
      if (state.profile != null || state.status == AuthStatus.initializing) {
        state = state.copyWith(user: () => user);
        return;
      }
      if (state.status == AuthStatus.error) {
        state = state.copyWith(user: () => user);
        return;
      }
    }
    state = AuthSnapshot(
      status: AuthStatus.initializing,
      user: user,
      recoveryActive: state.recoveryActive,
    );
    unawaited(_loadProfile(user));
  }

  Future<void> _loadProfile(User user) async {
    final seq = ++_loadSeq;
    try {
      final profile = await ref
          .read(profileRepositoryProvider)
          .loadOrCreate(user);
      if (seq != _loadSeq || state.user?.id != user.id) return;
      state = state.copyWith(
        status: _statusFor(profile),
        profile: () => profile,
        failure: () => null,
      );
      _reconcileLanguage(profile);
    } catch (e) {
      if (seq != _loadSeq || state.user?.id != user.id) return;
      debugPrint('profile load failed: ${e.runtimeType}');
      final f = authFailureFrom(e);
      state = state.copyWith(
        status: AuthStatus.error,
        failure: () =>
            f == AuthFailure.unknown ? AuthFailure.profileLoadFailed : f,
      );
    }
  }

  // ---- language sync ------------------------------------------------------

  /// Local choice always wins. If the device never had an explicit choice, the
  /// account's saved language is restored instead.
  void _reconcileLanguage(UserProfile profile) {
    final setting = ref.read(languageProvider);
    if (setting.explicit) {
      if (profile.preferredLanguage != setting.language.code) {
        _pushLanguage(profile.id, setting.language);
      }
    } else if (profile.language != null) {
      unawaited(
        ref.read(languageProvider.notifier).adoptFromAccount(profile.language!),
      );
    }
  }

  void _pushLanguage(String userId, AppLanguage language) {
    ref
        .read(profileRepositoryProvider)
        .updateLanguage(userId, language.code)
        .then<void>((_) {
          final p = state.profile;
          if (p != null && state.user?.id == userId) {
            state = state.copyWith(
              profile: () => p.copyWith(preferredLanguage: language.code),
            );
          }
        })
        // Best effort: guests and offline users must never be blocked by this.
        .catchError((Object _) {});
  }

  // ---- commands -----------------------------------------------------------

  void _guestWithFailure(AuthFailure f) {
    state = AuthSnapshot(
      status: AuthStatus.guest,
      failure: f,
      recoveryActive: state.recoveryActive,
    );
  }

  /// Returns null on success (navigation is driven by [state]), else why not.
  Future<AuthFailure?> signInWithEmail(String email, String password) async {
    state = state.copyWith(
      status: AuthStatus.authenticating,
      failure: () => null,
    );
    try {
      final res = await _gateway.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final user = res.session?.user;
      if (user == null) {
        _guestWithFailure(AuthFailure.unknown);
        return AuthFailure.unknown;
      }
      _adopt(user);
      return null;
    } catch (e) {
      final f = authFailureFrom(e);
      _guestWithFailure(f);
      return f;
    }
  }

  Future<AuthFailure?> signUpWithEmail(String email, String password) async {
    state = state.copyWith(
      status: AuthStatus.authenticating,
      failure: () => null,
    );
    try {
      final res = await _gateway.signUp(
        email: email.trim(),
        password: password,
      );
      final session = res.session;
      if (session != null) {
        // Email confirmation is disabled on the project: a real session exists.
        _adopt(session.user);
        return null;
      }
      final user = res.user;
      if (user == null) {
        _guestWithFailure(AuthFailure.unknown);
        return AuthFailure.unknown;
      }
      // With "Confirm email" on, Supabase hides that an address is taken by
      // returning a user with no identities and no session.
      if (user.identities != null && user.identities!.isEmpty) {
        _guestWithFailure(AuthFailure.emailTaken);
        return AuthFailure.emailTaken;
      }
      state = AuthSnapshot(
        status: AuthStatus.emailVerificationPending,
        pendingEmail: email.trim(),
      );
      return null;
    } catch (e) {
      final f = authFailureFrom(e);
      _guestWithFailure(f);
      return f;
    }
  }

  /// Opens the Kakao consent page. The browser opening is not a login: the
  /// state stays `authenticating` until a session arrives on the stream.
  Future<AuthFailure?> startKakaoSignIn() async {
    state = state.copyWith(
      status: AuthStatus.authenticating,
      failure: () => null,
    );
    _kakaoInFlight = true;
    try {
      final opened = await _gateway.signInWithKakao();
      if (!opened) {
        _guestWithFailure(AuthFailure.unknown);
        return AuthFailure.unknown;
      }
      return null;
    } catch (e) {
      final f = authFailureFrom(e);
      _guestWithFailure(f);
      return f;
    } finally {
      _kakaoInFlight = false;
    }
  }

  /// Call when the app returns to the foreground during Kakao sign-in. If no
  /// callback has produced a session shortly after, the attempt is treated as
  /// cancelled / not received so the user is never stuck on a spinner.
  void kakaoReturnedToApp() {
    // While the system auth session is still awaited, its own result (success,
    // cancel or error) decides; a timer would only race it.
    if (_kakaoInFlight) return;
    if (state.status != AuthStatus.authenticating) return;
    _callbackTimer?.cancel();
    _callbackTimer = Timer(ref.read(kakaoCallbackGraceProvider), () {
      if (state.status == AuthStatus.authenticating) {
        _guestWithFailure(AuthFailure.deepLinkMissing);
      }
    });
  }

  /// User pressed cancel while waiting.
  void cancelAuthenticating() {
    if (state.status != AuthStatus.authenticating) return;
    _callbackTimer?.cancel();
    _guestWithFailure(AuthFailure.kakaoCancelled);
  }

  Future<AuthFailure?> resendVerification(String email) async {
    try {
      await _gateway.resendSignupEmail(email.trim());
      state = state.copyWith(
        status: AuthStatus.emailVerificationPending,
        pendingEmail: () => email.trim(),
        failure: () => null,
      );
      return null;
    } catch (e) {
      return authFailureFrom(e);
    }
  }

  void cancelVerification() {
    if (state.status == AuthStatus.emailVerificationPending) {
      state = const AuthSnapshot.guest();
    }
  }

  Future<AuthFailure?> sendPasswordReset(String email) async {
    try {
      await _gateway.sendPasswordReset(email.trim());
      return null;
    } catch (e) {
      final f = authFailureFrom(e);
      return f == AuthFailure.unknown ? AuthFailure.passwordResetFailed : f;
    }
  }

  Future<AuthFailure?> updatePassword(String newPassword) async {
    try {
      await _gateway.updatePassword(newPassword);
      return null;
    } catch (e) {
      final f = authFailureFrom(e);
      return f == AuthFailure.unknown ? AuthFailure.passwordResetFailed : f;
    }
  }

  void finishRecovery() => state = state.copyWith(recoveryActive: false);

  Future<void> signOut() async {
    _trace('signOut requested by the user');
    _loadSeq++;
    try {
      await _gateway.signOut();
    } catch (e) {
      debugPrint('signOut failed: ${e.runtimeType}');
    }
    // Do not wait for the event: the UI must leave the account immediately.
    state = const AuthSnapshot.guest();
  }

  Future<void> retryProfile() async {
    final user = state.user;
    if (user == null) return;
    state = state.copyWith(
      status: AuthStatus.initializing,
      failure: () => null,
    );
    await _loadProfile(user);
  }

  /// After the onboarding / preferences RPC returns the updated profile.
  void applyProfile(UserProfile profile) {
    if (state.user?.id != profile.id) return;
    state = state.copyWith(status: _statusFor(profile), profile: () => profile);
  }

  /// Nickname first (a name copied from Kakao does not count), then the
  /// first-conditions onboarding, then the normal app.
  static AuthStatus _statusFor(UserProfile p) {
    if (!p.nicknameIsCustom) return AuthStatus.authenticatedNeedsNickname;
    return p.onboardingCompleted
        ? AuthStatus.authenticatedReady
        : AuthStatus.authenticatedNeedsOnboarding;
  }

  /// Validates and saves the user's app nickname. Null on success (the
  /// profile and routing update immediately); the old nickname is kept on
  /// failure.
  Future<AuthFailure?> saveNickname(String nickname) async {
    if (state.user == null) return AuthFailure.sessionExpired;
    final check = checkNickname(nickname);
    if (!check.isValid) return AuthFailure.nicknameInvalid;
    try {
      final profile = await ref
          .read(profileRepositoryProvider)
          .setNickname(check.value!);
      applyProfile(profile);
      return null;
    } catch (e) {
      final f = authFailureFrom(e);
      return switch (f) {
        AuthFailure.profileLoadFailed ||
        AuthFailure.unknown => AuthFailure.nicknameSaveFailed,
        _ => f,
      };
    }
  }

  void clearFailure() {
    if (state.failure != null) state = state.copyWith(failure: () => null);
  }
}
