import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_failure.dart';
import 'user_profile.dart';

enum AuthStatus {
  /// Restoring a stored session / loading the profile.
  initializing,
  guest,

  /// An email or Kakao sign-in is in flight.
  authenticating,

  /// Sign-up succeeded but the email link has not been opened yet.
  /// There is no session in this state.
  emailVerificationPending,

  /// Signed in, but the user has not chosen an app nickname yet.
  authenticatedNeedsNickname,
  authenticatedNeedsOnboarding,
  authenticatedReady,
  error,
}

@immutable
class AuthSnapshot {
  const AuthSnapshot({
    required this.status,
    this.user,
    this.profile,
    this.pendingEmail,
    this.failure,
    this.recoveryActive = false,
  });

  const AuthSnapshot.guest() : this(status: AuthStatus.guest);

  final AuthStatus status;

  /// Non-null only with a real Supabase session.
  final User? user;
  final UserProfile? profile;
  final String? pendingEmail;
  final AuthFailure? failure;

  /// A password-recovery link was opened; the reset form must be completed
  /// before onboarding / pending actions are processed.
  final bool recoveryActive;

  bool get isSignedIn => user != null;

  AuthSnapshot copyWith({
    AuthStatus? status,
    User? Function()? user,
    UserProfile? Function()? profile,
    String? Function()? pendingEmail,
    AuthFailure? Function()? failure,
    bool? recoveryActive,
  }) => AuthSnapshot(
    status: status ?? this.status,
    user: user != null ? user() : this.user,
    profile: profile != null ? profile() : this.profile,
    pendingEmail: pendingEmail != null ? pendingEmail() : this.pendingEmail,
    failure: failure != null ? failure() : this.failure,
    recoveryActive: recoveryActive ?? this.recoveryActive,
  );
}
