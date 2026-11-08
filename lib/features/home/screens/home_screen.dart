import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../widgets/category_section.dart';
import '../widgets/home_header.dart';
import '../widgets/home_hero.dart';
import '../widgets/home_search_bar.dart';
import '../widgets/menu_section.dart';
import '../widgets/nearby_section.dart';
import '../widgets/recommendation_banner.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const pad = EdgeInsets.symmetric(horizontal: AppSpacing.screenH);
    return Scaffold(
      body: SafeArea(
        bottom: false, // the bottom bar in the shell handles the home indicator
        child: ListView(
          // Keeps scroll offset when the shell switches tabs (IndexedStack).
          key: const PageStorageKey('home-scroll'),
          // The shell reports the floating bar's footprint as bottom padding,
          // so the last cards can scroll fully above it.
          padding: EdgeInsets.only(
            top: 8,
            bottom: 24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: const [
            Padding(padding: pad, child: HomeHeader()),
            SizedBox(height: 18),
            Padding(padding: pad, child: HomeHero()),
            SizedBox(height: 18),
            Padding(padding: pad, child: HomeSearchBar()),
            SizedBox(height: 20),
            CategorySection(),
            SizedBox(height: 20),
            Padding(padding: pad, child: RecommendationBanner()),
            SizedBox(height: AppSpacing.sectionGap),
            NearbySection(),
            SizedBox(height: 8),
            MenuSection(),
          ],
        ),
      ),
    );
  }
}
