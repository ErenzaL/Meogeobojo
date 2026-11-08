import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The one redirect target registered in Supabase Auth → URL Configuration
/// and in the iOS / Android manifests. Trailing slash is significant: Supabase
/// matches the allow-list entry exactly.
const kAuthRedirectUrl = 'com.meogeobojo.app://login-callback/';

/// URL scheme part of [kAuthRedirectUrl], for the system auth session.
const kAuthCallbackScheme = 'com.meogeobojo.app';

const _requestTimeout = Duration(seconds: 20);

/// Thin seam over `Supabase.instance.client.auth` so the controller and the
/// screens can be tested without a network. Deep links are NOT handled here:
/// supabase_flutter observes them itself and surfaces the result on [events].
abstract class AuthGateway {
  Stream<AuthState> get events;
  User? get currentUser;

  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  });

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  });

  /// Runs the Kakao consent flow.
  ///
  /// iOS: inside a system `ASWebAuthenticationSession` sheet that closes by
  /// itself when the redirect arrives; the returned future completes after the
  /// session was exchanged. Elsewhere: opens the browser and returns at once.
  /// Either way success is only real once a session shows up on [events].
  /// Throws on cancellation / provider errors.
  Future<bool> signInWithKakao();

  Future<void> resendSignupEmail(String email);
  Future<void> sendPasswordReset(String email);
  Future<void> updatePassword(String newPassword);
  Future<void> signOut();
}

class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._auth);

  /// Uses the app's single, already-initialized Supabase client.
  SupabaseAuthGateway.instance() : this(Supabase.instance.client.auth);

  final GoTrueClient _auth;

  @override
  Stream<AuthState> get events => _auth.onAuthStateChange;

  @override
  User? get currentUser => _auth.currentUser;

  @override
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) => _auth
      .signInWithPassword(email: email, password: password)
      .timeout(_requestTimeout);

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) => _auth
      .signUp(
        email: email,
        password: password,
        emailRedirectTo: kAuthRedirectUrl,
      )
      .timeout(_requestTimeout);

  @override
  Future<bool> signInWithKakao() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      // The plain in-app Safari sheet cannot render the custom-scheme redirect
      // and stays open (blank). ASWebAuthenticationSession intercepts the
      // redirect, hands it to us and dismisses itself. It is also why
      // supabase_flutter's deep-link observer does not see this callback, so
      // the code is exchanged exactly once, here, by the SDK.
      final res = await _auth.getOAuthSignInUrl(
        provider: OAuthProvider.kakao,
        redirectTo: kAuthRedirectUrl,
      );
      final callback = await FlutterWebAuth2.authenticate(
        url: res.url,
        callbackUrlScheme: kAuthCallbackScheme,
      );
      await _auth.getSessionFromUrl(Uri.parse(callback));
      return true;
    }
    // Android: in-app Custom Tab. The callback comes back through the
    // MainActivity intent filter and supabase_flutter's own observer (the same
    // path email-confirmation and password-recovery links use).
    return _auth.signInWithOAuth(
      OAuthProvider.kakao,
      redirectTo: kAuthRedirectUrl,
      authScreenLaunchMode: LaunchMode.inAppBrowserView,
    );
  }

  @override
  Future<void> resendSignupEmail(String email) => _auth
      .resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: kAuthRedirectUrl,
      )
      .timeout(_requestTimeout);

  @override
  Future<void> sendPasswordReset(String email) => _auth
      .resetPasswordForEmail(email, redirectTo: kAuthRedirectUrl)
      .timeout(_requestTimeout);

  @override
  Future<void> updatePassword(String newPassword) => _auth
      .updateUser(UserAttributes(password: newPassword))
      .timeout(_requestTimeout);

  @override
  Future<void> signOut() => _auth.signOut();
}
