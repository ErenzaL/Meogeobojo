#!/usr/bin/env python3
"""End-to-end check of the WEEKLY CAFETERIA system against a STAGING Supabase project.

  Admin RPCs  ->  Postgres  ->  what a student's app (anon key) reads
  (the same REST endpoints Flutter Web and Flutter Android use for campus_cafeterias / cafeteria_meals)

It WRITES (throw-away "[E2E]" cafeterias that it removes again), so:
  * it reads ONLY the STAGING_* variables, never admin/.env or the SUPABASE_* ones, and
  * it refuses the production project (ref below) unless --i-understand-this-is-production is given.

  STAGING_SUPABASE_URL=https://<staging-ref>.supabase.co STAGING_SUPABASE_PUBLISHABLE_KEY=... \
  STAGING_ADMIN_EMAIL=... STAGING_ADMIN_PASSWORD=... \
  python3 scripts/verify_cafeteria_e2e.py --yes-write-to-staging [--with-schedule] [--manual-check]

Checks: two universities; Monday-Friday x breakfast/lunch/dinner as ONE draft; two lunch options; 천원의 아침밥 on one date only;
draft invisible to students; atomic whole-week publish; university separation; publish of selected days; CSV import (dry run writes
nothing, drafts only, retry = unchanged, cross-university needs confirmation); unpublish clears the student view; rollback restores it;
(--with-schedule) the pg_cron runner publishes a scheduled week with no browser; cleanup.
--manual-check pauses with a menu published so you can look at Flutter Web and the Android app, then unpublishes and waits again so you
can confirm the app cleared it WITHOUT a restart.
Exit status: 0 all checks passed, 1 a check failed or the run crashed (cleanup is still attempted), 2 refused to start.
Unit tests: python3 -m unittest scripts/test_verify_cafeteria_e2e.py
"""
import datetime as dt, json, os, pathlib, sys, time, urllib.error, urllib.request

PRODUCTION_REF = 'jnnofemlolwdyonfhzje'


class Results:
    """Every check is one record (passed: bool, name, detail); values are coerced to a real bool in one place."""

    def __init__(self, echo=True):
        self.items, self.echo = [], echo

    def add(self, name, ok, detail=''):
        passed = bool(ok)
        self.items.append((passed, name, str(detail)))
        if self.echo:
            print(('PASS ' if passed else 'FAIL ') + name + (f'  [{detail}]' if detail else ''), flush=True)
        return passed

    @property
    def total(self):
        return len(self.items)

    @property
    def passed(self):
        return sum(1 for ok, _, _ in self.items if ok)

    @property
    def failed(self):
        return [n for ok, n, _ in self.items if not ok]

    def summary(self):
        line = f'{self.passed}/{self.total} checks passed.'
        return line + (f' {len(self.failed)} FAILED: ' + '; '.join(self.failed) if self.failed else '')

    def exit_code(self):
        return 0 if self.total > 0 and not self.failed else 1

    def finish(self):
        print('\n' + self.summary(), flush=True)
        return self.exit_code()


class _Abort(Exception):
    """A step the rest depends on failed (already recorded): stop, clean up, report."""


CFG = {'url': '', 'key': ''}
sleep = time.sleep


def http(method, path, body=None, token=None, extra=None):
    h = {'apikey': CFG['key'], 'Authorization': 'Bearer ' + (token or CFG['key']), 'Content-Type': 'application/json'}
    h.update(extra or {})
    req = urllib.request.Request(CFG['url'] + path, data=None if body is None else json.dumps(body).encode(), headers=h, method=method)
    try:
        r = urllib.request.urlopen(req, timeout=40)
        txt = r.read().decode('utf8', 'ignore')
        return r.status, (json.loads(txt) if txt else None)
    except urllib.error.HTTPError as e:
        txt = e.read().decode('utf8', 'ignore')
        try:
            return e.code, json.loads(txt)
        except Exception:
            return e.code, txt


def rpc(name, args, token):
    return http('POST', f'/rest/v1/rpc/{name}', args, token)


def student_meals(cafeteria_id):
    """What a student's app reads: anon key, no filters but the cafeteria."""
    s, rows = http('GET', f'/rest/v1/cafeteria_meals?cafeteria_id=eq.{cafeteria_id}&select=id,meal_date,meal_type,option_name,price_krw,badge,menu_items,status&order=meal_date,meal_type,option_order')
    return rows if s == 200 and isinstance(rows, list) else None


