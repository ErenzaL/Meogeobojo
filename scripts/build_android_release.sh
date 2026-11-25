#!/usr/bin/env bash
# Reproducible Android production build. It refuses to hand you an APK that cannot reach the network.
#
#   bash scripts/build_android_release.sh
#
# Output: dist/android/meogeobojo-<version>+<build>-<git sha>.apk  (+ .sha256)
#
# Why the checks exist: the Android *release* manifest only merges src/main. INTERNET used to be declared only in
# src/debug and src/profile, so every release APK installed fine and then failed every request with
# "Failed host lookup" (shown as the internet-connection error) while debug builds and iOS/web worked.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "ERROR: $*" >&2; exit 1; }

AAPT="${AAPT:-$(ls "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"/build-tools/*/aapt 2>/dev/null | sort -V | tail -1)}"
[ -x "$AAPT" ] || fail "aapt not found. Set ANDROID_HOME (needs build-tools)."

# 1. Never ship server-side secrets inside the bundled .env asset.
bash scripts/check_bundled_env.sh

# 2. Production config must exist: dart-define or the bundled .env.
if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_PUBLISHABLE_KEY:-}" ]; then
  [ -f .env ] || fail ".env missing (or export SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY)."
  grep -q '^SUPABASE_URL=https://' .env || fail ".env: SUPABASE_URL must be an https:// URL."
  grep -q '^SUPABASE_PUBLISHABLE_KEY=.\+' .env || fail ".env: SUPABASE_PUBLISHABLE_KEY is empty."
  grep -Eq '^SUPABASE_URL=https://(localhost|127\.|10\.0\.2\.2)' .env && fail ".env points SUPABASE_URL at a local host."
fi

# 3. Build.
flutter build apk --release
SRC=build/app/outputs/flutter-apk/app-release.apk
[ -f "$SRC" ] || fail "build produced no $SRC"

# 4. Verify the APK itself (the merged manifest), not the source manifest.
PERMS="$("$AAPT" dump permissions "$SRC")"
for p in android.permission.INTERNET android.permission.ACCESS_NETWORK_STATE; do
  echo "$PERMS" | grep -q "uses-permission: name='$p'" || fail "APK is missing $p. Not shipping it."
done

# 5. The bundled config must match the project config and carry no secret names.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
if unzip -q -o "$SRC" 'assets/flutter_assets/.env' -d "$TMP" 2>/dev/null; then
  grep -q '^SUPABASE_URL=https://' "$TMP/assets/flutter_assets/.env" || fail "bundled .env has no https SUPABASE_URL."
  if grep -Eq '^(GEMINI_|[A-Z_]*SERVICE_ROLE|[A-Z_]*SECRET)' "$TMP/assets/flutter_assets/.env"; then
    fail "bundled .env contains a server-side secret name."
  fi
fi

# 6. Versioned, hash-stamped copy.
VERSION="$(sed -n 's/^version: *//p' pubspec.yaml | head -1)"
SHA="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
DIRTY=""; git diff --quiet 2>/dev/null || DIRTY="-dirty"
OUT="dist/android/meogeobojo-${VERSION}-${SHA}${DIRTY}.apk"
mkdir -p dist/android
cp "$SRC" "$OUT"
( cd dist/android && shasum -a 256 "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
echo "OK  $OUT"
echo "    permissions: INTERNET, ACCESS_NETWORK_STATE present"
echo "    NOTE: signed with the debug key unless android/key.properties exists."
