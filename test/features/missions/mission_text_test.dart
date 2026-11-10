import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/missions/models/mission_models.dart';

void main() {
  test('emoji are dropped so no "?" box shows; normal text is untouched', () {
    expect(cleanMissionText('가을엔, 맛집 탐험하기 🍁'), '가을엔, 맛집 탐험하기');
    expect(cleanMissionText('🏆 11월 미션 마스터 🍁🔥'), '11월 미션 마스터');
    expect(cleanMissionText('10,000원 이하 · 3곳 – 완료!'), '10,000원 이하 · 3곳 – 완료!');
    expect(cleanMissionText('맛집  탐험'), '맛집 탐험');
    expect(cleanMissionText(null), isNull);
  });

  test('a campaign subtitle with an emoji parses clean', () {
    final c = MissionCampaign.fromJson({
      'id': 'c1',
      'title': '11월 미션',
      'subtitle': '가을엔, 맛집 탐험하기 🍁',
      'starts_at': '2026-10-31T15:00:00Z',
      'ends_at': '2026-11-30T15:00:00Z',
      'state': 'active',
    });
    expect(c.subtitle, '가을엔, 맛집 탐험하기');
  });
}