def student_cafeterias(university_id):
    s, rows = http('GET', f'/rest/v1/campus_cafeterias?university_id=eq.{university_id}&select=id,name_ko,status')
    return rows if s == 200 and isinstance(rows, list) else None


def next_monday(today=None):
    d = today or dt.date.today()
    return d + dt.timedelta(days=(7 - d.weekday()) % 7 or 7)


def week_meals(monday, tag=''):
    """15 weekday slots + a second lunch option on Tuesday; 천원의 아침밥 on Monday only."""
    out = []
    stamp = f'{monday.isoformat()}T00:00:00+09:00'
    for i in range(5):
        date = (monday + dt.timedelta(days=i)).isoformat()
        for t, price, (a, b) in (('breakfast', 3000, ('08:00', '09:30')), ('lunch', 5500, ('11:30', '13:30')), ('dinner', 6000, ('17:00', '19:00'))):
            out.append({'date': date, 'meal_type': t, 'option_name': '', 'option_order': 0, 'menu_items': [{'name_ko': f'{t} {date}{tag}', 'kind': 'main'}],
                        'price_krw': price, 'start_time': a, 'end_time': b, 'status': 'published', 'badge': None, 'source_url': None, 'verified_at': stamp, 'extra': {}})
    out[0].update(badge='천원의 아침밥', price_krw=1000, source_url='https://example.org/e2e-official')
    out.append({'date': (monday + dt.timedelta(days=1)).isoformat(), 'meal_type': 'lunch', 'option_name': 'B코너', 'option_order': 1,
                'menu_items': [{'name_ko': f'돈까스{tag}', 'kind': 'main'}], 'price_krw': 7000, 'start_time': '11:30', 'end_time': '13:30', 'status': 'published',
                'badge': None, 'source_url': None, 'verified_at': stamp, 'extra': {'description': 'B 메뉴'}})
    order = {'breakfast': 0, 'lunch': 1, 'dinner': 2}
    return sorted(out, key=lambda m: (m['date'], order[m['meal_type']], m['option_order']))


def check_args(argv, env):
    """Returns (ok, message). Pure, so it is unit-tested."""
    url = (env.get('STAGING_SUPABASE_URL') or '').rstrip('/')
    if '--yes-write-to-staging' not in argv:
        return False, 'Refusing to write without --yes-write-to-staging (see the docstring).'
    if not url or not env.get('STAGING_SUPABASE_PUBLISHABLE_KEY') or not env.get('STAGING_ADMIN_EMAIL') or not env.get('STAGING_ADMIN_PASSWORD'):
        return False, 'Set STAGING_SUPABASE_URL, STAGING_SUPABASE_PUBLISHABLE_KEY, STAGING_ADMIN_EMAIL and STAGING_ADMIN_PASSWORD.'
    if PRODUCTION_REF in url and '--i-understand-this-is-production' not in argv:
        return False, f'{url} is the PRODUCTION project. This script creates and deletes test data; refusing.'
    if not url.startswith('https://'):
        return False, 'STAGING_SUPABASE_URL must start with https://'
    return True, ''


