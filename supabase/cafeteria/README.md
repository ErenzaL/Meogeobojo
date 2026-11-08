# 학식 (campus cafeteria menus) — administrator workflow

The app **reads** `campus_cafeterias` and `cafeteria_meals`. Nobody can write
them through the API (no policies, no grants for `anon`/`authenticated`); an
administrator imports data. **No menus or cafeteria names are seeded** — only
add what comes from a verified, permitted source.

## Data source status (checked 2026-11-01)
No permitted, machine-readable official source was found for the supported
campuses, so nothing was imported:

| University | Finding |
|---|---|
| 순천향대 | `robots.txt` is `Disallow: /` for automated clients (`Allow: /$` only). Do **not** scrape. |
| 한국기술교육대 | The page found is a campus-facilities page, not a menu feed. |
| 호서대, 단국대, 상명대 | robots.txt only addresses specific search crawlers; no menu API or terms permitting automated collection found. |
| 선문대, 백석대 | No robots.txt / no public menu feed found. |

Options that are permitted: ask the cafeteria/co-op for a feed or a weekly
file and permission to republish; use an official open-data API if one is
published; or have staff transcribe the posted weekly menu (a "manually
verified submission"). Never bypass logins or access controls.

## Import
1. Copy `cafeterias_template.csv`, fill it (university ids are in
   `lib/features/university/models/verified_universities.dart`), then:
   ```
   python3 supabase/cafeteria/import_cafeteria_csv.py cafeterias my_cafeterias.csv > /tmp/cafeterias.sql
   supabase db query --linked -f /tmp/cafeterias.sql
   ```
2. Copy `meals_template.csv`, fill one or many days, then:
   ```
   python3 supabase/cafeteria/import_cafeteria_csv.py meals my_meals.csv > /tmp/meals.sql
   supabase db query --linked -f /tmp/meals.sql
   ```
Re-importing the same row **updates** it (key = cafeteria + date + meal type +
option). `action=delete` removes a wrong row. A second choice in the same meal
period uses a different `option_name`. The script validates dates, meal types,
prices, times, https URLs and a mandatory `verified_at`; the SQL re-checks that
each cafeteria exists and belongs to the stated university, in one transaction.

`status`: `published` (menu listed), `closed` / `no_menu` (only when the source
**states** it; a missing row is shown as "not collected yet", never as closed).
Menu items: `kind:name` separated by `|` (`main`, `side`, `soup`, `rice`), or a
JSON array with optional `name_en` / `name_zh` when verified translations exist.
