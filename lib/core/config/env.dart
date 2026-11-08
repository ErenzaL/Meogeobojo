import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Typed access to the bundled `.env`. Only client-safe values live here
/// (Supabase publishable key, Kakao *native* key). The Kakao REST key must
/// never be added: it lives in Supabase Secrets and is used by the
/// `search_restaurants` Edge Function only.
abstract final class Env {
  static String get supabaseUrl => _require('SUPABASE_URL');
  static String get supabasePublishableKey =>
      _require('SUPABASE_PUBLISHABLE_KEY');
  static String get kakaoNativeAppKey =>
      dotenv.env['KAKAO_NATIVE_APP_KEY'] ?? '';

  /// Public legal documents. Optional: when unset the app says the documents
  /// are not published yet instead of linking to an invented URL.
  static Uri? get termsUrl => _optionalUrl('TERMS_URL');
  static Uri? get privacyUrl => _optionalUrl('PRIVACY_URL');

  static Uri? _optionalUrl(String key) {
    String? v;
    try {
      v = dotenv.env[key];
    } catch (_) {
      return null; // .env not loaded (tests) -> treated as unset
    }
    if (v == null || v.trim().isEmpty) return null;
    final uri = Uri.tryParse(v.trim());
    return uri != null && uri.scheme == 'https' ? uri : null;
  }

  static String _require(String key) {
    final v = dotenv.env[key];
    if (v == null || v.isEmpty) {
      throw StateError('Missing $key in .env');
    }
    return v;
  }
}
