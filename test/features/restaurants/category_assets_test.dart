import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/config/app_assets.dart';
import 'package:meogeobojo/features/restaurants/models/food_category.dart';

void main() {
  test('every category artwork referenced in code exists on disk', () {
    final paths = [
      AppAssets.categoryCampusMeals,
      for (final c in FoodCategory.values)
        if (c.image != null) c.image!,
    ];
    for (final path in paths) {
      expect(File(path).existsSync(), isTrue, reason: '$path is missing');
    }
  });

  test('only 기타 falls back to a Material icon', () {
    final without = FoodCategory.values.where((c) => c.image == null);
    expect(without, [FoodCategory.etc]);
  });
}
