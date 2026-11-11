import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant_override.dart';

/// Menus imported from a CSV and then published reach the app as ordinary `restaurant_menus` rows. These are the shapes
/// the Admin's import produces (see supabase/tests/menu_import_test.sql), including the unknown-price case: the app must
/// read an unknown price as "no price" (the detail screen shows a price only when it is not null), never as 0 won.
void main() {
  Map<String, dynamic> row(Map<String, dynamic> over) => {
    'name_ko': '우동',
    'description_ko': null,
    'price_krw': 6000,
    'category': '면류',
    'price_verified_on': null,
    'available': true,
    'representative': false,
    'recommended': false,
    'status': 'active',
    'sort_order': 2,
    'image_url': null,
    ...over,
  };

  test('an imported menu with a price reads as that price, not verified, active', () {
    final m = RestaurantMenuItem.fromJson(row({}))!;
    expect(m.name, '우동');
    expect(m.priceKrw, 6000);
    expect(m.category, '면류');
    expect(m.available, isTrue);
    expect(m.imageUrl, isNull);
  });

  test('an unknown price stays null in the app (never 0 won)', () {
    final m = RestaurantMenuItem.fromJson(row({'price_krw': null}))!;
    expect(m.priceKrw, isNull);
    expect(m.name, '우동');
  });

  test('an explicit price of 0 is kept as 0 (a free item), distinct from unknown', () {
    expect(RestaurantMenuItem.fromJson(row({'price_krw': 0}))!.priceKrw, 0);
  });

  test('a description with commas and Korean text survives, a sold-out flag is read', () {
    final m = RestaurantMenuItem.fromJson(
      row({'description_ko': '진한 국물, 차슈', 'available': false}),
    )!;
    expect(m.description, '진한 국물, 차슈');
    expect(m.available, isFalse);
  });

  test('an archived line (a menu taken off the list) never reaches the screen', () {
    expect(RestaurantMenuItem.fromJson(row({'status': 'archived'})), isNull);
  });
}
