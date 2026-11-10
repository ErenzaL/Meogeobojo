#!/usr/bin/env python3
"""End-to-end check that PUBLISHING reaches what the app reads - against a real Supabase project.

WRITES to the project (briefly), so it refuses to run without --yes-i-approve-production-write.
It uses ONE throw-away announcement ("[E2E] ...") and removes it again:

  1. create it switched OFF (a staged row)           -> the public (anon, i.e. the app) cannot see it
  2. save a draft that changes the title              -> the public still cannot see it, live is unchanged
  3. publish now                                      -> the public sees the DRAFT's title (no rebuild, no code deploy)
  4. (--with-schedule) schedule for ~2 minutes ahead  -> invisible until pg_cron runs cms_run_due_jobs(), then visible
  5. unpublish                                        -> the public cannot see it again
  6. delete the staged row                            -> nothing is left in app_content
Version history / audit rows stay (they are immutable by design).

The "public" reads use the publishable key and the same REST endpoint the Flutter app (mobile and web) uses
for app_content, so they show what a student's app shows after a refresh.

Needs: SUPABASE_URL + SUPABASE_PUBLISHABLE_KEY (or admin/.env VITE_*), and an ADMIN account:
  ADMIN_EMAIL=... ADMIN_PASSWORD=... python3 scripts/verify_publish_e2e.py --yes-i-approve-production-write [--with-schedule]
Credentials are read from the environment only; nothing is stored. Exit status 0 = every step passed.
"""
import datetime as dt, json, os, pathlib, re, sys, time, urllib.error, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent


def env():
    d = dict(os.environ)
    p = ROOT / 'admin' / '.env'
    if p.exists():
        for line in p.read_text().splitlines():
            m = re.match(r'\s*([A-Z_]+)\s*=\s*(.*)', line)
            if m:
                d.setdefault(m.group(1), m.group(2).strip().strip('"\''))
    return d


E = env()
URL = (E.get('SUPABASE_URL') or E.get('VITE_SUPABASE_URL') or '').rstrip('/')
KEY = E.get('SUPABASE_PUBLISHABLE_KEY') or E.get('VITE_SUPABASE_ANON_KEY') or ''
results = []


def step(name, ok, detail=''):
    results.append(ok)
    print(('PASS ' if ok else 'FAIL ') + name + (f'  [{detail}]' if detail else ''), flush=True)
    return ok


def http(method, path, body=None, token=None, extra=None):
    h = {'apikey': KEY, 'Authorization': 'Bearer ' + (token or KEY), 'Content-Type': 'application/json'}
    h.update(extra or {})
    req = urllib.request.Request(URL + path, data=None if body is None else json.dumps(body).encode(), headers=h, method=method)
    try:
        r = urllib.request.urlopen(req, timeout=30)
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


def public_row(row_id):
    """What the app (anon) can read for this row right now."""
    s, rows = http('GET', f'/rest/v1/app_content?id=eq.{row_id}&select=id,title,active')
    return rows[0] if s == 200 and rows else None


