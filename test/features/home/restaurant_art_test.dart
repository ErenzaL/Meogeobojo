import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/theme/app_theme.dart';
import 'package:meogeobojo/features/home/widgets/restaurant_art.dart';
import 'package:meogeobojo/features/recommendation/restaurant_insight.dart';

import '../../support/fakes.dart';

void main() {
  const url = 'https://example.com/photo.jpg';

  Future<List<BoxFit?>> fitsOf(
    WidgetTester tester, {
    required bool whole,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: RestaurantArt(
          restaurant: fakeRestaurant('1', name: '식당'),
          insight: const RestaurantInsight(imageUrl: url),
          radius: 16,
          width: 900,
          height: 320,
          wholePhoto: whole,
        ),
      ),
    );
    return [
      for (final i in tester.widgetList<Image>(find.byType(Image)))
        if (i.image is NetworkImage) i.fit,
    ];
  }

  testWidgets('the #1 card shows the whole photo, not a cropped strip', (
    tester,
  ) async {
    // a contained copy (whole photo) over a blurred, covering copy (fill)
    expect(await fitsOf(tester, whole: true), [BoxFit.cover, BoxFit.contain]);
  });

  testWidgets('thumbnails keep filling their box', (tester) async {
    expect(await fitsOf(tester, whole: false), [BoxFit.cover]);
  });
}
