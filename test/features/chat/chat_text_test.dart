import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/l10n/l10n.dart';
import 'package:meogeobojo/features/chat/models/chat_models.dart';
import 'package:meogeobojo/features/chat/models/chat_prefs.dart';
import 'package:meogeobojo/features/chat/widgets/chat_text.dart';
import 'package:meogeobojo/features/preferences/models/user_preferences.dart';

AppLocalizations l(String code) => lookupAppLocalizations(Locale(code));

String found(String code, ChatPrefs? prefs, {int count = 3}) => chatNoteText(
  l(code),
  ChatNote(NoteKind.foundCount, number: count, prefs: prefs),
);

void main() {
  const asked = ChatPrefs(
    dishKeywords: ['국밥'],
    maxPriceKrw: 8000,
    maxWalkMinutes: 10,
  );

  test('the found line says WHAT was found for, in Korean, English and Chinese', () {
    expect(found('ko', asked), '국밥 · 8,000원 이하 · 도보 10분 이내 조건에 맞는 3곳을 찾았어요.');
    expect(found('en', asked), 'I found 3 places for 국밥 · under 8,000 won · within a 10-min walk.');
    expect(found('zh', asked), contains('국밥'));
    expect(found('zh', asked), contains('8,000韩元以下'));
    expect(found('zh', asked), contains('步行10分钟内'));
    expect(found('zh', asked), contains('3'));
  });

  test('nothing specific asked (or no prefs): the plain count line, never an empty "for ."', () {
    for (final code in ['ko', 'en', 'zh']) {
      expect(found(code, null), l(code).chatFoundCount(3));
      expect(found(code, ChatPrefs.none), l(code).chatFoundCount(3));
      expect(found(code, const ChatPrefs(cuisines: {Cuisine.any})), l(code).chatFoundCount(3));
    }
  });

  test('cuisines, open now, not spicy, cheap and close by are named; at most four parts, hard ones first', () {
    final c = chatCriteria(
      l('en'),
      const ChatPrefs(
        cuisines: {Cuisine.chinese},
        openNow: true,
        avoidSpicy: true,
        maxPriceKrw: 9000,
        cheap: true,
        closer: true,
        dishKeywords: ['짜장면', '짬뽕', '탕수육'],
      ),
    );
    expect(c.split(' · '), hasLength(4));
    expect(c, startsWith('짜장면 · 짬뽕'));
    expect(c, contains('under 9,000 won'));
    // "cheap" is redundant once a budget number is given
    expect(chatCriteria(l('en'), const ChatPrefs(cheap: true, maxPriceKrw: 9000)), 'under 9,000 won');
    expect(chatCriteria(l('en'), const ChatPrefs(cheap: true, closer: true)), 'cheap · close by');
  });
}
