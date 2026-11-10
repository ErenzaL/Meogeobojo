#!/usr/bin/env python3
"""Live end-to-end check of the weekly cafeteria system on the PRODUCTION Supabase project, with THROW-AWAY data.

  Admin RPCs (what the Admin page calls)  ->  Postgres  ->  what a student's app reads with the publishable key
  (the same REST endpoints Flutter Web and Flutter mobile use for campus_cafeterias / cafeteria_meals)

It WRITES to production (briefly): one cafeteria named "[E2E] 주간 점검 <time>" in ONE university, a week of structured menus,
a CSV-style import, and removes the cafeteria again. It never touches an existing cafeteria or menu, and it proves that by
comparing what a student can read before and after. The cafeteria is switched on for the few minutes of the test (students can
only see active cafeterias), so a student who opens 학식 in that window could see "[E2E] 주간 점검" - run it when that is acceptable.

  ADMIN_EMAIL=... ADMIN_PASSWORD=... python3 scripts/verify_cafeteria_production.py --yes-i-approve-production-write \
      [--university 순천향대학교] [--with-schedule] [--manual-check]

URL and publishable key come from SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY or admin/.env (VITE_*); credentials only from the
environment. Refuses to run against any project other than production, and refuses if an "[E2E]" cafeteria already exists.
Checks (in order): preflight + baseline; draft invisible; selected structure (main/side/soup/rice/kimchi/salad/dessert, shared flags,
origin, notice, a confirmed HALAL label) reaches students after 지금 게시; selected-day publish; history and rollback; CSV import
with several dishes (preview, drafts only, retry unchanged, then published); unpublish clears the student view; (--with-schedule)
the pg_cron runner publishes with no browser; cleanup; and nothing else changed.
Exit status: 0 all passed, 1 a check failed (cleanup is still attempted), 2 refused to start.
"""
import datetime as dt, importlib.util, os, pathlib, re, sys

HERE = pathlib.Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location('cafe_e2e_base', HERE / 'verify_cafeteria_e2e.py')
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)
Results, _Abort, http, rpc, student_meals = base.Results, base._Abort, base.http, base.rpc, base.student_meals
PRODUCTION_REF = base.PRODUCTION_REF
TAG = '[E2E] 주간 점검'

ORIGIN = '쌀:국내산 / 배추김치:중국산 / 돈육:국내산 (E2E 점검용 문구)'
NOTICE = '상기 메뉴는 재료수급상황에 따라 변경될 수 있습니다 (E2E)'
SHARED = {'breakfast': [('아산쌀밥', 'rice'), ('김치', 'kimchi'), ('샐러드', 'salad')],
          'lunch': [('김치', 'kimchi'), ('샐러드', 'salad'), ('후식차', 'dessert')],
          'dinner': [('김치', 'kimchi'), ('샐러드', 'salad')]}


def read_env(env, root=HERE.parent):
    """Environment first, then admin/.env (VITE_* names); the credentials are never read from a file."""
    d = dict(env)
    p = root / 'admin' / '.env'
    if p.exists():
        for line in p.read_text().splitlines():
            m = re.match(r'\s*([A-Z_]+)\s*=\s*(.*)', line)
            if m:
                d.setdefault(m.group(1), m.group(2).strip().strip('"\''))
    return d


def check_args(argv, env):
    url = (env.get('SUPABASE_URL') or env.get('VITE_SUPABASE_URL') or '').rstrip('/')
    key = env.get('SUPABASE_PUBLISHABLE_KEY') or env.get('VITE_SUPABASE_ANON_KEY') or ''
    if '--yes-i-approve-production-write' not in argv:
        return False, 'Refusing to write to production without --yes-i-approve-production-write (see the docstring).'
    if not url or not key:
        return False, 'Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (or admin/.env).'
    if PRODUCTION_REF not in url:
        return False, f'{url} is not the production project; this script is only for production (use verify_cafeteria_e2e.py for staging).'
    if not env.get('ADMIN_EMAIL') or not env.get('ADMIN_PASSWORD'):
        return False, 'Set ADMIN_EMAIL and ADMIN_PASSWORD (an admin account) in the environment.'
    if len(key) > 60 and key.count('.') == 2 and '"role":"service_role"' in __import__('base64').urlsafe_b64decode(key.split('.')[1] + '==').decode('utf8', 'ignore').replace(' ', ''):
        return False, 'That key is a service-role key. Use the publishable (anon) key only.'
    return True, ''


