import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/preferences/models/user_preferences.dart';
import 'package:meogeobojo/features/recommendation/preference_filter.dart';

import '../../support/fakes.dart';

void main() {
  group('budget semantics', () {
    test('"12,000원 이상" is a MINIMUM, "이하" options are maximums', () {
      expect(BudgetOption.min12000.type, BudgetType.min);
      expect(BudgetOption.min12000.amountKrw, 12000);
      expect(BudgetOption.max12000.type, BudgetType.max);
      expect(BudgetOption.max8000.amountKrw, 8000);
      expect(BudgetOption.any.type, BudgetType.any);
      expect(
        BudgetOption.any.amountKrw,
        isNull,
        reason: 'unrestricted has no amount',
      );
    });

    test('round-trips through the stored (type, amount) pair', () {
      for (final o in BudgetOption.values) {
        expect(BudgetOption.from(o.type.name, o.amountKrw), o);
      }
      expect(BudgetOption.from('min', 9000), isNull, reason: 'unknown amount');
    });
  });

  group('distance semantics', () {
    test('mode and minutes are stored separately', () {
      expect(DistanceOption.walk10.mode, TravelMode.walk);
      expect(DistanceOption.walk10.minutes, 10);
      expect(DistanceOption.drive15.mode, TravelMode.drive);
      expect(DistanceOption.any.minutes, isNull);
      for (final o in DistanceOption.values) {
        expect(DistanceOption.from(o.mode.name, o.minutes), o);
      }
    });
  });

  group('cuisine selection rules', () {
    test('several cuisines can be selected', () {
      var s = <Cuisine>{};
      s = toggleCuisine(s, Cuisine.korean);
      s = toggleCuisine(s, Cuisine.cafe);
      expect(s, {Cuisine.korean, Cuisine.cafe});
    });

    test('tapping a selected cuisine clears it', () {
      expect(toggleCuisine({Cuisine.korean}, Cuisine.korean), isEmpty);
    });

    test('"상관없음" is exclusive: it clears the rest', () {
      final s = toggleCuisine({Cuisine.korean, Cuisine.cafe}, Cuisine.any);
      expect(s, {Cuisine.any});
    });

    test('picking a cuisine clears "상관없음"', () {
      expect(toggleCuisine({Cuisine.any}, Cuisine.japanese), {
        Cuisine.japanese,
      });
    });

    test('tapping "상관없음" again unselects it', () {
      expect(toggleCuisine({Cuisine.any}, Cuisine.any), isEmpty);
    });
  });

  group('UserPreferences', () {
    const complete = UserPreferences(
      budget: BudgetOption.min12000,
      distance: DistanceOption.walk10,
      companions: {CompanionType.professor, CompanionType.solo},
      cuisines: {Cuisine.korean, Cuisine.cafe},
      tags: {FoodTag.spicy},
      prioritizeUntried: true,
      universityId: 'u1',
    );

    test('requires budget and distance to be complete', () {
      expect(const UserPreferences().isComplete, isFalse);
      expect(
        const UserPreferences(budget: BudgetOption.any).isComplete,
        isFalse,
      );
      expect(complete.isComplete, isTrue);
    });

    test('RPC params carry structured values and NEVER a user id', () {
      final p = complete.toRpcParams();
      expect(p['p_budget_type'], 'min');
      expect(p['p_budget_amount_krw'], 12000);
      expect(p['p_travel_mode'], 'walk');
      expect(p['p_max_travel_minutes'], 10);
      expect(p['p_companion_types'], ['professor', 'solo']);
      expect(p['p_preferred_cuisines'], ['cafe', 'korean']);
      expect(p['p_preferred_tags'], ['spicy']);
      expect(p['p_prioritize_untried'], true);
      expect(p['p_university_id'], 'u1');
      expect(
        p.keys.where((k) => k.contains('user')).toList(),
        isEmpty,
        reason: 'the database takes the user from auth.uid()',
      );
    });

    test('"any" options are sent without amounts', () {
      final p = const UserPreferences(
        budget: BudgetOption.any,
        distance: DistanceOption.any,
      ).toRpcParams();
      expect(p['p_budget_type'], 'any');
      expect(p['p_budget_amount_krw'], isNull);
      expect(p['p_travel_mode'], 'any');
      expect(p['p_max_travel_minutes'], isNull);
      expect(p['p_companion_types'], isEmpty);
    });

    test('fromJson reads what the database stores', () {
      final prefs = UserPreferences.fromJson({
        'budget_type': 'max',
        'budget_amount_krw': 10000,
        'travel_mode': 'drive',
        'max_travel_minutes': 15,
        'companion_type': 'friends_2_3', // legacy column only
        'preferred_cuisines': ['japanese', 'nonsense'],
        'preferred_tags': ['light'],
        'prioritize_untried': true,
        'university_id': 'u2',
      });
      expect(prefs.budget, BudgetOption.max10000);
      expect(prefs.distance, DistanceOption.drive15);
      expect(prefs.companions, {CompanionType.friends});
      expect(prefs.cuisines, {
        Cuisine.japanese,
      }, reason: 'unknown values dropped');
      expect(prefs.tags, {FoodTag.light});
      expect(prefs.prioritizeUntried, isTrue);
    });
  });

  group('companions (multi-select)', () {
    test('several companions serialize to a sorted array', () {
      const prefs = UserPreferences(
        budget: BudgetOption.any,
        distance: DistanceOption.any,
        companions: {
          CompanionType.professor,
          CompanionType.solo,
          CompanionType.friends,
        },
      );
      expect(prefs.toRpcParams()['p_companion_types'], [
        'friends_2_3',
        'professor',
        'solo',
      ]);
    });

    test('zero selections are valid and send an empty array', () {
      const prefs = UserPreferences(
        budget: BudgetOption.any,
        distance: DistanceOption.any,
      );
      expect(prefs.isComplete, isTrue, reason: 'companions are optional');
      expect(prefs.toRpcParams()['p_companion_types'], <String>[]);
    });

    test('deserializes companion_types and drops unknown values', () {
      final prefs = UserPreferences.fromJson({
        'companion_types': ['solo', 'group_4_plus', 'martian'],
      });
      expect(prefs.companions, {CompanionType.solo, CompanionType.group});
    });

    test(
      'rows written before the change (single companion_type) still load',
      () {
        expect(
          UserPreferences.fromJson({'companion_type': 'junior'}).companions,
          {CompanionType.junior},
        );
        expect(
          UserPreferences.fromJson({'companion_type': null}).companions,
          isEmpty,
        );
        expect(UserPreferences.fromJson({}).companions, isEmpty);
      },
    );

    test('companion_types wins over the deprecated column', () {
      final prefs = UserPreferences.fromJson({
        'companion_type': 'solo',
        'companion_types': ['senior', 'junior'],
      });
      expect(prefs.companions, {CompanionType.senior, CompanionType.junior});
    });

    test('round trip keeps every selection and all other fields', () {
      const original = UserPreferences(
        budget: BudgetOption.min12000,
        distance: DistanceOption.walk15,
        companions: {CompanionType.solo, CompanionType.professor},
        cuisines: {Cuisine.cafe},
        tags: {FoodTag.light},
        prioritizeUntried: true,
      );
      final p = original.toRpcParams();
      final back = UserPreferences.fromJson({
        'budget_type': p['p_budget_type'],
        'budget_amount_krw': p['p_budget_amount_krw'],
        'travel_mode': p['p_travel_mode'],
        'max_travel_minutes': p['p_max_travel_minutes'],
        'companion_types': p['p_companion_types'],
        'preferred_cuisines': p['p_preferred_cuisines'],
        'preferred_tags': p['p_preferred_tags'],
        'prioritize_untried': p['p_prioritize_untried'],
      });
      expect(back, original);
    });

    test(
      'companions never change the restaurant filter (no capacity data)',
      () {
        final all = [fakeRestaurant('1', distance: 100)];
        expect(
          applyPreferences(
            all,
            const UserPreferences(companions: {CompanionType.group}),
          ).map((e) => e.kakaoId),
          ['1'],
        );
      },
    );
  });

  group('applyPreferences (only what real data supports)', () {
    final near = fakeRestaurant('1', distance: 300);
    final mid = fakeRestaurant('2', distance: 700, category: '음식점 > 일식');
    final far = fakeRestaurant('3', distance: 3000);
    final cafe = fakeRestaurant(
      '4',
      distance: 200,
      category: '음식점 > 카페',
      group: 'CE7',
    );
    final all = [far, mid, cafe, near];

    test(
      'walking radius uses an approximate meters-per-minute, nearest first',
      () {
        final r = applyPreferences(
          all,
          const UserPreferences(distance: DistanceOption.walk10),
        );
        // 10 min * 80 m = 800 m
        expect(r.map((e) => e.kakaoId), ['1', '2']);
      },
    );

    test('driving radius is wider', () {
      final r = applyPreferences(
        all,
        const UserPreferences(distance: DistanceOption.drive10),
      );
      expect(r.map((e) => e.kakaoId), ['1', '2', '3']);
    });

    test('"상관없어요" distance filters nothing', () {
      final r = applyPreferences(
        all,
        const UserPreferences(distance: DistanceOption.any),
      );
      expect(r.length, 3, reason: 'cafe excluded unless asked for');
    });

    test(
      'cuisine filter uses Kakao category_name; cafes only when requested',
      () {
        expect(
          applyPreferences(
            all,
            const UserPreferences(cuisines: {Cuisine.japanese}),
          ).map((e) => e.kakaoId),
          ['2'],
        );
        expect(
          applyPreferences(
            all,
            const UserPreferences(cuisines: {Cuisine.cafe}),
          ).map((e) => e.kakaoId),
          ['4'],
        );
      },
    );

    test('"상관없음" filters nothing', () {
      final r = applyPreferences(
        all,
        const UserPreferences(cuisines: {Cuisine.any}),
      );
      expect(r.length, 3);
    });

    test(
      'budget / companion / tags are NOT applied (no price or capacity data)',
      () {
        final base = applyPreferences(all, const UserPreferences());
        final withSoft = applyPreferences(
          all,
          const UserPreferences(
            budget: BudgetOption.max8000,
            companions: {CompanionType.professor},
            tags: {FoodTag.value},
            prioritizeUntried: true,
          ),
        );
        expect(withSoft.map((e) => e.kakaoId), base.map((e) => e.kakaoId));
      },
    );
  });
}
