import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/embed/embed_mode.dart';
import '../../analytics/app_events.dart';
import '../../university/providers/university_providers.dart';

/// 챗봇 기록: one finished chat turn (what was asked, what the chat answered) for the admin 챗봇 기록 page
/// (`chat_turns`, migration 20261129000100). The chat tells the user so in its footnote.
///
/// What travels: the question, how it was understood, the restaurants shown (id, name, the one-line reason) and the
/// AI's sentence. The account is taken from the session by the database, never sent from here; a guest is only the
/// random device id the usage events already use.
@immutable
class ChatTurnLog {
  const ChatTurnLog({
    required this.language,
    required this.question,
    required this.outcome,
    required this.aiStatus,
    this.intent,
    this.prefs,
    this.reply,
    this.restaurants = const [],
    this.notes = const [],
    this.failure,
  });

  /// The app language code ("ko", "en", "zh-Hans").
  final String language;
  final String question;

  /// "search", "more", "different", "menu", "compare", "chitchat", "clarify"; null when nothing was understood.
  final String? intent;

  /// The interpreted conditions (the same JSON the assistant exchanges); null when none.
  final Map<String, dynamic>? prefs;

  /// "answered", "no_result", "chitchat", "clarify" or "error".
  final String outcome;

  /// "ok" = the AI understood and worded the answer, "busy" = it understood but the app worded the answer,
  /// "down" = it did not understand and the app answered with its own engine.
  final String aiStatus;

  /// The sentence the AI wrote (null when the app wrote the lines itself: see [notes]).
  final String? reply;

  /// `{id, name, reason?}` of each restaurant shown, in order.
  final List<Map<String, String>> restaurants;

  /// Kind names of the lines the app wrote itself (foundCount, aiBusy, noneRaiseBudget, ...).
  final List<String> notes;

  /// The kind of the error bubble when the turn failed.
  final String? failure;

  Map<String, dynamic> toRpc(String clientId) => {
    'p_client_id': clientId,
    'p_language': language,
    'p_question': question,
    'p_intent': intent,
    'p_prefs': prefs,
    'p_outcome': outcome,
    'p_ai_status': aiStatus,
    'p_reply': reply,
    'p_restaurants': restaurants,
    'p_failure': failure,
    'p_notes': notes,
  };
}

typedef ChatHistoryLogger = void Function(ChatTurnLog turn);

/// Records a turn in the background. The phone preview embedded in the website is a demo surface, not a visitor, so it
/// records nothing (the same rule as the usage events).
final chatHistoryLoggerProvider = Provider<ChatHistoryLogger>((ref) {
  if (ref.watch(embeddedPreviewProvider)) return (_) {};
  return (turn) =>
      sendChatTurn(() => ref.read(sharedPreferencesProvider), turn);
});

/// Never throws and never waits: a lost history row is fine, a slower or broken chat is not.
void sendChatTurn(SharedPreferences Function() prefs, ChatTurnLog turn) {
  try {
    unawaited(
      Supabase.instance.client
          .rpc('log_chat_turn', params: turn.toRpc(analyticsClientId(prefs())))
          .timeout(const Duration(seconds: 10))
          .then<void>(
            (_) {},
            onError: (Object e) =>
                debugPrint('chat turn not recorded: ${e.runtimeType}'),
          ),
    );
  } catch (e) {
    debugPrint('chat turn not recorded: ${e.runtimeType}');
  }
}