def dish(name, kind, shared=False):
    return {'name_ko': name, 'kind': kind, **({'shared': True} if shared else {})}


def structured_week(monday, tag=''):
    """Five weekdays x breakfast/lunch/dinner as a menu table lists them: main, dishes, soup, then the shared row."""
    out = []
    stamp = f'{monday.isoformat()}T00:00:00+09:00'
    for i in range(5):
        date = (monday + dt.timedelta(days=i)).isoformat()
        for t, (a, b) in (('breakfast', ('08:00', '09:30')), ('lunch', ('11:30', '13:30')), ('dinner', ('17:00', '19:00'))):
            items = [dish(f'{t} 메인 {date}{tag}', 'main'), dish('새우튀김*타르타르', 'side'), dish(f'{t} 반찬 {date}', 'side'), dish(f'{t} 국 {date}', 'soup')]
            items += [dish(n, k, True) for n, k in SHARED[t]]
            extra = {'origin': ORIGIN, 'notice': NOTICE}
            if i == 4 and t == 'lunch':
                extra.update(labels=['HALAL'], labels_verified=True)
            out.append({'date': date, 'meal_type': t, 'option_name': '', 'option_order': 0, 'menu_items': items, 'price_krw': None, 'start_time': a, 'end_time': b,
                        'status': 'published', 'badge': None, 'source_url': None, 'verified_at': stamp, 'extra': extra})
    return out


def student_view(rows):
    """{(date, meal): [(name, kind, shared)]} exactly as a student's app would parse it."""
    return {(m['meal_date'], m['meal_type']): [(i['name_ko'], i.get('kind'), bool(i.get('shared'))) for i in m['menu_items']] for m in rows}


def expected_view(meals):
    return {(m['date'], m['meal_type']): [(i['name_ko'], i.get('kind'), bool(i.get('shared'))) for i in m['menu_items']] for m in meals}


def snapshot():
    """Everything a student can read about cafeterias and menus (ids only): the proof that nothing else changes."""
    out = {}
    for t in ('campus_cafeterias', 'cafeteria_meals'):
        s, rows = http('GET', f'/rest/v1/{t}?select=id&order=id')
        out[t] = sorted(r['id'] for r in rows) if s == 200 and isinstance(rows, list) else None
    return out


