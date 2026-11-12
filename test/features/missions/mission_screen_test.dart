import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;
import 'package:meogeobojo/features/auth/providers/auth_providers.dart';
import 'package:meogeobojo/features/favorites/providers/favorites_providers.dart';
import 'package:meogeobojo/features/home/providers/home_providers.dart';
import 'package:meogeobojo/features/home/screens/home_screen.dart';
import 'package:meogeobojo/features/home/widgets/home_category_bar.dart';
import 'package:meogeobojo/features/missions/models/mission_models.dart';
import 'package:meogeobojo/features/missions/providers/mission_providers.dart';
import 'package:meogeobojo/features/missions/widgets/campaign_banner.dart';
import 'package:meogeobojo/features/navigation/providers/shell_tab_provider.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/preferences/models/user_preferences.dart';
import 'package:meogeobojo/features/restaurants/models/food_category.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

/// What the server (sync_my_missions) returns, as JSON, so the tests also
/// cover the wire format the Dart models parse.
Map<String, dynamic> mission(
  String slug,
  String title, {
  String kind = 'monthly',
  String rule = 'favorite_distinct',
  int target = 3,
  int progress = 0,
  int points = 10,
  String state = 'active',
  String action = 'none',
  String icon = 'star',
  String? description,
  String recurrence = 'none',
  String? badgeKey,
  String? badgeName,
  String? badgeMascot,
  int order = 0,
}) => {
  'id': 'id-$slug',
  'slug': slug,
  'kind': kind,
  'title': title,
  'description': description ?? '$title 설명',
  'icon': icon,
  'reward_points': points,
  'rule_type': rule,
  'target': target,
  'progress': progress,
  'state': state,
  'action_key': action,
  'sort_order': order,
  'recurrence': recurrence,
  'ends_at': '2026-11-30T15:00:00Z',
  'badge_key': badgeKey,
  'badge_name': badgeName,
  'badge_mascot': badgeMascot,
};

Map<String, dynamic> payload({
  List<Map<String, dynamic>>? missions,
  int pointsTotal = 0,
  int pointsCampaign = 0,
  List<Map<String, dynamic>> badges = const [],
  List<Map<String, dynamic>> newly = const [],
  bool campaign = true,
}) => {
  'campaign': campaign
      ? {
          'id': 'camp-1',
          'slug': '2026-11',
          'title': '11월 미션',
          'subtitle': '가을엔, 맛집 탐험하기 🍁',
          'theme_color': '#E85D04',
          'banner_mascot': 'cheer',
          // Nov 1 00:00 KST .. Dec 1 00:00 KST (exclusive), in UTC
          'starts_at': '2026-10-31T15:00:00Z',
          'ends_at': '2026-11-30T15:00:00Z',
          'state': 'active',
        }
      : null,
  'missions': missions ?? [],
  'points_total': pointsTotal,
  'points_campaign': pointsCampaign,
  'badges': badges,
  'newly_completed': newly,
};

final _november = [
  mission(
    'a',
    '오늘 뭐 먹지?',
    target: 3,
    progress: 1,
    points: 15,
    action: 'recommend',
    icon: 'sparkle',
    order: 1,
  ),
  mission(
    'b',
    '맛집 찜하기',
    target: 5,
    progress: 5,
    points: 20,
    state: 'completed',
    action: 'map',
    icon: 'favorite',
    order: 2,
  ),
  mission(
    'c',
    '첫 리뷰 도전',
    target: 1,
    progress: 0,
    points: 30,
    action: 'review',
    icon: 'review',
    order: 3,
  ),
  mission(
    'm',
    '11월 미션 마스터',
    rule: 'missions_completed',
    target: 5,
    progress: 1,
    points: 0,
    action: 'none',
    icon: 'trophy',
    order: 9,
    badgeKey: 'nov_2026_master',
    badgeName: '11월 미션 마스터',
    badgeMascot: 'cheer',
  ),
  mission(
    'd',
    '오늘의 추천 확인',
    kind: 'daily',
    target: 1,
    progress: 0,
    points: 5,
    recurrence: 'daily',
    action: 'recommend',
  ),
  mission(
    'w',
    '이번 주 맛집 2곳 찜하기',
    kind: 'weekly',
    target: 2,
    progress: 1,
    points: 10,
    recurrence: 'weekly',
    action: 'map',
  ),
  mission(
    'x',
    '찜 수집가',
    kind: 'achievement',
    target: 20,
    progress: 4,
    points: 50,
  ),
];

