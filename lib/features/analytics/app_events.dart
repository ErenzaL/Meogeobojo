import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../university/providers/university_providers.dart';

/// 사용 지표: the four anonymous events behind the admin 분석 page
/// (`app_events`, migration 20261122000100). No account id is sent: only a
/// random id kept on this device, to count visitors and returning visitors.
enum AppEvent {
  appOpen('app_open'),
  restaurantView('restaurant_view'),
  directionsClick('directions_click'),
  search('search');

  const AppEvent(this.wire);
  final String wire;
}

typedef AppEventLogger = void Function(
  AppEvent event, {
  String? restaurantId,
  String? query,
});

final appEventLoggerProvider = Provider<AppEventLogger>(
  (ref) =>
      (event, {restaurantId, query}) => sendAppEvent(
        () => ref.read(sharedPreferencesProvider),
        event,
        restaurantId: restaurantId,
        query: query,
      ),
);

const analyticsClientIdKey = 'analytics_client_id';

/// Sends one event in the background. Never throws and never waits: a lost
/// event is fine, a slower tap is not.
void sendAppEvent(
  SharedPreferences Function() prefs,
  AppEvent event, {
  String? restaurantId,
  String? query,
}) {
  try {
    final q = query?.trim();
    final row = {
      'event': event.wire,
      'client_id': analyticsClientId(prefs()),
      'restaurant_id': ?restaurantId,
      // The table keeps at most 100 characters (runes, so an emoji is never cut in half).
      if (q != null && q.isNotEmpty)
        'query': String.fromCharCodes(q.runes.take(100)),
    };
    unawaited(
      Supabase.instance.client
          .from('app_events')
          .insert(row)
          .timeout(const Duration(seconds: 10))
          .then<void>(
            (_) {},
            onError: (Object e) => debugPrint('app event not sent: $e'),
          ),
    );
  } catch (e) {
    debugPrint('app event not sent: $e');
  }
}

/// This device's random id, created on first use and kept.
String analyticsClientId(SharedPreferences prefs) {
  final saved = prefs.getString(analyticsClientIdKey);
  if (saved != null) return saved;
  final rnd = Random.secure();
  final b = List<int>.generate(16, (_) => rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // RFC 4122 variant
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  final id =
      '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
  unawaited(prefs.setString(analyticsClientIdKey, id));
  return id;
}
