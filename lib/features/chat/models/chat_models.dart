import 'package:flutter/foundation.dart';

import '../../recommendation/home_ranking.dart';
import '../../restaurants/models/restaurant_override.dart';

enum ChatRole { user, assistant }

/// A line of the chat that is written by the app, not by the AI. It is stored as data and turned into text when it is
/// drawn, so it follows the app language even after the language is changed mid-conversation.
enum NoteKind {
  foundCount,
  aiBusy,
  networkError,
  rateLimited,
  genericError,
  noMore,
  hoursUnknown,
  menuOpened,
  menuNone,
  cheapest,
  closest,
  noPriceData,
  noneGeneric,
  noneRaiseBudget,
  noneWiderDistance,
  noneAnyCuisine,
  noneDropDish,
}

@immutable
class ChatNote {
  const ChatNote(this.kind, {this.name, this.number, this.price});

  final NoteKind kind;
  final String? name;
  final int? number;
  final int? price;
}

/// One recommended restaurant in the chat. Everything shown on its card comes from the database; [reason] is the one
/// AI-written sentence (null when the AI was unavailable or its sentence was not grounded: the card then writes a
/// templated reason from the real data).
@immutable
class ChatHit {
  const ChatHit({
    required this.ranked,
    this.matched = const [],
    this.reason,
    this.spiceUnrecorded = false,
  });

  final RankedRestaurant ranked;

  /// The real menu lines that fit what was asked, best first (at most a few).
  final List<RestaurantMenuItem> matched;
  final String? reason;

  /// The user avoids spicy food and the menu does not record spice level.
  final bool spiceUnrecorded;

  String get id => ranked.restaurant.kakaoId;

  ChatHit withReason(String? r) => ChatHit(
    ranked: ranked,
    matched: matched,
    reason: r,
    spiceUnrecorded: spiceUnrecorded,
  );
}

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    this.text,
    this.notes = const [],
    this.hits = const [],
    this.expand = const {},
    this.failed = false,
  });

  final int id;
  final ChatRole role;

  /// What the user typed, or what the AI wrote.
  final String? text;
  final List<ChatNote> notes;
  final List<ChatHit> hits;

  /// Restaurant ids whose menu opens with the card ("show me the menu of the second one").
  final Set<String> expand;

  /// An error bubble: offers a retry.
  final bool failed;
}
