import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Typed access to the bundled `.env`. Only client-safe values live here
/// (Supabase publishable key, Kakao *native* key). The Kakao REST key must
/// never be added: it lives in Supabase Secrets and is used by the
/// `search_restaurants` Edge Function only.
abstract final class Env {
  // Compile-time values (`--dart-define`). Used for the web build so that no
  // `.env` content is published as a static asset; empty when not provided.
  static const _defSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _defSupabaseKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const _defKakaoNative = String.fromEnvironment('KAKAO_NATIVE_APP_KEY');
  static const _defKakaoJs = String.fromEnvironment('KAKAO_JAVASCRIPT_KEY');

  static String get supabaseUrl => _require('SUPABASE_URL', _defSupabaseUrl);
  static String get supabasePublishableKey =>
      _require('SUPABASE_PUBLISHABLE_KEY', _defSupabaseKey);
  static String get kakaoNativeAppKey => _defKakaoNative.isNotEmpty
      ? _defKakaoNative
      : _env('KAKAO_NATIVE_APP_KEY');

  /// Kakao *JavaScript* key, used only by the web map. Public by design (the
  /// browser needs it); Kakao restricts it to the domains registered for it.
  static String get kakaoJavascriptKey =>
      _defKakaoJs.isNotEmpty ? _defKakaoJs : _env('KAKAO_JAVASCRIPT_KEY');

  /// Public legal documents. Optional: when unset the app says the documents
  /// are not published yet instead of linking to an invented URL.
  static Uri? get termsUrl =>
      _optionalUrl('TERMS_URL', const String.fromEnvironment('TERMS_URL'));
  static Uri? get privacyUrl =>
      _optionalUrl('PRIVACY_URL', const String.fromEnvironment('PRIVACY_URL'));

  /// Where questions and suggestions go. Optional, like the legal links: when neither is configured the footer says
  /// the contact channel is not set up yet instead of showing an invented address.
  static Uri? get feedbackUrl => _optionalUrl(
    'FEEDBACK_URL',
    const String.fromEnvironment('FEEDBACK_URL'),
  );
  static String? get supportEmail {
    const compileTime = String.fromEnvironment('SUPPORT_EMAIL');
    final v = (compileTime.isNotEmpty ? compileTime : _env('SUPPORT_EMAIL'))
        .trim();
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v) ? v : null;
  }

  static Uri? _optionalUrl(String key, String compileTime) {
    final v = compileTime.isNotEmpty ? compileTime : _env(key);
    if (v.trim().isEmpty) return null;
    final uri = Uri.tryParse(v.trim());
    return uri != null && uri.scheme == 'https' ? uri : null;
  }

  /// Value from the loaded `.env`, or '' when it is not loaded / not set.
  static String _env(String key) {
    try {
      return dotenv.env[key] ?? '';
    } catch (_) {
      return ''; // .env not loaded (tests, web builds)
    }
  }

  static String _require(String key, String compileTime) {
    if (compileTime.isNotEmpty) return compileTime;
    final v = _env(key);
    if (v.isEmpty) {
      throw StateError(
        'Missing $key: set it in .env or pass --dart-define=$key=...',
      );
    }
    return v;
  }
}
