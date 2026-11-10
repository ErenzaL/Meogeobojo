# Monthly mission system

Missions, campaigns, points and badges. Progress is **computed by the database
from real data**; the app and the admin dashboard only read it and ask for
changes through functions that check permissions.

## How it works

```
Flutter app ──sync_my_missions() / log_activity()──▶ Supabase (SECURITY DEFINER)
   │                                                   │  recompute from favorites, reviews,
   │  shows what comes back                            │  approved contributions, activity
   ▼                                                   ▼
 미션 tab, MY badges                   user_mission_progress / point_transactions / user_badges
Admin web ──admin_* functions──▶ same project, role checked in SQL, audited in audit_log
```

* `sync_my_missions()` recomputes the caller's missions and returns the whole
  dashboard (current campaign, missions with progress, points, badges, and
  `newly_completed` for the celebration).
* `log_activity('recommendation_view' | 'category_explore', ref)` records the
  few actions that have no table of their own. One row per user, event, ref and
  **Seoul day**: repeated taps change nothing. It re-evaluates and returns what
  it completed.
* The Flutter app calls them when: the 미션 tab opens, the tab is revisited,
  a place is saved or un-saved (de-bounced), **오늘의 추천 받기** is tapped
  (`recommendation_view`), a Home or category-page category other than 전체 is
  chosen (`category_explore`). Guests never call them.

## Rule types (what a mission can count)

| `rule_type` | Counts | Source |
|---|---|---|
| `favorite_distinct` | distinct saved places in the window | `favorites` |
| `favorite_cheap` | distinct saved places whose **published** admin price is ≤ `max_price_krw` | `favorites` + `restaurant_overrides` (unknown / draft prices never count) |
| `activity_days` | distinct Seoul days with `params.event` | `activity_events` |
| `activity_refs` | distinct refs of `params.event`, minus `params.exclude` | `activity_events` |
| `review_valid` | visible reviews with ≥ `min_chars` characters | `student_reviews` |
| `contribution_approved` | contributions of `params.kind` approved by an admin | `user_contributions` |
| `missions_completed` | other missions of the campaign completed (the "마스터" mission) | `user_mission_progress` |

New campaigns, missions, targets, rewards, dates, campuses and badges are data
(admin dashboard); only a **new rule type** needs a migration.

## Periods and time zones

All timestamps are `timestamptz` (UTC). Periods are **Asia/Seoul** calendar
periods: `daily` resets at 00:00 KST, `weekly` on Monday 00:00 KST, campaigns
and dated missions use an **exclusive** end (November ends 2026-12-01 00:00 KST,
shown as 2026.11.30). Only actions inside the window count.

## Rewards cannot be duplicated

* `point_transactions_one_reward`: a unique index on `(user, lineage, period)` for
  rewards. Re-running the evaluator, racing two calls (a per-user advisory lock
  serialises them), or editing a mission into a new version cannot pay twice.
* Completion is sticky: un-saving a place later does not take a completed mission back.
* Badges are unique per `(user, badge_key)`.
* Clients have **no** write grant on progress, points, badges, events or
  contributions; RLS lets users read only their own rows.

## Editing a live mission (versioning)

`admin_save_mission` edits in place for wording changes. If a mission already
has progress and the edit changes the target, reward, rule, parameters,
recurrence, campus or dates, it creates **version + 1** (same `lineage_id`),
archives the old row, and leaves earned progress, points and badges untouched.
Users who already completed the mission are not paid again.

## Admin dashboard (미션 관리)

One sidebar entry, five tabs: **미션** (create / edit / duplicate / activate /
pause / archive, with a live app preview), **캠페인** (draft → scheduled →
active → ended; banner preview; publish with a reason), **분석** (participants,
completion rates, points, trends, by campus, vs. overall app activity),
**사용자 진행** (search, history, revoke a reward or badge with a reason,
suspicious-activity leads), **기여 검토** (approve / reject photos and
corrections; moderators can use this tab). There is deliberately no function
that edits progress or a balance: a bad reward is reversed with an audited
negative ledger row, and the same period is never paid again.

Mascots for banners and badges are chosen from the artwork the app already
ships (`assets/images/mascot/`, mirrored in `admin/public/mascot/`); no new
characters.

## Setup (nothing has been applied to the hosted project)

1. Apply `supabase/migrations/20261110000100_missions.sql` after
   `20261109000100_admin_foundation.sql` (SQL editor or `supabase db push`). It is
   additive and idempotent, and seeds the 11월 미션 campaign (published, Nov 2026)
   with the eight missions from the brief plus a daily, a weekly and two
   achievement missions. No user progress is seeded.
2. Nothing else to configure: the app and admin already use the publishable
   key; the service-role key is never used by either.
3. Pause or edit the seeded missions from 미션 관리 if you want different ones.

## Known limits (honest list)

* The Flutter app has **no UI to write a review, upload a menu photo, or suggest
  a correction yet**. The database, rules and admin review queue for them are
  built and tested, and those missions' buttons say "준비 중" in the app. Their
  progress moves only when such submissions exist (a review row, or an
  approved `user_contributions` row). There is no photo storage bucket yet.
* Guests cannot see missions (they must sign in); the 미션 tab asks them to.
* Mission titles and descriptions are the Korean text an admin writes; the
  surrounding UI is localised (ko / en / zh).
* The reference screenshot "11월 미션" was not attached to the request, so the
  layout follows the written spec.

## Tests

* Database: `zsh supabase/tests/run_local.sh <scratch-dir>` (mission suite:
  `supabase/tests/missions_test.sql`: RLS, duplicate-reward, windows, daily/weekly
  boundaries in Seoul time, versioning, revocation, authorization, audit).
* Flutter: `flutter test test/features/missions` (+ updated nav / MY tests).
* Admin: `cd admin && npm test` (`src/features/missions/*.test.*`).
