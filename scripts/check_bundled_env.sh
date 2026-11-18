#!/usr/bin/env bash
# pubspec.yaml lists `.env` as a Flutter asset, so EVERYTHING in it is shipped inside the Android/iOS app and the web
# build, where anyone can read it. Server-side secrets (the Gemini key and model, a Supabase service-role key) belong in
# the Supabase Edge Function secrets, never here. This prints the offending KEY NAMES only (never a value) and fails.
#
#   bash scripts/check_bundled_env.sh        # run before building an app you hand to anyone
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] || exit 0
bad=$(grep -oE '^(GEMINI_[A-Z_]*|[A-Z_]*SERVICE_ROLE[A-Z_]*|[A-Z_]*SECRET[A-Z_]*)=' .env | tr -d '=' || true)
if [ -n "$bad" ]; then
  echo "ERROR: .env is bundled into the app, but it contains server-side secrets:" >&2
  echo "$bad" | sed 's/^/  - /' >&2
  echo "Remove these lines from .env (keep them only in Supabase: supabase secrets set NAME=...)." >&2
  exit 1
fi
echo ".env holds no server-side secret names."
