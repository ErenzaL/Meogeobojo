# Deployment: Flutter Web on Render

Static site, built by `scripts/render_build.sh` (see `render.yaml`).

| Setting | Value |
|---|---|
| Service type | Static Site |
| Build command | `bash scripts/render_build.sh` |
| Publish directory | `build/web` |
| Rewrite | `/*` → `/index.html` |

## Environment variables (Render dashboard)
| Name | Required | Notes |
|---|---|---|
| `SUPABASE_URL` | yes | project URL |
| `SUPABASE_PUBLISHABLE_KEY` | yes | **publishable/anon key only** |
| `KAKAO_JAVASCRIPT_KEY` | for the map | register the site domain for this key in Kakao Developers |
| `FLUTTER_VERSION` | no | defaults to `3.47.8` (needs Dart ≥ 3.13.7 per `pubspec.yaml`) |
| `TERMS_URL`, `PRIVACY_URL` | no | https links |

Never set a service-role/secret key here: everything passed to the build is
compiled into public JavaScript.

## How config reaches the app
- Web: values are compiled in with `--dart-define`. `pubspec.yaml` still lists
  `.env` as an asset (mobile reads it), so the script creates an **empty**
  `.env` and fails the build if the shipped `assets/.env` is not empty.
- Mobile/local: copy `.env.example` to `.env` (gitignored). `Env` prefers
  `--dart-define` values and falls back to `.env`.

## Why a clean clone used to fail
`.env` is gitignored but listed as an asset, so Render's clone lacked it and
`flutter build web` aborted with "No file or variants found for asset: .env",
which Flutter reports as "Failed to compile application for the Web".
The same applies to `flutter test` / `flutter analyze` on a fresh clone: copy
`.env.example` to `.env` first.

## After deploying, in Supabase / Kakao
- Add the Render URL to Supabase Auth → URL Configuration (redirect URLs).
- Add the Render domain to the Kakao JavaScript key's allowed domains and to
  the Kakao Login redirect settings.

## Rollback
Render → Deploys → pick the last good deploy → Rollback (or revert the commit).
