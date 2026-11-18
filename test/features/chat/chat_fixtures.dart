import 'package:meogeobojo/features/chat/logic/chat_engine.dart';
import 'package:meogeobojo/features/recommendation/providers/ranking_providers.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant_override.dart';

import '../../support/fakes.dart';

// fakeRestaurant puts a place [distance] metres north of the default start point; the engine walks at 80 m/min.
const originLat = 36.769563, originLng = 126.92736;

RestaurantMenuItem menu(
  String name,
  int? price,
  String category, {
  bool rep = false,
  bool available = true,
  String? description,
}) => RestaurantMenuItem(
  name: name,
  priceKrw: price,
  category: category,
  representative: rep,
  available: available,
  description: description,
);

class Fixture {
  Fixture() {
    // a: 100 m (1 min), f: 150 m (2), cafe: 200 m (3), b: 300 m (4), c: 500 m (6), e: 1500 m (19)
    pool = [
      fakeRestaurant('1', name: '든든', category: '음식점 > 한식 > 국밥', distance: 100),
      fakeRestaurant('2', name: '차이나', category: '음식점 > 중식', distance: 300),
      fakeRestaurant('3', name: '분식', category: '음식점 > 분식', distance: 500),
      fakeRestaurant('4', name: '카페', category: '음식점 > 카페', group: 'CE7', distance: 200),
      fakeRestaurant('5', name: '먼집', distance: 1500),
      fakeRestaurant('6', name: '메뉴없음', distance: 150),
      fakeRestaurant('7', name: '숨김', distance: 120),
    ];
    menus = {
      '1': [
        menu('순대국밥', 9000, '식사', rep: true),
        menu('수육', 25000, '기타'),
        menu('공기밥', 1000, '사이드'),
        menu('콜라', 2000, '음료'),
      ],
      '2': [
        menu('짜장면', 7000, '식사', rep: true),
        menu('짬뽕', 8500, '식사'),
        menu('탕수육', 18000, '기타'),
      ],
      '3': [menu('김밥', 4000, '분식'), menu('떡볶이', 5000, '분식')],
      '4': [menu('아메리카노', 4500, '음료'), menu('케이크', 6500, '기타')],
      '5': [menu('백반', 7000, '식사')],
      '7': [menu('비밀 정식', 7000, '식사')],
    };
  }

  late final List<Restaurant> pool;
  late final Map<String, List<RestaurantMenuItem>> menus;

  ChatSearchContext context({Set<String> hidden = const {'7'}}) =>
      ChatSearchContext(
        pool: pool,
        insights: insightsFrom(const {}, menus),
        menus: menus,
        lat: originLat,
        lng: originLng,
        nowMinutes: 12 * 60,
        hiddenIds: hidden,
      );
}