def main(argv=None, env=None):
    argv = sys.argv[1:] if argv is None else argv
    env = read_env(dict(os.environ) if env is None else env)
    ok, msg = check_args(argv, env)
    if not ok:
        print(msg, file=sys.stderr)
        return 2
    base.CFG.update(url=(env.get('SUPABASE_URL') or env.get('VITE_SUPABASE_URL')).rstrip('/'), key=env.get('SUPABASE_PUBLISHABLE_KEY') or env.get('VITE_SUPABASE_ANON_KEY'))
    R = Results()
    s, auth = http('POST', '/auth/v1/token?grant_type=password', {'email': env['ADMIN_EMAIL'], 'password': env['ADMIN_PASSWORD']})
    if not R.add('admin sign-in', s == 200 and isinstance(auth, dict) and 'access_token' in auth, f'HTTP {s}'):
        return R.finish()
    tok = auth['access_token']
    s, left = http('GET', '/rest/v1/campus_cafeterias?name_ko=like.*[E2E]*&select=id,name_ko', None, tok)
    if not R.add('preflight: no leftover "[E2E]" cafeteria from an earlier run', s == 200 and left == [], f'HTTP {s} {left if left else ""}'):
        return R.finish()
    before = snapshot()
    R.add('baseline: the student-visible cafeteria and menu lists were read', before['campus_cafeterias'] is not None and before['cafeteria_meals'] is not None)
    created, ents = [], {}
    monday = base.next_monday()
    ws, nxt = monday.isoformat(), (monday + dt.timedelta(days=7))
    wed = lambda n: (monday + dt.timedelta(days=n)).isoformat()
    try:
        q = '/rest/v1/universities?select=id,name_ko&is_active=eq.true&order=name_ko'
        if '--university' in argv:
            from urllib.parse import quote
            q += '&name_ko=eq.' + quote(argv[argv.index('--university') + 1])
        s, unis = http('GET', q + '&limit=1')
        if not R.add('a university to test with', s == 200 and isinstance(unis, list) and len(unis) == 1, f'HTTP {s}'):
            raise _Abort()
        uni = unis[0]
        name = f'{TAG} {dt.datetime.now().strftime("%H%M%S")}'
        s, r = http('POST', '/rest/v1/campus_cafeterias', {'university_id': uni['id'], 'kind': 'student', 'name_ko': name, 'status': 'inactive',
                    'meal_periods': ['breakfast', 'lunch', 'dinner'], 'operating_days': [1, 2, 3, 4, 5]}, tok, {'Prefer': 'return=representation'})
        if not R.add(f'create the throw-away cafeteria "{name}" in {uni["name_ko"]} (inactive)', s in (200, 201) and isinstance(r, list) and len(r) == 1, f'HTTP {s} {r if s >= 300 else ""}'):
            raise _Abort()
        cid = r[0]['id']; created.append(cid)
        s, ent = rpc('cafeteria_week_entity', {'p_cafeteria': cid, 'p_week': ws}, tok)
        ents['a'] = ent
        if not R.add('week entity (needs migration 20261118000100)', s == 200 and isinstance(ent, str), f'HTTP {s} {ent if s >= 300 else ""}'):
            raise _Abort()

        meals = structured_week(monday)
        s, d = rpc('cms_save_draft', {'p_type': 'cafeteria_week', 'p_id': ent, 'p_data': {'meals': meals}, 'p_expected_revision': 0}, tok)
        R.add('Admin: save a full structured week as ONE draft', s == 200, f'HTTP {s} {d if s >= 300 else ""}')
        R.add('a draft is invisible to students', student_meals(cid) == [])
        http('PATCH', f'/rest/v1/campus_cafeterias?id=eq.{cid}', {'status': 'active'}, tok)
        R.add('cafeteria switched on, the draft is still invisible', student_meals(cid) == [])
        s, pv = rpc('cms_state', {'p_type': 'cafeteria_week', 'p_id': ent}, tok)
        R.add('preview data: the draft differs from the (empty) live week', s == 200 and pv['draft'] is not None and pv['live']['meals'] == [])

        s, v = rpc('cms_publish', {'p_type': 'cafeteria_week', 'p_id': ent, 'p_expected_revision': 1, 'p_reason': 'E2E 지금 게시'}, tok)
        R.add('Admin: 지금 게시 (cms_publish, whole week)', s == 200, f'HTTP {s} {v if s >= 300 else ""}')
        s, live = http('GET', f'/rest/v1/cafeteria_meals?cafeteria_id=eq.{cid}&select=id,meal_date,meal_type,option_name,menu_items,extra,status&order=meal_date,meal_type')
        live = live if s == 200 else []
        R.add('students: 15 published meals, nothing else', len(live) == 15 and all(m['status'] == 'published' for m in live), str(len(live)))
        R.add('students: every dish, its category and its shared flag arrive in order', student_view(live) == expected_view(meals))
        R.add('students: origin statement and notice are on every meal', all(m['extra'].get('origin') == ORIGIN and m['extra'].get('notice') == NOTICE for m in live))
        R.add('students: the confirmed HALAL label is on Friday lunch only', [(m['meal_date'], m['meal_type']) for m in live if m['extra'].get('labels') == ['HALAL'] and m['extra'].get('labels_verified') is True] == [(wed(4), 'lunch')])
        R.add('students: a shared dish exists once per meal', all([i['name_ko'] for i in m['menu_items']].count('김치') == 1 for m in live))
        s, bad = rpc('cms_save_draft', {'p_type': 'cafeteria_week', 'p_id': ent, 'p_data': {'meals': [{**meals[0], 'extra': {'labels': ['HALAL']}}]}, 'p_expected_revision': 0}, tok)
        R.add('an unconfirmed HALAL label is refused by the server', s >= 400, f'HTTP {s}')

        # selected days: change Tuesday lunch (replace its soup) and Thursday dinner, publish Tuesday only
        d2 = [{**m, 'menu_items': [dict(i) for i in m['menu_items']]} for m in meals]
        for m in d2:
            if m['date'] == wed(1) and m['meal_type'] == 'lunch':
                m['menu_items'][3] = dish('된장국 (수정)', 'soup')
            if m['date'] == wed(3) and m['meal_type'] == 'dinner':
                m['menu_items'][3] = dish('미역국 (수정)', 'soup')
        s, _ = rpc('cms_save_draft', {'p_type': 'cafeteria_week', 'p_id': ent, 'p_data': {'meals': d2}, 'p_expected_revision': 0}, tok)
        R.add('Admin: edit two days in the draft', s == 200, f'HTTP {s}')
        s, _ = rpc('cms_publish_week_days', {'p_id': ent, 'p_expected_revision': 1, 'p_days': [wed(1)], 'p_reason': 'E2E 화요일만'}, tok)
        R.add('Admin: publish only Tuesday', s == 200, f'HTTP {s}')
        sv = student_view(student_meals(cid) or [])
        R.add('students: Tuesday lunch changed, Thursday dinner did not', ('된장국 (수정)', 'soup', False) in sv.get((wed(1), 'lunch'), []) and ('미역국 (수정)', 'soup', False) not in sv.get((wed(3), 'dinner'), []))

        # history and rollback
        s, st = rpc('cms_state', {'p_type': 'cafeteria_week', 'p_id': ent}, tok)
        R.add('history: two published versions exist', s == 200 and st.get('live_version') == 2, str(st.get('live_version') if isinstance(st, dict) else st))
        s, _ = rpc('cms_rollback', {'p_type': 'cafeteria_week', 'p_id': ent, 'p_version': 1, 'p_reason': 'E2E 복원'}, tok)
        R.add('Admin: restore version 1', s == 200, f'HTTP {s}')
        s, rows = http('GET', f'/rest/v1/cafeteria_meals?cafeteria_id=eq.{cid}&select=meal_date,meal_type,menu_items')
        R.add('students: the original week is back', s == 200 and student_view(rows) == expected_view(meals))

        # CSV import with several dishes -> drafts -> publish
        csvrows = [{'line': 2 + i, 'university': uni['name_ko'], 'cafeteria_name': name, 'date': (nxt + dt.timedelta(days=i)).isoformat(), 'meal_type': 'lunch',
                    'menu_name': f'CSV 메인 {i}', 'dishes': [dish('CSV 반찬', 'side'), dish('CSV 국', 'soup'), dish('김치', 'kimchi', True), dish('샐러드', 'salad', True)],
                    'origin': ORIGIN, 'notes': NOTICE, 'price': '', 'start_time': None, 'end_time': None} for i in range(2)]
        def imp(dry, mode='upsert'):
            return rpc('cafeteria_import', {'p_rows': csvrows, 'p_mode': mode, 'p_dry_run': dry, 'p_create_missing': False, 'p_allow_multi_university': False}, tok)
        s, pre = imp(True)
        R.add('CSV: the preview plans 2 creations and writes nothing', s == 200 and pre['summary']['created'] == 2 and student_meals(cid) is not None and len(student_meals(cid)) == 15, f'HTTP {s}')
        s, ap = imp(False)
        R.add('CSV: the import saves drafts', s == 200 and ap['summary']['created'] == 2 and ap['summary']['failed'] == 0, f'HTTP {s} {ap if s >= 300 else ""}')
        R.add('CSV: imported meals are invisible until published', len(student_meals(cid) or []) == 15)
        s, again = imp(False)
        R.add('CSV: the same file again changes nothing', s == 200 and again['summary']['unchanged'] == 2 and again['summary']['weeks_changed'] == 0, f'HTTP {s}')
        s, ent2 = rpc('cafeteria_week_entity', {'p_cafeteria': cid, 'p_week': nxt.isoformat()}, tok)
        s, st2 = rpc('cms_state', {'p_type': 'cafeteria_week', 'p_id': ent2}, tok)
        rev = (st2.get('draft') or {}).get('revision') if isinstance(st2, dict) else None
        s, _ = rpc('cms_publish', {'p_type': 'cafeteria_week', 'p_id': ent2, 'p_expected_revision': rev, 'p_reason': 'E2E CSV 게시'}, tok)
        R.add('Admin: 지금 게시 the imported week', s == 200 and rev is not None, f'HTTP {s}')
        s, rows = http('GET', f'/rest/v1/cafeteria_meals?cafeteria_id=eq.{cid}&meal_date=gte.{nxt.isoformat()}&select=meal_date,meal_type,menu_items')
        sv = student_view(rows) if s == 200 else {}
        R.add('students: the CSV dishes arrive with category and shared flag', sv.get((nxt.isoformat(), 'lunch')) == [('CSV 메인 0', 'main', False), ('CSV 반찬', 'side', False), ('CSV 국', 'soup', False), ('김치', 'kimchi', True), ('샐러드', 'salad', True)], str(sv.get((nxt.isoformat(), 'lunch'))))

        if '--with-schedule' in argv:
            ws3 = nxt + dt.timedelta(days=7)
            s, ent3 = rpc('cafeteria_week_entity', {'p_cafeteria': cid, 'p_week': ws3.isoformat()}, tok)
            s, _ = rpc('cms_save_draft', {'p_type': 'cafeteria_week', 'p_id': ent3, 'p_data': {'meals': structured_week(ws3, ' (예약)')}, 'p_expected_revision': 0}, tok)
            run_at = (dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=2)).isoformat()
            s, _ = rpc('cms_schedule', {'p_type': 'cafeteria_week', 'p_id': ent3, 'p_expected_revision': 1, 'p_run_at': run_at, 'p_unpublish_at': None, 'p_reason': 'E2E 예약'}, tok)
            R.add('Admin: schedule a week for ~2 minutes ahead', s == 200, f'HTTP {s}')
            seen = []
            print('     waiting for pg_cron (cms-run-due-jobs), up to 4 minutes ...', flush=True)
            for _ in range(24):
                base.sleep(10)
                s, seen = http('GET', f'/rest/v1/cafeteria_meals?cafeteria_id=eq.{cid}&meal_date=gte.{ws3.isoformat()}&select=id')
                if s == 200 and seen:
                    break
            R.add('the SERVER published the scheduled week with no browser open', isinstance(seen, list) and len(seen) == 15, str(len(seen) if isinstance(seen, list) else seen))
            rpc('cms_unpublish', {'p_type': 'cafeteria_week', 'p_id': ent3, 'p_reason': 'E2E cleanup'}, tok)

        if '--manual-check' in argv:
            print(f'\n  MANUAL CHECK: Flutter Web (and the app) -> 학식 -> {uni["name_ko"]} -> "{name}" should show the week of {ws}, with')
            print('  main / dishes / "함께 제공" / origin (tap "원산지 표시사항") and HALAL on Friday lunch.')
            input('  Press Enter when you have looked ... ')

        s, _ = rpc('cms_unpublish', {'p_type': 'cafeteria_week', 'p_id': ent, 'p_reason': 'E2E 게시 중단'}, tok)
        R.add('Admin: 게시 중단 (unpublish)', s == 200, f'HTTP {s}')
        rpc('cms_unpublish', {'p_type': 'cafeteria_week', 'p_id': ent2, 'p_reason': 'E2E 게시 중단'}, tok)
        R.add('students see NOTHING again (an empty answer clears stale data)', student_meals(cid) == [])
        if '--manual-check' in argv:
            print('  MANUAL CHECK: the menus must now DISAPPEAR from Flutter Web without a reload (within ~1 s, or pull to refresh).')
            input('  Press Enter when you have confirmed it ... ')
    except _Abort:
        pass
    except Exception as e:
        R.add('unexpected error: ' + type(e).__name__, False, str(e)[:200])
    finally:
        for cid in created:
            try:
                s, _ = http('DELETE', f'/rest/v1/campus_cafeterias?id=eq.{cid}', None, tok)
                if s in (200, 204):
                    s2, left = http('GET', f'/rest/v1/campus_cafeterias?id=eq.{cid}&select=id', None, tok)
                    R.add('cleanup: the test cafeteria (and its menus) is deleted', s2 == 200 and left == [], f'HTTP {s}')
                else:
                    s3, _ = http('PATCH', f'/rest/v1/campus_cafeterias?id=eq.{cid}', {'status': 'archived'}, tok)
                    # archived = hidden from students, but test data is still in production: that is a failed cleanup, never a pass
                    R.add('cleanup: the test cafeteria is deleted', False, f'delete HTTP {s}, archive HTTP {s3} ({"hidden from students" if s3 in (200, 204) else "STILL VISIBLE"}) - REMOVE "{TAG}" by hand in Admin')
            except Exception as e:
                R.add('cleanup: the test cafeteria is deleted', False, f'{type(e).__name__}: {str(e)[:120]} - REMOVE "{TAG}" by hand in Admin')
        if created:
            after = snapshot()
            R.add('nothing else changed: the student-visible cafeterias and menus are exactly as before', before is not None and after == before)
    return R.finish()


if __name__ == '__main__':
    sys.exit(main())