def main(argv=None, env=None):
    argv = sys.argv[1:] if argv is None else argv
    env = dict(os.environ) if env is None else env
    ok, msg = check_args(argv, env)
    if not ok:
        print(msg, file=sys.stderr)
        return 2
    CFG.update(url=env['STAGING_SUPABASE_URL'].rstrip('/'), key=env['STAGING_SUPABASE_PUBLISHABLE_KEY'])
    R = Results()
    s, auth = http('POST', '/auth/v1/token?grant_type=password', {'email': env['STAGING_ADMIN_EMAIL'], 'password': env['STAGING_ADMIN_PASSWORD']})
    if not R.add('admin sign-in', s == 200 and isinstance(auth, dict) and 'access_token' in auth, f'HTTP {s}'):
        return R.finish()
    tok = auth['access_token']
    created = []        # cafeteria ids to remove
    monday = next_monday()
    ws = monday.isoformat()
    try:
        s, unis = http('GET', '/rest/v1/universities?select=id,name_ko&is_active=eq.true&order=name_ko&limit=2')
        if not R.add('two universities exist', s == 200 and isinstance(unis, list) and len(unis) == 2, f'HTTP {s}'):
            raise _Abort()
        ua, ub = unis
        mk = {'kind': 'student', 'status': 'inactive', 'meal_periods': ['breakfast', 'lunch', 'dinner'], 'operating_days': [1, 2, 3, 4, 5]}
        ids = {}
        for key, uni in (('a', ua), ('b', ub)):
            s, r = http('POST', '/rest/v1/campus_cafeterias', {**mk, 'university_id': uni['id'], 'name_ko': f'[E2E] 학생식당 {key.upper()}'}, tok, {'Prefer': 'return=representation'})
            made = s in (200, 201) and isinstance(r, list) and len(r) == 1
            if made:
                ids[key] = r[0]['id']; created.append(r[0]['id'])
            if not R.add(f'create a cafeteria for {uni["name_ko"]} (inactive)', made, f'HTTP {s} {r if s >= 300 else ""}'):
                raise _Abort()
        R.add('students do not see the new (inactive) cafeterias', not [c for c in (student_cafeterias(ua['id']) or []) if c['id'] == ids['a']] and not [c for c in (student_cafeterias(ub['id']) or []) if c['id'] == ids['b']])

        ents = {}
        for key in ('a', 'b'):
            s, e = rpc('cafeteria_week_entity', {'p_cafeteria': ids[key], 'p_week': ws}, tok)
            ents[key] = e
            R.add(f'week entity for cafeteria {key.upper()}', s == 200 and isinstance(e, str), f'HTTP {s}')
        meals = week_meals(monday)
        R.add('a full week is 15 slots + 1 extra option', len(meals) == 16 and len({(m['date'], m['meal_type']) for m in meals}) == 15)

        s, d = rpc('cms_save_draft', {'p_type': 'cafeteria_week', 'p_id': ents['a'], 'p_data': {'meals': meals}, 'p_expected_revision': 0}, tok)
        R.add('save the whole week as ONE draft', s == 200, f'HTTP {s} {d if s >= 300 else ""}')
        R.add('a draft week is invisible to students', student_meals(ids['a']) == [])
        s, bad = rpc('cms_save_draft', {'p_type': 'cafeteria_week', 'p_id': ents['b'], 'p_data': {'meals': [{**meals[0], 'badge': '천원의 아침밥', 'source_url': None}]}, 'p_expected_revision': 0}, tok)
        R.add('천원의 아침밥 without an official source is refused', s >= 400, f'HTTP {s}')

        # students only ever see ACTIVE cafeterias: switch A on, publish the week
        s, _ = http('PATCH', f'/rest/v1/campus_cafeterias?id=eq.{ids["a"]}', {'status': 'active'}, tok)
        R.add('switch cafeteria A on', s in (200, 204), f'HTTP {s}')
        R.add('still nothing visible (the week is a draft)', student_meals(ids['a']) == [])
        s, v = rpc('cms_publish', {'p_type': 'cafeteria_week', 'p_id': ents['a'], 'p_expected_revision': 1, 'p_reason': 'E2E 주간 게시'}, tok)
        R.add('publish the whole week (one atomic call)', s == 200, f'HTTP {s} {v if s >= 400 else ""}')
        live = student_meals(ids['a']) or []
        R.add('students see all 16 menus', len(live) == 16, str(len(live)))
        R.add('five weekdays x three meals', {(m['meal_date'], m['meal_type']) for m in live} == {(m['date'], m['meal_type']) for m in meals})
        R.add('two lunch options on Tuesday', len([m for m in live if m['meal_type'] == 'lunch' and m['meal_date'] == (monday + dt.timedelta(days=1)).isoformat()]) == 2)
        R.add('천원의 아침밥 on exactly one date', [m['meal_date'] for m in live if m['badge'] == '천원의 아침밥'] == [ws])
        R.add('university separation: the other university has no cafeteria menus', (student_meals(ids['b']) or []) == [])

        # selected days: change Tue lunch + Thu dinner, publish only Tuesday
        d = [dict(m) for m in meals]
        for m in d:
            if m['date'] == (monday + dt.timedelta(days=1)).isoformat() and m['meal_type'] == 'lunch' and m['option_name'] == '':
                m['price_krw'] = 6000
            if m['date'] == (monday + dt.timedelta(days=3)).isoformat() and m['meal_type'] == 'dinner':
                m['price_krw'] = 6100
        s, _ = rpc('cms_save_draft', {'p_type': 'cafeteria_week', 'p_id': ents['a'], 'p_data': {'meals': d}, 'p_expected_revision': 0}, tok)
        R.add('draft with two changed days', s == 200, f'HTTP {s}')
        s, _ = rpc('cms_publish_week_days', {'p_id': ents['a'], 'p_expected_revision': 1, 'p_days': [(monday + dt.timedelta(days=1)).isoformat()], 'p_reason': 'E2E 화요일만'}, tok)
        R.add('publish only Tuesday', s == 200, f'HTTP {s}')
        live = {(m['meal_date'], m['meal_type'], m['option_name']): m['price_krw'] for m in (student_meals(ids['a']) or [])}
        R.add('Tuesday changed, Thursday did not', live.get(((monday + dt.timedelta(days=1)).isoformat(), 'lunch', '')) == 6000 and live.get(((monday + dt.timedelta(days=3)).isoformat(), 'dinner', '')) == 6100 - 100)

        # CSV import: preview writes nothing; drafts only; retry unchanged; cross-university needs confirmation
        nxt = (monday + dt.timedelta(days=7))
        rows = [{'line': 2, 'university': ua['name_ko'], 'cafeteria_name': '[E2E] 학생식당 A', 'date': nxt.isoformat(), 'meal_type': 'lunch', 'menu_name': 'CSV 제육', 'price': '5500', 'start_time': '11:30', 'end_time': '13:30'},
                {'line': 3, 'university': ub['name_ko'], 'cafeteria_name': '[E2E] 학생식당 B', 'date': nxt.isoformat(), 'meal_type': 'lunch', 'menu_name': 'CSV 비빔밥', 'price': '5000', 'start_time': '11:30', 'end_time': '13:30'}]
        s, pre = rpc('cafeteria_import', {'p_rows': rows, 'p_mode': 'create_only', 'p_dry_run': True, 'p_create_missing': False, 'p_allow_multi_university': False}, tok)
        R.add('CSV preview (dry run) plans 2 creations and flags two universities', s == 200 and pre['summary']['created'] == 2 and pre['multi_university'] is True, f'HTTP {s}')
        s, _ = rpc('cafeteria_import', {'p_rows': rows, 'p_mode': 'create_only', 'p_dry_run': False, 'p_create_missing': False, 'p_allow_multi_university': False}, tok)
        R.add('importing two universities without confirmation is refused', s >= 400, f'HTTP {s}')
        s, ap = rpc('cafeteria_import', {'p_rows': rows, 'p_mode': 'create_only', 'p_dry_run': False, 'p_create_missing': False, 'p_allow_multi_university': True}, tok)
        R.add('confirmed import saves drafts', s == 200 and ap['summary']['created'] == 2 and ap['summary']['weeks_changed'] == 2, f'HTTP {s}')
        R.add('imported menus are invisible to students', all((student_meals(ids[k]) or []) == [] or k == 'a' for k in ('a', 'b')) and not [m for m in (student_meals(ids['a']) or []) if m['meal_date'] == nxt.isoformat()])
        s, again = rpc('cafeteria_import', {'p_rows': rows, 'p_mode': 'upsert', 'p_dry_run': False, 'p_create_missing': False, 'p_allow_multi_university': True}, tok)
        R.add('the same CSV again changes nothing', s == 200 and again['summary']['unchanged'] == 2 and again['summary']['weeks_changed'] == 0, f'HTTP {s}')
        s, junk = rpc('cafeteria_import', {'p_rows': [{**rows[0], 'date': '2026-02-30', 'line': 9}], 'p_mode': 'upsert', 'p_dry_run': True, 'p_create_missing': False, 'p_allow_multi_university': False}, tok)
        R.add('an invalid date is reported per row', s == 200 and junk['summary']['failed'] == 1)

        # scheduling (needs pg_cron on the project)
        if '--with-schedule' in argv:
            http('PATCH', f'/rest/v1/campus_cafeterias?id=eq.{ids["b"]}', {'status': 'active'}, tok)
            wk_b = week_meals(monday, ' (예약)')
            s, _ = rpc('cms_save_draft', {'p_type': 'cafeteria_week', 'p_id': ents['b'], 'p_data': {'meals': wk_b}, 'p_expected_revision': 0}, tok)
            R.add('draft a week for cafeteria B', s == 200, f'HTTP {s}')
            run_at = (dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=2)).isoformat()
            s, _ = rpc('cms_schedule', {'p_type': 'cafeteria_week', 'p_id': ents['b'], 'p_expected_revision': 1, 'p_run_at': run_at, 'p_unpublish_at': None, 'p_reason': 'E2E 예약'}, tok)
            R.add('schedule it for ~2 minutes ahead', s == 200, f'HTTP {s}')
            R.add('invisible before the scheduled time', (student_meals(ids['b']) or []) == [])
            print('     waiting for pg_cron (cms-run-due-jobs), up to 4 minutes ...', flush=True)
            seen = []
            for _ in range(24):
                sleep(10)
                seen = student_meals(ids['b']) or []
                if seen:
                    break
            R.add('the SERVER published the scheduled week with no browser open', len(seen) == 16, str(len(seen)))

        # unpublish / rollback
        s, _ = rpc('cms_unpublish', {'p_type': 'cafeteria_week', 'p_id': ents['a'], 'p_reason': 'E2E 게시 중단'}, tok)
        R.add('unpublish the week', s == 200, f'HTTP {s}')
        R.add('students see NOTHING again (an empty answer, not stale data)', student_meals(ids['a']) == [])
        s, st = rpc('cms_state', {'p_type': 'cafeteria_week', 'p_id': ents['a']}, tok)
        s2, _ = rpc('cms_rollback', {'p_type': 'cafeteria_week', 'p_id': ents['a'], 'p_version': 1, 'p_reason': 'E2E 복원'}, tok)
        R.add('roll back to version 1', s == 200 and s2 == 200, f'HTTP {s}/{s2}')
        R.add('the first published week is back (16 menus)', len(student_meals(ids['a']) or []) == 16)

        if '--manual-check' in argv:
            print('\n  MANUAL CHECK 1: cafeteria "[E2E] 학생식당 A" now shows the week of ' + ws + ' - open Flutter Web and the Android app (pull to refresh if needed).')
            input('  Press Enter when you have looked ... ')
            s, _ = rpc('cms_unpublish', {'p_type': 'cafeteria_week', 'p_id': ents['a'], 'p_reason': 'E2E 수동 확인'}, tok)
            R.add('manual: unpublished for the live-clearing check', s == 200, f'HTTP {s}')
            print('  MANUAL CHECK 2: the menus must DISAPPEAR from both apps without restarting them (within ~1 s with migration 20261117000100, else within 60 s).')
            input('  Press Enter when you have confirmed it ... ')
    except _Abort:
        pass
    except Exception as e:
        R.add('unexpected error: ' + type(e).__name__, False, str(e)[:200])
    finally:
        for cid in created:
            try:
                for key, e in (('a', locals().get('ents', {}).get('a')), ('b', locals().get('ents', {}).get('b'))):
                    if e:
                        rpc('cms_unpublish', {'p_type': 'cafeteria_week', 'p_id': e, 'p_reason': 'E2E cleanup'}, tok)
                s, _ = http('DELETE', f'/rest/v1/campus_cafeterias?id=eq.{cid}', None, tok)
                if s in (200, 204):
                    s2, left = http('GET', f'/rest/v1/campus_cafeterias?id=eq.{cid}&select=id', None, tok)
                    R.add('cleanup: the test cafeteria is deleted', s2 == 200 and left == [], f'HTTP {s}')
                else:
                    s3, _ = http('PATCH', f'/rest/v1/campus_cafeterias?id=eq.{cid}', {'status': 'archived'}, tok)
                    R.add('cleanup: the test cafeteria is deleted (or at least archived)', s3 in (200, 204), f'delete HTTP {s}, archive HTTP {s3} - REMOVE "[E2E]" cafeterias by hand')
            except Exception as e:
                R.add('cleanup: the test cafeteria is deleted', False, f'cleanup raised {type(e).__name__}: {str(e)[:120]} - REMOVE "[E2E]" cafeterias by hand')
    return R.finish()


if __name__ == '__main__':
    sys.exit(main())