def main():
    if '--yes-i-approve-production-write' not in sys.argv:
        sys.exit('Refusing to write to the project without --yes-i-approve-production-write (see the docstring).')
    if not URL or not KEY:
        sys.exit('Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (or admin/.env).')
    email, pw = E.get('ADMIN_EMAIL'), E.get('ADMIN_PASSWORD')
    if not email or not pw:
        sys.exit('Set ADMIN_EMAIL and ADMIN_PASSWORD (an admin account) in the environment.')
    s, auth = http('POST', '/auth/v1/token?grant_type=password', {'email': email, 'password': pw})
    if not step('admin sign-in', s == 200 and isinstance(auth, dict) and 'access_token' in auth, f'HTTP {s}'):
        sys.exit(1)
    tok = auth['access_token']
    stamp = dt.datetime.now().strftime('%H%M%S')
    title0, title1 = f'[E2E] 게시 점검 {stamp}', f'[E2E] 게시 점검 {stamp} (수정됨)'
    row_id = None
    try:
        s, h = rpc('cms_health', {}, tok)
        if s == 200:
            print(f'     scheduler: cron available={h["cron"]["available"]} job_found={h["cron"]["job_found"]} active={h["cron"].get("active")} | overdue jobs={h["jobs"]["overdue"]}')
        else:
            print('     (cms_health not available yet: migration 20261116000100)')

        s, r = http('POST', '/rest/v1/app_content', {'kind': 'announcement', 'title': title0, 'body': 'publishing check', 'active': False},
                    tok, {'Prefer': 'return=representation'})
        if not step('1. staged (switched-off) row can be created', s in (200, 201) and isinstance(r, list) and r, f'HTTP {s} {r if s >= 300 else ""}'):
            return
        row_id = r[0]['id']
        step('1. the app cannot see the staged row', public_row(row_id) is None)

        s, d = rpc('cms_save_draft', {'p_type': 'app_content', 'p_id': row_id,
                   'p_data': {'title': title1, 'body': 'publishing check', 'image_url': None, 'link_url': None, 'kakao_place_id': None,
                              'university_id': None, 'active': True, 'sort_order': 0, 'starts_at': None, 'ends_at': None},
                   'p_expected_revision': 0}, tok)
        step('2. save draft (RPC)', s == 200, f'HTTP {s} {d if s >= 300 else ""}')
        step('2. a saved draft is invisible to the app', public_row(row_id) is None)
        s, live = http('GET', f'/rest/v1/app_content?id=eq.{row_id}&select=title,active', None, tok)
        step('2. the live row is unchanged by the draft', s == 200 and live and live[0]['title'] == title0 and live[0]['active'] is False)

        s, d = rpc('cms_publish', {'p_type': 'app_content', 'p_id': row_id, 'p_expected_revision': 1, 'p_reason': 'E2E 게시 점검'}, tok)
        step('3. publish now (RPC)', s == 200, f'HTTP {s} {d if s >= 300 else ""}')
        pub = public_row(row_id)
        step('3. the app now sees the published title (no rebuild, no code deploy)', bool(pub) and pub['title'] == title1, str(pub))

        s, d = rpc('cms_unpublish', {'p_type': 'app_content', 'p_id': row_id, 'p_reason': 'E2E 게시 점검 종료'}, tok)
        step('5. unpublish (RPC)', s == 200, f'HTTP {s} {d if s >= 300 else ""}')
        step('5. the app no longer sees it', public_row(row_id) is None)

        if '--with-schedule' in sys.argv:
            s, st = rpc('cms_state', {'p_type': 'app_content', 'p_id': row_id}, tok)
            live2 = st['live'] if s == 200 else {}
            s, d = rpc('cms_save_draft', {'p_type': 'app_content', 'p_id': row_id, 'p_data': {**live2, 'title': title1 + ' (예약)', 'active': True}, 'p_expected_revision': 0}, tok)
            step('4. save draft for the schedule', s == 200, f'HTTP {s}')
            run_at = (dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=2)).isoformat()
            s, job = rpc('cms_schedule', {'p_type': 'app_content', 'p_id': row_id, 'p_expected_revision': 1, 'p_run_at': run_at, 'p_unpublish_at': None, 'p_reason': 'E2E 예약 점검'}, tok)
            step('4. schedule (RPC)', s == 200, f'HTTP {s} {job if s >= 300 else ""}')
            step('4. invisible before the scheduled time', public_row(row_id) is None)
            print('     waiting for pg_cron (cms-run-due-jobs) - up to 4 minutes ...', flush=True)
            seen = None
            for _ in range(24):
                time.sleep(10)
                seen = public_row(row_id)
                if seen:
                    break
            step('4. the SERVER (pg_cron) published it on schedule, with no browser open', bool(seen), str(seen))
            rpc('cms_unpublish', {'p_type': 'app_content', 'p_id': row_id, 'p_reason': 'E2E 예약 점검 종료'}, tok)
            step('4. unpublished again', public_row(row_id) is None)
    finally:
        if row_id:
            # make sure nothing stays visible, then remove the staged row (allowed only while switched off)
            rpc('cms_unpublish', {'p_type': 'app_content', 'p_id': row_id, 'p_reason': 'E2E cleanup'}, tok)
            s, _ = http('DELETE', f'/rest/v1/app_content?id=eq.{row_id}', None, tok)
            step('6. cleanup: the staged row is deleted', s in (200, 204) and public_row(row_id) is None, f'HTTP {s}')
    print(f'\n{sum(results)}/{len(results)} checks passed.')
    sys.exit(0 if all(results) else 1)


main()
