import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/conditions/models/conditions.dart';
import 'package:meogeobojo/features/home/utils/home_text.dart';
import 'package:meogeobojo/features/preferences/models/user_preferences.dart';
import 'package:meogeobojo/features/recommendation/demo/demo_features.dart';
import 'package:meogeobojo/features/recommendation/demo/demo_providers.dart';
import 'package:meogeobojo/features/recommendation/demo/demo_repository.dart';
import 'package:meogeobojo/features/recommendation/home_ranking.dart';
import 'package:meogeobojo/features/recommendation/providers/ranking_providers.dart';
import 'package:meogeobojo/features/recommendation/restaurant_insight.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant_override.dart';
import 'package:meogeobojo/features/university/providers/university_providers.dart';
import 'package:meogeobojo/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

const lat = 36.7680, lng = 126.9305;

Restaurant place(String id, double dLat) => Restaurant(
  kakaoId: id,
  name: '식당$id',
  categoryName: '음식점 > 한식',
  categoryGroupCode: 'FD6',
  address: '',
  roadAddress: '',
  phone: '',
  latitude: lat + dLat,
  longitude: lng,
  distanceMeters: 0,
  placeUrl: null,
);

Map<String, dynamic> row(
  String id, {
  bool? parking,
  String open = '11:00:00',
  String last = '20:30:00',
  String? brk,
  bool noBreak = true,
  bool takeout = true,
  bool lateOpen = false,
}) => {
  'kakao_place_id': id,
  'open_time': open,
  'last_order_time': last,
  'break_time': brk,
  'no_break_time': noBreak,
  'parking': parking,
  'local_currency': false,
  'fast_turnover': false,
  'takeout': takeout,
  'open_late': lateOpen,
  'demo_data': true,
};

class _FakeDemo implements DemoFeatureRepository {
  _FakeDemo(this.rows);
  final List<Map<String, dynamic>> rows;
  int reads = 0;
  @override
  Future<Map<String, DemoFeature>> all() async {
    reads++;
    return {
      for (final r in rows)
        ?DemoFeature.fromJson(r)?.kakaoId: DemoFeature.fromJson(r)!,
    };
  }
}

