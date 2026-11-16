# 먹어보조 (Meogeobojo)

> **A campus food guide for university students** — find nearby restaurants and cafés, check today's campus cafeteria (학식) menu, and get recommendations that match your taste and budget.

먹어보조 is a cross-platform [Flutter](https://flutter.dev) app backed by [Supabase](https://supabase.com) and the Kakao Maps / Local APIs. It is currently set up for several universities in the Asan / Cheonan area of South Korea and is available in **Korean, English and Chinese**.

## Features

- **Restaurant & café search** – keyword and category search around your campus, backed by Kakao Local data.
- **Map view** – browse results on a Kakao map.
- **Campus cafeteria (학식)** – daily menus per cafeteria and meal type.
- **Personalised recommendations** – onboarding collects budget, food preferences and who you usually eat with; recommendations are filtered accordingly.
- **Favorites** – save places to your account (stored by Kakao place id only).
- **Meal records & reviews** – mark places as "먹었어요" and leave a student review.
- **Accounts** – email sign-up/login and Kakao login through Supabase Auth, with a nickname/profile screen.
- **Multi-university** – pick your campus; the list falls back to a bundled copy if the backend is unreachable.
- **Localisation** – Korean (template), English, Chinese, switchable in-app.
- **Theming** – light/dark theme controller.

## Tech stack

| Area | Choice |
|---|---|
| Framework | Flutter (Dart SDK `^3.13.7`) |
| State management | [Riverpod](https://riverpod.dev) (`flutter_riverpod`) |
| Backend | Supabase (Postgres + RLS, Auth, Edge Functions) via `supabase_flutter` |
| Maps | `kakao_maps_flutter` |
| Config | `flutter_dotenv` (bundled `.env`) |
| Other | `shared_preferences`, `url_launcher`, `flutter_web_auth_2`, `intl` / `flutter_localizations` |

## Project structure

```
lib/
├── main.dart, app.dart        # entry point and root app widget
├── core/                      # config (Env), theme, l10n helpers, geo utils, shared widgets
├── features/                  # feature-first modules (models / providers / repositories / screens / widgets)
│   ├── auth/  campus_meals/  community/  favorites/  home/  map/
│   ├── navigation/  preferences/  profile/  recommendation/
│   ├── records/  restaurants/  search/  settings/  university/
├── l10n/                      # ARB files (ko / en / zh) + generated localisations
└── services/
supabase/
├── migrations/                # SQL schema, RLS and RPCs (apply in order, see supabase/README.md)
├── tests/                     # SQL tests (RLS, migrations) – run with tests/run_local.sh
└── cafeteria/                 # CSV templates + importer for cafeteria menu data
test/                          # widget and unit tests
```

## Getting started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) compatible with Dart `^3.13.7`
- A Supabase project
- A Kakao Developers app (for the **native app key** and Kakao login)

### 1. Clone and install

```bash
git clone https://github.com/ErenzaL/Meogeobojo.git
cd Meogeobojo
flutter pub get
```

### 2. Configure environment variables

Create a `.env` file in the project root with the keys below (`KEY=value`, one per line). It must exist even if empty, because it is listed as an asset; `flutter test` / `flutter analyze` fail on a fresh clone without it.

| Key | Required | Description |
|---|---|---|
| `SUPABASE_URL` | yes | Your Supabase project URL |
| `SUPABASE_PUBLISHABLE_KEY` | yes | Supabase publishable (anon) key |
| `KAKAO_NATIVE_APP_KEY` | mobile | Kakao **native** app key (for the map SDK) |
| `KAKAO_JAVASCRIPT_KEY` | web | Kakao **JavaScript** key (web map; register the site domain in Kakao) |
| `TERMS_URL` / `PRIVACY_URL` | no | `https` links to your legal documents |
| `FEEDBACK_URL` / `SUPPORT_EMAIL` | no | where questions and suggestions go |

> `.env` is git-ignored but is bundled into the app as an asset, so **only put client-safe values in it**. Never add the Kakao REST key or a Supabase service-role key — the REST key lives in Supabase Secrets and is used only by the `search_restaurants` Edge Function.

### 3. Set up the backend

Apply the SQL migrations in `supabase/migrations/` **in the order listed in [supabase/README.md](supabase/README.md)**, and deploy the `search_restaurants` Edge Function (it proxies Kakao Local search and holds the Kakao REST key as the `KAKAO_REST_API_KEY` secret). That document also covers the auth dashboard checklist (email + Kakao providers, redirect URL `com.meogeobojo.app://login-callback/`).

Cafeteria menus are not seeded; see [supabase/cafeteria/README.md](supabase/cafeteria/README.md) for the import workflow.

### 4. Run

```bash
flutter run
```

### Generate localisations / icons / splash

```bash
flutter gen-l10n
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

## Testing

```bash
flutter test
cd admin && npm ci && npm test
```

SQL tests (RLS isolation, migrations) run against a scratch PostgreSQL – see `supabase/tests/run_local.sh`.

## Deployment

Both sites are Render static sites defined in [`render.yaml`](render.yaml).

| Site | URL | Source |
|---|---|---|
| Student app (Flutter web) | https://meogeobojo.onrender.com | repo root, `scripts/render_build.sh` |
| Admin (React) | https://meogeobojo-admin.onrender.com | `admin/` |

Environment variables, Supabase/Kakao redirect settings and rollback: [docs/deployment.md](docs/deployment.md).
Release checklist for DB changes: [docs/publishing-deployment.md](docs/publishing-deployment.md).

## Admin

The admin site manages universities, restaurants, menus, cafeteria data, app content (announcements, banners) and review/photo moderation.
Sign in with an account that has the admin role; how to grant it and what each page does: [docs/admin.md](docs/admin.md).
To run it locally: `cd admin && cp .env.example .env && npm ci && npm run dev`.

## Notes

- Kakao Local API results are not stored permanently; favorites keep only the `kakao_place_id`.
- The `community` (밥수다) tab is "coming soon".

## License

No license has been specified yet. All rights reserved by the author until one is added.
