import '../../../core/config/app_assets.dart';

/// The profile pictures a user can pick: the app's own mascot artwork. The
/// value saved to `profiles.avatar_path` is [key] (never a file path), so the
/// stored value stays valid if the asset files are renamed or moved.
enum ProfileAvatar {
  standing('standing', AppAssets.mascotStanding),
  wink('wink', AppAssets.mascotHero),
  cheer('cheer', AppAssets.mascotCheer),
  sparkle('sparkle', AppAssets.mascotSparkle),
  burger('burger', AppAssets.mascotBurger),
  boba('boba', AppAssets.mascotBoba),
  searching('searching', AppAssets.mascotSearching),
  sleeping('sleeping', AppAssets.mascotSleeping);

  const ProfileAvatar(this.id, this.asset);

  final String id;
  final String asset;

  static const _prefix = 'mascot:';

  /// Value stored in `profiles.avatar_path`.
  String get key => '$_prefix$id';

  /// What a new account shows until the user picks something.
  static const fallback = ProfileAvatar.standing;

  /// The avatar for a stored value; null for nothing / an unknown value
  /// (older app versions, a hand-edited row), so callers fall back safely.
  static ProfileAvatar? fromKey(String? key) {
    if (key == null) return null;
    for (final a in values) {
      if (a.key == key) return a;
    }
    return null;
  }

  static ProfileAvatar resolve(String? key) => fromKey(key) ?? fallback;
}
