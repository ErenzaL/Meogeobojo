import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_prefs.dart';

/// Why the assistant's language service could not answer.
enum ChatFailure {
  /// Gemini's free quota (or the daily cap) is used up for now.
  quota,

  /// Gemini or the function did not answer in time or is down.
  unavailable,

  /// The answer could not be understood.
  badOutput,

  /// The function has no Gemini key / model configured.
  notConfigured,

  /// This visitor sends too many messages ([ChatApiException.retryAfterSeconds]).
  rateLimited,
  unauthorized,
  invalid,
  network,
}

class ChatApiException implements Exception {
  const ChatApiException(this.failure, {this.retryAfterSeconds});

  final ChatFailure failure;
  final int? retryAfterSeconds;

  /// Failures where the chat can still answer with the app's own engine.
  bool get canFallBack => switch (failure) {
    ChatFailure.quota ||
    ChatFailure.unavailable ||
    ChatFailure.badOutput ||
    ChatFailure.notConfigured ||
    ChatFailure.network => true,
    _ => false,
  };

  @override
  String toString() => 'ChatApiException($failure)';
}

enum ChatIntent { search, more, different, menu, compare, chitchat, clarify }

/// What the AI understood of one message.
@immutable
class Interpretation {
  const Interpretation({
    required this.intent,
    this.count,
    this.prefs = ChatPrefs.none,
    this.targetPositions = const [],
    this.rejectPositions = const [],
    this.rejectAll = false,
    this.compareBy,
    this.reply = '',
  });

  final ChatIntent intent;

  /// How many restaurants the user asked for (null = not stated: the default of three applies).
  final int? count;
  final ChatPrefs prefs;

  /// 1-based positions in the last result the message refers to.
  final List<int> targetPositions;
  final List<int> rejectPositions;
  final bool rejectAll;
  final String? compareBy;
  final String reply;

  static Interpretation? fromJson(Object? json) {
    if (json is! Map || json['ok'] != true) return null;
    final intent = ChatIntent.values
        .where((i) => i.name == json['intent'])
        .firstOrNull;
    if (intent == null) return null;
    List<int> ints(Object? v) => [
      if (v is List)
        for (final x in v)
          if (x is num) x.round(),
    ];
    return Interpretation(
      intent: intent,
      count: json['count'] is num ? (json['count'] as num).round() : null,
      prefs: ChatPrefs.fromJson(json['prefs']),
      targetPositions: ints(json['target_positions']),
      rejectPositions: ints(json['reject_positions']),
      rejectAll: json['reject_all'] == true,
      compareBy: json['compare_by'] as String?,
      reply: (json['reply'] as String?)?.trim() ?? '',
    );
  }
}

/// The AI's words for the restaurants the app already ranked.
@immutable
class Explanation {
  const Explanation({this.message, this.reasons = const {}, this.ids});

  final String? message;

  /// One short, grounded sentence per restaurant id.
  final Map<String, String> reasons;

  /// The restaurants the server confirmed as published (null = the server did not say).
  final List<String>? ids;

  static Explanation? fromJson(Object? json) {
    if (json is! Map || json['ok'] != true) return null;
    final raw = json['reasons'];
    return Explanation(
      message: (json['message'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['message'] as String).trim(),
      reasons: {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.key is String && e.value is String) e.key as String: e.value as String,
      },
      ids: json['ids'] is List
          ? [
              for (final x in json['ids'] as List)
                if (x is String) x,
            ]
          : null,
    );
  }
}

@immutable
class ExplainItem {
  const ExplainItem({
    required this.id,
    this.walkMinutes,
    this.openStatus,
    this.matchedMenus = const [],
  });

  final String id;
  final int? walkMinutes;
  final String? openStatus;
  final List<String> matchedMenus;

  Map<String, dynamic> toJson() => {
    'id': id,
    'walk_minutes': walkMinutes,
    'open_status': openStatus,
    'matched_menus': matchedMenus,
  };
}

