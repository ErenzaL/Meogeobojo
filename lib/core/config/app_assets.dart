abstract final class AppAssets {
  static const _mascot = 'assets/images/mascot';

  static const mascotHero = '$_mascot/mascot_jump_wink.png';
  static const mascotSearching = '$_mascot/mascot_searching.png';
  static const mascotMapConfused = '$_mascot/mascot_map_confused.png';
  static const mascotSleeping = '$_mascot/mascot_resting_sleep.png';
  static const mascotSparkle = '$_mascot/mascot_excited_sparkle.png';
  static const mascotCheer = '$_mascot/mascot_cheer_jump.png';
  static const mascotStanding = '$_mascot/mascot_default_standing.png';
  static const mascotBurger = '$_mascot/mascot_eating_burger.png';
  static const mascotBoba = '$_mascot/mascot_drink_boba.png';
  static const mascotRunning = '$_mascot/mascot_running_side.png';

  /// The existing mascot artwork by the short keys the database stores for
  /// campaign banners and badges (no new art; unknown keys fall back).
  static String mascotByKey(String? key) => switch (key) {
    'wink' => mascotHero,
    'cheer' => mascotCheer,
    'sparkle' => mascotSparkle,
    'burger' => mascotBurger,
    'boba' => mascotBoba,
    'searching' => mascotSearching,
    'sleeping' => mascotSleeping,
    'confused' => mascotMapConfused,
    'running' => mascotRunning,
    _ => mascotStanding,
  };

  // Category icons (3D artwork). 기타 has no artwork and keeps a Material icon.
  static const _categoryIcons = 'assets/icon_logo';

  static const categoryCampusMeals = '$_categoryIcons/campus_meals.png';
  static const categoryAll = '$_categoryIcons/all.png';
  static const categoryKorean = '$_categoryIcons/korean.png';
  static const categoryWestern = '$_categoryIcons/western.png';
  static const categoryChinese = '$_categoryIcons/chinese.png';
  static const categoryJapanese = '$_categoryIcons/japanese.png';
  static const categorySnack = '$_categoryIcons/snack.png';
  static const categoryCafe = '$_categoryIcons/cafe.png';
  static const categoryChicken = '$_categoryIcons/chicken.png';
  static const categoryFastFood = '$_categoryIcons/fast_food.png';
  static const categoryGlobal = '$_categoryIcons/global.png';
}