void main() {
  group('mapping the demo rows to RestaurantInsight', () {
    test('hours, break time and every amenity flag come across', () {
      final f = DemoFeature.fromJson(
        row(
          '1',
          parking: true,
          open: '09:00:00',
          last: '21:30:00',
          brk: '15:00-17:00',
          noBreak: false,
          takeout: false,
          lateOpen: true,
        ),
      )!;
      final i = applyDemo(RestaurantInsight.unknown, f);
      expect(i.openMinutes, 9 * 60);
      expect(i.lastOrderMinutes, 21 * 60 + 30);
      expect(i.breakTime, (15 * 60, 17 * 60));
      expect(i.hasBreakTime, isTrue);
      expect(
        [i.parking, i.takeout, i.openLate, i.localCurrency, i.fastTurnover],
        [true, false, true, false, false],
      );
      expect(i.demo, isTrue);
    });

    test('no break time -> hasBreakTime false; a last order after midnight goes past 1440', () {
      final f = DemoFeature.fromJson(
        row('1', open: '17:00:00', last: '01:00:00', noBreak: true),
      )!;
      final i = applyDemo(RestaurantInsight.unknown, f);
      expect(i.hasBreakTime, isFalse);
      expect(i.lastOrderMinutes, 25 * 60);
    });

    test('only an explicit demo_data = true is demo; false or missing is a real row; a row without an id is ignored', () {
      expect(DemoFeature.fromJson({...row('1')})!.demo, isTrue);
      expect(
        DemoFeature.fromJson({...row('1'), 'demo_data': false})!.demo,
        isFalse,
      );
      expect(
        DemoFeature.fromJson({...row('1')}..remove('demo_data'))!.demo,
        isFalse,
      );
      expect(DemoFeature.fromJson({...row('')}), isNull);
    });

    test('a REAL row fills the gaps like any information and never marks the result as demo; a simulated one does', () {
      final real = DemoFeature.fromJson({
        ...row('1', parking: true),
        'demo_data': false,
      })!;
      final sim = DemoFeature.fromJson(row('1', parking: true))!;
      expect(applyDemo(RestaurantInsight.unknown, real).parking, isTrue);
      expect(applyDemo(RestaurantInsight.unknown, real).demo, isFalse);
      expect(applyDemo(RestaurantInsight.unknown, sim).demo, isTrue);
    });

    test('featuresForMode: real rows always, simulated rows only while demo mode is on', () {
      final stored = {
        '1': DemoFeature.fromJson({...row('1'), 'demo_data': false})!,
        '2': DemoFeature.fromJson(row('2'))!,
      };
      expect(featuresForMode(stored, false).keys, ['1']);
      expect(featuresForMode(stored, true).keys, ['1', '2']);
    });

    test('an administrator\'s own values always win; the demo only fills the gaps, and never mixes hours', () {
      final f = DemoFeature.fromJson(
        row(
          '1',
          parking: true,
          open: '09:00:00',
          last: '22:00:00',
          brk: '15:00-17:00',
          noBreak: false,
        ),
      )!;
      final mine = RestaurantInsight(
        openMinutes: 12 * 60,
        lastOrderMinutes: 20 * 60,
        breakTime: (14 * 60, 16 * 60),
        parking: false,
      );
      final i = applyDemo(mine, f);
      expect([i.openMinutes, i.lastOrderMinutes], [12 * 60, 20 * 60]);
      expect(i.breakTime, (14 * 60, 16 * 60));
      expect(
        i.parking,
        isFalse,
      ); // the real "no parking" is not overwritten by a simulated "parking"
      // only a last order of their own: the demo opening time is NOT paired with it
      final half = applyDemo(
        const RestaurantInsight(lastOrderMinutes: 20 * 60),
        f,
      );
      expect(half.openMinutes, isNull);
      expect(half.lastOrderMinutes, 20 * 60);
    });

    test('nothing is used -> not flagged as demo; menus and prices are never touched', () {
      const full = RestaurantInsight(
        openMinutes: 600,
        lastOrderMinutes: 1200,
        breakTime: (900, 960),
        hasBreakTime: true,
        parking: true,
        localCurrency: true,
        fastTurnover: true,
        takeout: true,
        openLate: true,
        minPriceKrw: 5000,
        menus: [MenuLine(priceKrw: 5000, category: '식사')],
      );
      final i = applyDemo(
        full,
        DemoFeature.fromJson(row('1', parking: false))!,
      );
      expect(i.demo, isFalse);
      expect(i.menus.single.priceKrw, 5000);
      expect(i.minPriceKrw, 5000);
      expect(applyDemo(full, null), same(full));
    });

    test('insightsFrom: demo adds a place that has no admin data, and off means untouched', () {
      final demo = {'9': DemoFeature.fromJson(row('9', parking: true))!};
      expect(insightsFrom(const {}, const {}).containsKey('9'), isFalse);
      final on = insightsFrom(const {}, const {}, demo: demo);
      expect(on['9']!.parking, isTrue);
      expect(on['9']!.demo, isTrue);
    });
  });

  group(
    '₩10,000 or less + a 10-minute walk + parking (no match is fabricated)',
    () {
      // walk 10 minutes = 800 m. All places due north of the origin.
      final near = 0.0027; // ~300 m
      final beyond = 0.0081; // ~900 m
      final places = [
        place('ok', near),
        place('noParking', near),
        place('unknownParking', near),
        place('dear', near),
        place('far', beyond),
        place('noCategory', near),
        place('noMenu', near),
      ];
      const meal = [MenuLine(priceKrw: 8500, category: '식사')];
      final menus = {
        'ok': meal,
        'noParking': meal,
        'unknownParking': const [MenuLine(priceKrw: 9500, category: '면류')],
        'dear': const [MenuLine(priceKrw: 12000, category: '식사')],
        'far': meal,
        'noCategory': const [MenuLine(priceKrw: 8000)],
      };
      Map<String, RestaurantInsight> insights(Map<String, DemoFeature> demo) =>
          {
            for (final e in insightsFrom(const {}, {
              for (final m in menus.entries)
                m.key: [
                  RestaurantMenuItem(
                    name: m.key,
                    priceKrw: m.value.single.priceKrw,
                    category: m.value.single.category,
                  ),
                ],
            }, demo: demo).entries)
              e.key: e.value,
          };
      const c = Conditions(
        budget: BudgetOption.max10000,
        distance: DistanceOption.walk10,
        amenities: {Amenity.parking},
      );
      List<RankedRestaurant> rank(Map<String, RestaurantInsight> ins) =>
          rankRestaurants(
            all: places,
            lat: lat,
            lng: lng,
            conditions: c,
            insights: ins,
            nowMinutes: 12 * 60,
          );

      final demo = {
        for (final r in [
          row('ok', parking: true),
          row('noParking', parking: false),
          row('dear', parking: true),
          row('far', parking: true),
          row('noCategory', parking: true),
          row('noMenu', parking: true),
          // unknownParking: no demo row at all
        ])
          r['kakao_place_id'] as String: DemoFeature.fromJson(r)!,
      };

      test('with demo data: one confirmed match; the rest are dropped or listed as unverified with the reason', () {
        final r = rank(insights(demo));
        Set<String> ids(Iterable<RankedRestaurant> xs) =>
            xs.map((e) => e.restaurant.kakaoId).toSet();
        expect(ids(r.confirmed), {'ok'});
        expect(ids(r.unconfirmed), {'unknownParking', 'noCategory', 'noMenu'});
        // dropped: parking known to be absent, a meal over budget, too far
        for (final gone in ['noParking', 'dear', 'far']) {
          expect(
            r.any((e) => e.restaurant.kakaoId == gone),
            isFalse,
            reason: gone,
          );
        }
        final byId = {for (final e in r) e.restaurant.kakaoId: e};
        expect(byId['unknownParking']!.missingAmenities, {Amenity.parking});
        expect(byId['unknownParking']!.missing, {MissingInfo.amenities});
        expect(byId['noCategory']!.missing, {
          MissingInfo.price,
        }); // an unclassified price proves nothing
        expect(byId['noMenu']!.missing, {MissingInfo.price});
        expect(
          byId['ok']!.demoBasis,
          isTrue,
        ); // the parking fact is simulated: it must be labelled
        expect(r.first.restaurant.kakaoId, 'ok'); // confirmed first
      });

      test(
        'without demo data nothing is confirmed: parking is simply unknown',
        () {
          final r = rank(insights(const {}));
          expect(r.confirmed, isEmpty);
          expect(
            r.every((e) => e.missing.contains(MissingInfo.amenities)),
            isTrue,
          );
          expect(r.any((e) => e.demoBasis), isFalse);
        },
      );

      test('the budget comes from the menus only: the demo file\'s own "meal under X" flags are never read', () {
        // a demo row that claims a cheap meal changes nothing about a place whose real menu has none
        final liar = {
          ...demo,
          'noMenu': DemoFeature.fromJson({
            ...row('noMenu', parking: true),
            'meal_under_10000_demo': true,
          })!,
        };
        final r = rank(insights(liar));
        expect(r.confirmed.map((e) => e.restaurant.kakaoId), ['ok']);
      });

      test('the missing-information text names what could not be checked', () {
        final l10n = lookupAppLocalizations(const Locale('ko'));
        final r = rank(insights(demo));
        final u = r.firstWhere((e) => e.restaurant.kakaoId == 'unknownParking');
        expect(
          missingText(l10n, u.missing, amenities: u.missingAmenities),
          contains('주차'),
        );
        expect(missingText(l10n, {MissingInfo.price}), l10n.missingPrice);
      });
    },
  );

  group('the demo switch', () {
    Future<ProviderContainer> container({
      Map<String, Object> prefs = const {},
      bool available = true,
      _FakeDemo? repo,
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          demoAvailableProvider.overrideWithValue(available),
          demoFeatureRepositoryProvider.overrideWithValue(
            repo ?? _FakeDemo([row('1', parking: true)]),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('it is OFF by default; while off a simulated row is never applied, a real one always is', () async {
      final repo = _FakeDemo([
        row('1', parking: true),
        {...row('2', parking: true), 'demo_data': false},
      ]);
      final c = await container(repo: repo);
      expect(c.read(demoModeProvider), isFalse);
      await c.read(demoFeaturesProvider.future);
      expect(c.read(restaurantInsightsProvider).containsKey('1'), isFalse);
      final real = c.read(restaurantInsightsProvider)['2'];
      expect(real?.parking, isTrue);
      expect(real?.demo, isFalse);
    });

    test('turning it on loads the demo features into the insights and is remembered', () async {
      final repo = _FakeDemo([row('1', parking: true)]);
      final c = await container(repo: repo);
      await c.read(demoModeProvider.notifier).set(true);
      expect(c.read(demoModeProvider), isTrue);
      expect((await c.read(demoFeaturesProvider.future)).keys, ['1']);
      expect(c.read(restaurantInsightsProvider)['1']?.parking, isTrue);
      expect(c.read(restaurantInsightsProvider)['1']?.demo, isTrue);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'recommendation_demo_mode',
        ),
        isTrue,
      );
      await c.read(demoModeProvider.notifier).set(false);
      expect(c.read(restaurantInsightsProvider).containsKey('1'), isFalse);
    });

    test('a build without the switch can never be in demo mode, even with a stored "on"', () async {
      final c = await container(
        prefs: {'recommendation_demo_mode': true},
        available: false,
      );
      expect(c.read(demoModeProvider), isFalse);
      await c.read(demoModeProvider.notifier).set(true);
      expect(c.read(demoModeProvider), isFalse);
    });

    test(
      'the table missing or failing means no demo data, not an error',
      () async {
        final repo = SupabaseDemoFeatureRepository(
          () => throw StateError('no client'),
        );
        expect(await repo.all(), isEmpty);
      },
    );
  });
}