abstract interface class ChatApi {
  /// [language] is the app language code ("ko", "en", "zh-Hans").
  Future<Interpretation> interpret({
    required String language,
    required String message,
    required List<({bool user, String text})> history,
    required ChatPrefs? prefs,
    required List<String> lastResult,
    required int shownCount,
  });

  Future<Explanation> explain({
    required String language,
    required List<ExplainItem> items,
    required ChatPrefs prefs,
    required bool hasMore,
  });
}

class SupabaseChatApi implements ChatApi {
  SupabaseChatApi(this._client);

  final SupabaseClient _client;

  static const _function = 'ai-restaurant-chat';
  static const _timeout = Duration(seconds: 25);

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions
          .invoke(_function, body: body)
          .timeout(_timeout);
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw const ChatApiException(ChatFailure.badOutput);
      }
      if (data['ok'] != true) throw _fromCode(data);
      return data;
    } on ChatApiException {
      rethrow;
    } on FunctionException catch (e) {
      final d = e.details;
      throw _fromCode(
        d is Map ? d : const {},
        status: e.status,
        retryHeader: null,
      );
    } on TimeoutException {
      throw const ChatApiException(ChatFailure.network);
    } catch (e) {
      debugPrint('ai-restaurant-chat failed: ${e.runtimeType}');
      throw const ChatApiException(ChatFailure.network);
    }
  }

  static ChatApiException _fromCode(
    Map data, {
    int? status,
    String? retryHeader,
  }) {
    final retry = data['retry_after'] is num
        ? (data['retry_after'] as num).round()
        : int.tryParse(retryHeader ?? '');
    final code = data['code'];
    if (status == 429 || code == 'rate_limited') {
      return ChatApiException(ChatFailure.rateLimited, retryAfterSeconds: retry);
    }
    if (status == 401 || code == 'unauthorized') {
      return const ChatApiException(ChatFailure.unauthorized);
    }
    if (status == 400 || status == 413 || code == 'invalid_request') {
      return const ChatApiException(ChatFailure.invalid);
    }
    return ChatApiException(switch (code) {
      'quota' => ChatFailure.quota,
      'bad_output' => ChatFailure.badOutput,
      'not_configured' => ChatFailure.notConfigured,
      _ => ChatFailure.unavailable,
    });
  }

  @override
  Future<Interpretation> interpret({
    required String language,
    required String message,
    required List<({bool user, String text})> history,
    required ChatPrefs? prefs,
    required List<String> lastResult,
    required int shownCount,
  }) async {
    final data = await _call({
      'action': 'interpret',
      'language': language,
      'message': message,
      'history': [
        for (final h in history)
          {'role': h.user ? 'user' : 'assistant', 'text': h.text},
      ],
      'state': {
        'prefs': prefs?.toJson(),
        'last_result': lastResult,
        'shown_count': shownCount,
      },
    });
    final out = Interpretation.fromJson(data);
    if (out == null) throw const ChatApiException(ChatFailure.badOutput);
    return out;
  }

  @override
  Future<Explanation> explain({
    required String language,
    required List<ExplainItem> items,
    required ChatPrefs prefs,
    required bool hasMore,
  }) async {
    final data = await _call({
      'action': 'explain',
      'language': language,
      'items': [for (final i in items) i.toJson()],
      'asked': {
        'max_price_krw': prefs.maxPriceKrw,
        'min_price_krw': prefs.minPriceKrw,
        'max_walk_minutes': prefs.maxWalkMinutes,
        'group_size': prefs.groupSize,
        'keywords': [...prefs.dishKeywords, ...prefs.softKeywords],
        'cuisines': [for (final c in prefs.cuisines) c.name],
        'avoid_spicy': prefs.avoidSpicy,
      },
      'has_more': hasMore,
    });
    final out = Explanation.fromJson(data);
    if (out == null) throw const ChatApiException(ChatFailure.badOutput);
    return out;
  }
}