Future<Harness> openMissions(
  WidgetTester tester, {
  FakeMissionRepository? repo,
  bool signedIn = true,
  Size size = const Size(390, 1500),
}) async {
  final h = await buildHarness(
    // Home starts before a pick, so its first button is "조건에 맞게 추천받기".
    recsRequested: false,
    auth: signedIn ? FakeAuthGateway(user: fakeUser()) : null,
    profiles: FakeProfileRepository(onboardingCompleted: true, nickname: '민수'),
    prefs: FakePreferencesRepository(
      stored: const UserPreferences(
        budget: BudgetOption.any,
        distance: DistanceOption.any,
      ),
    ),
    missions: repo,
  );
  await pumpApp(tester, h, home: const AppShell(), size: size);
  h.container.read(shellTabProvider.notifier).select(ShellTabs.missions);
  await tester.pumpAndSettle();
  return h;
}

void main() {
  group('wire format', () {
    test('parses the campaign, missions, points and badges', () {
      final d = MissionDashboard.fromJson(
        payload(
          missions: _november,
          pointsTotal: 20,
          pointsCampaign: 20,
          badges: [
            {
              'badge_key': 'nov_2026_master',
              'name': '11월 미션 마스터',
              'mascot': 'cheer',
            },
          ],
        ),
      );
      expect(d.campaign!.title, '11월 미션');
      expect(d.campaign!.periodLabel, '2026.11.01 – 2026.11.30');
      expect(d.mainMonthly, hasLength(3));
      expect(d.completedMain, 1);
      expect(d.totalMain, 3);
      expect(d.master!.target, 5);
      expect(d.hasBadge('nov_2026_master'), isTrue);
      expect(d.byKind(MissionKind.daily), hasLength(1));
      expect(d.pointsCampaign, 20);
    });

    test('missing / unknown fields fall back instead of throwing', () {
      final d = MissionDashboard.fromJson({
        'missions': [
          {'id': 'x', 'kind': '???', 'state': '???', 'action_key': '???'},
          'garbage',
        ],
      });
      expect(d.campaign, isNull);
      expect(d.missions, hasLength(1));
      expect(d.missions.single.action, MissionAction.none);
      expect(d.missions.single.state, MissionState.active);
    });

    test('period is shown in Seoul time with an inclusive last day', () {
      final c = MissionCampaign.fromJson({
        'id': 'c',
        'title': 't',
        'starts_at': '2026-11-30T15:00:00Z', // Dec 1 00:00 KST
        'ends_at': '2026-12-31T15:00:00Z', // Jan 1 00:00 KST (exclusive)
      });
      expect(c.periodLabel, '2026.12.01 – 2026.12.31');
    });

    test('progress never exceeds the target', () {
      final m = Mission.fromJson(mission('z', 'z', target: 3, progress: 9));
      expect(m.fraction, 1.0);
    });
  });

  group('미션 tab', () {
    testWidgets('banner, dashboard and the 11월 missions from the server', (
      tester,
    ) async {
      final repo = FakeMissionRepository(
        dashboard: MissionDashboard.fromJson(
          payload(missions: _november, pointsTotal: 20, pointsCampaign: 20),
        ),
      );
      await openMissions(tester, repo: repo);
      expect(find.byType(CampaignBanner), findsOneWidget);
      expect(find.text('가을엔, 맛집 탐험하기'), findsOneWidget);
      expect(find.text('2026.11.01 – 2026.11.30'), findsOneWidget);
      // completed / total, points and the badge preview
      expect(find.text('완료한 미션'), findsOneWidget);
      expect(find.textContaining('/ 3', findRichText: true), findsOneWidget);
      expect(find.text('20P'), findsOneWidget);
      expect(find.text('이달의 뱃지'), findsOneWidget);
      expect(find.text('미션 5개를 완료하면 받을 수 있어요'), findsOneWidget);
      // cards: title, progress, reward; completed shows 완료
      expect(find.text('오늘 뭐 먹지?'), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('+15P'), findsOneWidget);
      expect(find.text('5/5'), findsOneWidget);
      expect(find.text('완료'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.text('한정 뱃지'), findsOneWidget);
    });

    testWidgets('the four tabs show only their own missions', (tester) async {
      await openMissions(
        tester,
        repo: FakeMissionRepository(
          dashboard: MissionDashboard.fromJson(payload(missions: _november)),
        ),
      );
      expect(find.text('데일리'), findsOneWidget);
      expect(find.text('주간'), findsOneWidget);
      expect(find.text('도전과제'), findsOneWidget);
      expect(find.text('오늘의 추천 확인'), findsNothing);
      await tester.tap(find.text('데일리'));
      await tester.pumpAndSettle();
      expect(find.text('오늘의 추천 확인'), findsOneWidget);
      expect(find.text('오늘 뭐 먹지?'), findsNothing);
      await tester.tap(find.text('주간'));
      await tester.pumpAndSettle();
      expect(find.text('이번 주 맛집 2곳 찜하기'), findsOneWidget);
      await tester.tap(find.text('도전과제'));
      await tester.pumpAndSettle();
      expect(find.text('찜 수집가'), findsOneWidget);
      expect(find.text('4/20'), findsOneWidget);
      await tester.tap(find.text('11월 미션').last);
      await tester.pumpAndSettle();
      expect(find.text('맛집 찜하기'), findsOneWidget);
    });

    testWidgets('an unlocked badge shows as earned', (tester) async {
      final done = [
        for (final m in _november)
          if (m['slug'] == 'm')
            {...m, 'state': 'completed', 'progress': 5}
          else
            m,
      ];
      await openMissions(
        tester,
        repo: FakeMissionRepository(
          dashboard: MissionDashboard.fromJson(
            payload(
              missions: done,
              badges: [
                {
                  'badge_key': 'nov_2026_master',
                  'name': '11월 미션 마스터',
                  'mascot': 'cheer',
                },
              ],
            ),
          ),
        ),
      );
      expect(find.text('획득 완료'), findsOneWidget);
      expect(find.text('미션 5개를 완료하면 받을 수 있어요'), findsNothing);
    });

    testWidgets('expired and upcoming missions are labelled', (tester) async {
      await openMissions(
        tester,
        repo: FakeMissionRepository(
          dashboard: MissionDashboard.fromJson(
            payload(
              missions: [
                mission('e', '지난 미션', state: 'expired', progress: 1, order: 1),
                mission('u', '예정 미션', state: 'upcoming', order: 2),
              ],
            ),
          ),
        ),
      );
      expect(find.text('기간 종료'), findsOneWidget);
      expect(find.text('예정'), findsOneWidget);
    });

    testWidgets(
      'no campaign: no banner, just the tabs and an honest empty state',
      (tester) async {
        await openMissions(
          tester,
          repo: FakeMissionRepository(
            dashboard: MissionDashboard.fromJson(payload(campaign: false)),
          ),
        );
        expect(find.byType(CampaignBanner), findsNothing);
        expect(find.text('이달의 미션'), findsOneWidget);
        expect(find.text('진행 중인 미션이 없어요'), findsOneWidget);
      },
    );

    testWidgets('server error shows a retry that works', (tester) async {
      final repo = FakeMissionRepository()..error = Exception('down');
      await openMissions(tester, repo: repo);
      expect(find.text('미션을 불러오지 못했어요'), findsOneWidget);
      repo
        ..error = null
        ..dashboard = MissionDashboard.fromJson(payload(missions: _november));
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.text('미션을 불러오지 못했어요'), findsNothing);
      expect(find.text('오늘 뭐 먹지?'), findsOneWidget);
    });

    testWidgets('guests see a sign-in prompt and no server calls are made', (
      tester,
    ) async {
      final repo = FakeMissionRepository();
      await openMissions(tester, repo: repo, signedIn: false);
      expect(find.text('로그인하고 미션에 참여해요'), findsOneWidget);
      expect(repo.syncs, 0);
    });

    for (final (lang, size) in [
      ('ko', Size(320, 640)),
      ('en', Size(320, 640)),
      ('zh-Hans', Size(320, 640)),
    ]) {
      testWidgets('fits 320px at 1.6x text: $lang', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final h = await buildHarness(
          storage: {'app_language': lang},
          auth: FakeAuthGateway(user: fakeUser()),
          profiles: FakeProfileRepository(onboardingCompleted: true),
          missions: FakeMissionRepository(
            dashboard: MissionDashboard.fromJson(
              payload(missions: _november, pointsCampaign: 20),
            ),
          ),
        );
        await pumpApp(tester, h, home: const AppShell(), size: size);
        h.container.read(shellTabProvider.notifier).select(ShellTabs.missions);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text(lang == 'ko' ? '11월 미션 마스터' : '11월 미션 마스터'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('mission detail', () {
    testWidgets(
      'opens a sheet with description, progress, reward, period and an action',
      (tester) async {
        await openMissions(
          tester,
          repo: FakeMissionRepository(
            dashboard: MissionDashboard.fromJson(payload(missions: _november)),
          ),
        );
        await tester.tap(find.text('오늘 뭐 먹지?'));
        await tester.pumpAndSettle();
        expect(find.text('완료 조건'), findsOneWidget);
        expect(find.text('오늘 뭐 먹지? 설명'), findsWidgets); // card + sheet
        expect(find.text('진행 상황'), findsOneWidget);
        expect(find.text('보상'), findsOneWidget);
        expect(find.text('+15P'), findsWidgets);
        expect(find.text('2026.11.30까지'), findsOneWidget);
        expect(find.text('추천 받기'), findsOneWidget);
      },
    );

    testWidgets('the action goes to the matching feature', (tester) async {
      final h = await openMissions(
        tester,
        repo: FakeMissionRepository(
          dashboard: MissionDashboard.fromJson(payload(missions: _november)),
        ),
      );
      await tester.tap(find.text('오늘 뭐 먹지?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('추천 받기'));
      await tester.pumpAndSettle();
      expect(h.container.read(shellTabProvider), ShellTabs.home);
    });

    testWidgets('a review mission sends the student to pick a restaurant', (
      tester,
    ) async {
      final h = await openMissions(
        tester,
        repo: FakeMissionRepository(
          dashboard: MissionDashboard.fromJson(payload(missions: _november)),
        ),
      );
      await tester.tap(find.text('첫 리뷰 도전'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('리뷰 작성하기'));
      await tester.pumpAndSettle();
      // reviews belong to a restaurant: the map tab opens with a hint
      expect(find.textContaining('식당을 골라 상세 화면에서'), findsOneWidget);
      expect(h.container.read(shellTabProvider), ShellTabs.map);
    });

    testWidgets('a correction suggestion (not built yet) says so', (
      tester,
    ) async {
      final h = await openMissions(
        tester,
        repo: FakeMissionRepository(
          dashboard: MissionDashboard.fromJson(
            payload(missions: [mission('fix', '정보 해결사', action: 'correct')]),
          ),
        ),
      );
      await tester.ensureVisible(find.text('정보 해결사'));
      await tester.tap(find.text('정보 해결사'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('정보 수정 제안하기'));
      await tester.pumpAndSettle();
      expect(find.textContaining('아직 준비 중'), findsOneWidget);
      expect(h.container.read(shellTabProvider), ShellTabs.missions);
    });

    testWidgets('a completed mission has no action button', (tester) async {
      await openMissions(
        tester,
        repo: FakeMissionRepository(
          dashboard: MissionDashboard.fromJson(payload(missions: _november)),
        ),
      );
      await tester.tap(find.text('맛집 찜하기'));
      await tester.pumpAndSettle();
      expect(find.text('맛집 찾으러 가기'), findsNothing);
      expect(find.text('완료'), findsWidgets);
    });

    testWidgets('daily missions say when they reset', (tester) async {
      await openMissions(
        tester,
        repo: FakeMissionRepository(
          dashboard: MissionDashboard.fromJson(payload(missions: _november)),
        ),
      );
      await tester.tap(find.text('데일리'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('오늘의 추천 확인'));
      await tester.pumpAndSettle();
      expect(find.text('매일 0시(한국 시간)에 새로 시작돼요'), findsOneWidget);
    });
  });

  group('server-driven updates', () {
    testWidgets('a completion is celebrated once, with the points', (
      tester,
    ) async {
      final repo = FakeMissionRepository(
        dashboard: MissionDashboard.fromJson(payload(missions: _november)),
      );
      final h = await openMissions(tester, repo: repo);
      // The server completes a mission when the user taps 오늘의 추천 받기.
      repo.completionsOnActivity.add(
        const CompletedMission(title: '오늘 뭐 먹지?', points: 15),
      );
      h.container.read(shellTabProvider.notifier).select(ShellTabs.home);
      await tester.pumpAndSettle();
      await tester.tap(find.text('조건에 맞게 추천받기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('미션 완료!'), findsOneWidget);
      expect(find.text('+15P 획득'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('미션 완료!'), findsNothing);
      expect(h.container.read(missionCelebrationProvider), isEmpty);
    });

    testWidgets('the 오늘의 추천 받기 button reports one recommendation_view', (
      tester,
    ) async {
      final repo = FakeMissionRepository();
      final h = await openMissions(tester, repo: repo);
      h.container.read(shellTabProvider.notifier).select(ShellTabs.home);
      await tester.pumpAndSettle();
      await tester.tap(find.text('조건에 맞게 추천받기'));
      await tester.pumpAndSettle();
      expect(repo.activity, [('recommendation_view', '')]);
    });

    testWidgets('choosing a category reports it; 전체 does not', (tester) async {
      final repo = FakeMissionRepository();
      final h = await openMissions(tester, repo: repo);
      h.container.read(shellTabProvider.notifier).select(ShellTabs.home);
      await tester.pumpAndSettle();
      final bar = find.byType(HomeCategoryBar);
      await tester.tap(find.descendant(of: bar, matching: find.text('한식')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: bar, matching: find.text('전체')));
      await tester.pumpAndSettle();
      expect(repo.activity, [('category_explore', FoodCategory.korean.name)]);
      expect(h.container.read(homeCategoryProvider), isEmpty);
    });

    testWidgets('guests never report activity', (tester) async {
      final repo = FakeMissionRepository();
      final h = await openMissions(tester, repo: repo, signedIn: false);
      h.container.read(shellTabProvider.notifier).select(ShellTabs.home);
      await tester.pumpAndSettle();
      await tester.tap(find.text('조건에 맞게 추천받기'));
      await tester.pumpAndSettle();
      expect(repo.activity, isEmpty);
    });

    testWidgets('a failing server never blocks the action itself', (
      tester,
    ) async {
      final repo = FakeMissionRepository()..error = Exception('down');
      final h = await openMissions(tester, repo: repo);
      h.container.read(shellTabProvider.notifier).select(ShellTabs.home);
      await tester.pumpAndSettle();
      await tester.tap(find.text('조건에 맞게 추천받기'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('saving a place asks the server to recompute', (tester) async {
      final repo = FakeMissionRepository(
        dashboard: MissionDashboard.fromJson(payload(missions: _november)),
      );
      final h = await openMissions(tester, repo: repo);
      final before = repo.syncs;
      await h.container.read(favoritesProvider.notifier).toggle('place-1');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(repo.syncs, greaterThan(before));
    });

    testWidgets('coming back to the tab refreshes it', (tester) async {
      final repo = FakeMissionRepository(
        dashboard: MissionDashboard.fromJson(payload(missions: _november)),
      );
      final h = await openMissions(tester, repo: repo);
      h.container.read(shellTabProvider.notifier).select(ShellTabs.home);
      await tester.pumpAndSettle();
      final before = repo.syncs;
      h.container.read(shellTabProvider.notifier).select(ShellTabs.missions);
      await tester.pumpAndSettle();
      expect(repo.syncs, greaterThan(before));
    });

    testWidgets(
      'rewards come back after logging out and in (they live on the server)',
      (tester) async {
        final repo = FakeMissionRepository(
          dashboard: MissionDashboard.fromJson(
            payload(missions: _november, pointsTotal: 20, pointsCampaign: 20),
          ),
        );
        final h = await openMissions(tester, repo: repo);
        expect(find.text('20P'), findsOneWidget);
        await h.container.read(authControllerProvider.notifier).signOut();
        await tester.pumpAndSettle();
        expect(find.text('로그인하고 미션에 참여해요'), findsOneWidget);
        expect(find.text('20P'), findsNothing);
        h.auth.emit(AuthChangeEvent.signedIn, fakeUser());
        await tester.pumpAndSettle();
        expect(find.text('20P'), findsOneWidget);
      },
    );
  });

  group('MY badges', () {
    testWidgets('earned badges are listed; the collection shows points', (
      tester,
    ) async {
      final repo = FakeMissionRepository(
        dashboard: MissionDashboard.fromJson(
          payload(
            pointsTotal: 135,
            badges: [
              {
                'badge_key': 'nov_2026_master',
                'name': '11월 미션 마스터',
                'mascot': 'cheer',
              },
            ],
          ),
        ),
      );
      final h = await buildHarness(
        auth: FakeAuthGateway(user: fakeUser()),
        profiles: FakeProfileRepository(
          onboardingCompleted: true,
          nickname: '민수',
        ),
        missions: repo,
      );
      await pumpApp(
        tester,
        h,
        home: const AppShell(),
        size: const Size(390, 1900),
      );
      h.container.read(shellTabProvider.notifier).select(ShellTabs.profile);
      await tester.pumpAndSettle();
      // MY only loads the dashboard when something asks for it
      await h.container.read(missionDashboardProvider.future);
      await tester.pumpAndSettle();
      expect(find.text('내 뱃지'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('전체 보기 →'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('전체 보기 →'));
      await tester.pumpAndSettle();
      expect(find.text('뱃지 컬렉션'), findsOneWidget);
      expect(find.text('135P'), findsOneWidget);
      expect(find.text('11월 미션 마스터'), findsOneWidget);
    });

    testWidgets('no badge is shown unless the server says it was earned', (
      tester,
    ) async {
      final h = await buildHarness(
        auth: FakeAuthGateway(user: fakeUser()),
        profiles: FakeProfileRepository(
          onboardingCompleted: true,
          nickname: '민수',
        ),
      );
      await pumpApp(
        tester,
        h,
        home: const AppShell(),
        size: const Size(390, 1900),
      );
      h.container.read(shellTabProvider.notifier).select(ShellTabs.profile);
      await tester.pumpAndSettle();
      expect(find.text('아직 얻은 뱃지가 없어요. 미션을 완료해 보세요.'), findsOneWidget);
    });
  });
}
