/// App nickname rules. The same rules are enforced by `set_nickname()` and a
/// CHECK constraint in the database; this is the friendly client-side copy.
///
/// Length is counted in Unicode code points (what PostgreSQL's char_length
/// counts), so Korean, Chinese, English and digits all count one per
/// character. Nicknames are NOT unique: the Supabase user id identifies the
/// account.
const kNicknameMinLength = 2;
const kNicknameMaxLength = 15;

enum NicknameError { empty, tooShort, tooLong, invalidChars }

class NicknameCheck {
  const NicknameCheck.valid(String this.value) : error = null;
  const NicknameCheck.invalid(NicknameError this.error) : value = null;

  /// The normalized nickname to save, when valid.
  final String? value;
  final NicknameError? error;

  bool get isValid => error == null;
}

// Control characters plus invisible / bidi-format characters that could make
// a nickname look blank or impersonate another one.
final _forbidden = RegExp(
  r'[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff]',
);
// Exotic spaces (NBSP, ideographic space ...) that become a normal space.
final _spaces = RegExp(r'[   -   　]');
final _spaceRuns = RegExp(r' {2,}');

NicknameCheck checkNickname(String raw) {
  var v = raw.trim();
  if (v.isEmpty) return const NicknameCheck.invalid(NicknameError.empty);
  if (_forbidden.hasMatch(v)) {
    return const NicknameCheck.invalid(NicknameError.invalidChars);
  }
  v = v.replaceAll(_spaces, ' ').replaceAll(_spaceRuns, ' ').trim();
  final length = v.runes.length;
  if (length < kNicknameMinLength) {
    return const NicknameCheck.invalid(NicknameError.tooShort);
  }
  if (length > kNicknameMaxLength) {
    return const NicknameCheck.invalid(NicknameError.tooLong);
  }
  return NicknameCheck.valid(v);
}
