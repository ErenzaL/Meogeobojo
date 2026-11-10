#!/usr/bin/env bash
# Builds the Flutter Web app on Render (or any clean CI machine).
#
# Why this exists: pubspec.yaml lists `.env` as an asset (mobile reads its
# config from it), but `.env` is gitignored, so a fresh clone has no such file
# and `flutter build web` fails with "No file or variants found for asset:
# .env" (reported as "Failed to compile application for the Web").
#
# For web we do NOT publish any `.env` content: an EMPTY placeholder `.env`
# satisfies the asset list, and the values are compiled in with
# --dart-define. Only client-safe (publishable) values may be passed; they are
# visible in the built JavaScript by design.
#
# Required env vars:  SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY
# Optional env vars:  KAKAO_JAVASCRIPT_KEY (web map), KAKAO_NATIVE_APP_KEY, FEEDBACK_URL / SUPPORT_EMAIL (website footer),
#                     TERMS_URL, PRIVACY_URL, FLUTTER_VERSION
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.8}"   # keep in sync with the local SDK
FLUTTER_HOME="${FLUTTER_HOME:-$HOME/flutter-$FLUTTER_VERSION}"

: "${SUPABASE_URL:?Set SUPABASE_URL in the Render environment}"
: "${SUPABASE_PUBLISHABLE_KEY:?Set SUPABASE_PUBLISHABLE_KEY in the Render environment}"

# 1. Flutter SDK (pinned). Render's static-site image has none.
if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
  echo "Installing Flutter $FLUTTER_VERSION into $FLUTTER_HOME"
  git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$FLUTTER_HOME"
fi
export PATH="$FLUTTER_HOME/bin:$PATH"
flutter --version

# 2. Placeholder .env (empty; never contains secrets) + compile-time defines.
for v in SUPABASE_URL SUPABASE_PUBLISHABLE_KEY KAKAO_JAVASCRIPT_KEY \
         KAKAO_NATIVE_APP_KEY TERMS_URL PRIVACY_URL FEEDBACK_URL SUPPORT_EMAIL; do
  case "${!v:-}" in *$'\n'*) echo "$v must be a single line" >&2; exit 1;; esac
done
: > .env
DEFINES=(
  "--dart-define=SUPABASE_URL=$SUPABASE_URL"
  "--dart-define=SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"
)
for v in KAKAO_JAVASCRIPT_KEY KAKAO_NATIVE_APP_KEY TERMS_URL PRIVACY_URL FEEDBACK_URL SUPPORT_EMAIL; do
  [ -n "${!v:-}" ] && DEFINES+=("--dart-define=$v=${!v}")
done

# 3. Build.
flutter config --no-analytics >/dev/null 2>&1 || true
flutter pub get
flutter build web --release "${DEFINES[@]}"

# The shipped .env must be empty.
[ ! -s build/web/assets/.env ] || { echo "build/web/assets/.env is not empty" >&2; exit 1; }
test -f build/web/main.dart.js || { echo "build/web/main.dart.js missing" >&2; exit 1; }
echo "Built build/web"
