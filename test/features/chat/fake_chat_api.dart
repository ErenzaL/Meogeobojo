import 'package:meogeobojo/features/chat/data/chat_api.dart';
import 'package:meogeobojo/features/chat/models/chat_prefs.dart';

class InterpretCall {
  InterpretCall(this.language, this.message, this.history, this.prefs, this.lastResult);
  final String language;
  final String message;
  final List<({bool user, String text})> history;
  final ChatPrefs? prefs;
  final List<String> lastResult;
}

/// A scripted assistant: what it "understands" and how it words answers. Nothing touches the network.
class FakeChatApi implements ChatApi {
  FakeChatApi({this.onInterpret, this.onExplain});

  Interpretation Function(String message, InterpretCall call)? onInterpret;
  Explanation Function(List<ExplainItem> items)? onExplain;
  final interprets = <InterpretCall>[];
  final explains = <List<ExplainItem>>[];
  final questions = <String?>[];
  Object? interpretError;
  Object? explainError;

  @override
  Future<Interpretation> interpret({
    required String language,
    required String message,
    required List<({bool user, String text})> history,
    required ChatPrefs? prefs,
    required List<String> lastResult,
    required int shownCount,
  }) async {
    final call = InterpretCall(language, message, history, prefs, lastResult);
    interprets.add(call);
    if (interpretError != null) throw interpretError!;
    return onInterpret?.call(message, call) ??
        const Interpretation(intent: ChatIntent.search);
  }

  @override
  Future<Explanation> explain({
    required String language,
    required List<ExplainItem> items,
    required ChatPrefs prefs,
    required bool hasMore,
    String? question,
  }) async {
    questions.add(question);
    explains.add(items);
    if (explainError != null) throw explainError!;
    return onExplain?.call(items) ??
        Explanation(
          message: 'Here you go.',
          reasons: {for (final i in items) i.id: 'Reason for ${i.id}'},
          ids: [for (final i in items) i.id],
        );
  }
}
