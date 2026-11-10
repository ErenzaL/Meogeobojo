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
Credentials are read from the environment only; nothing is stored.
Exit status: 0 = every check passed; 1 = a check failed or the run crashed (cleanup is still attempted);
2 = refused to start (missing approval flag or configuration). Unit tests: python3 -m unittest scripts/test_verify_publish_e2e.py
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


class Results:
    """Every check is one record (passed: bool, name, detail), whatever expression produced it.

    The previous version appended the raw expression, so `a and b and some_list` stored the LIST and
    the final sum() crashed. Values are coerced to a real bool here, in one place."""

    def __init__(self, echo=True):
        self.items = []
        self.echo = echo

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
        return [name for ok, name, _ in self.items if not ok]

    def summary(self):
        line = f'{self.passed}/{self.total} checks passed.'
        if self.failed:
            line += f' {len(self.failed)} FAILED: ' + '; '.join(self.failed)
        return line

    def exit_code(self):
        """0 only when at least one check ran and every check passed (nothing verified is not a success)."""
        return 0 if self.total > 0 and not self.failed else 1

    def finish(self):
        print('\n' + self.summary(), flush=True)
        return self.exit_code()


class _Abort(Exception):
    """A step the rest of the run depends on failed (already recorded): stop, clean up, report."""


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


def main(argv=None):
    """Runs the checks and returns the process exit code (0 = every check passed)."""
    argv = sys.argv[1:] if argv is None else argv
    if '--yes-i-approve-production-write' not in argv:
        print('Refusing to write to the project without --yes-i-approve-production-write (see the docstring).', file=sys.stderr)
        return 2
    if not URL or not KEY:
        print('Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (or admin/.env).', file=sys.stderr)
        return 2
    email, pw = E.get('ADMIN_EMAIL'), E.get('ADMIN_PASSWORD')
    if not email or not pw:
        print('Set ADMIN_EMAIL and ADMIN_PASSWORD (an admin account) in the environment.', file=sys.stderr)
        return 2
    R = Results()
    s, auth = http('POST', '/auth/v1/token?grant_type=password', {'email': email, 'password': pw})
    if not R.add('admin sign-in', s == 200 and isinstance(auth, dict) and 'access_token' in auth, f'HTTP {s}'):
        return R.finish()
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
        created = s in (200, 201) and isinstance(r, list) and len(r) > 0
        if created:
            row_id = r[0]['id']           # set before anything can fail, so cleanup always knows the row
        if not R.add('1. staged (switched-off) row can be created', created, f'HTTP {s} {r if s >= 300 else ""}'):
            raise _Abort()
        R.add('1. the app cannot see the staged row', public_row(row_id) is None)

        s, d = rpc('cms_save_draft', {'p_type': 'app_content', 'p_id': row_id,
                   'p_data': {'title': title1, 'body': 'publishing check', 'image_url': None, 'link_url': None, 'kakao_place_id': None,
                              'university_id': None, 'active': True, 'sort_order': 0, 'starts_at': None, 'ends_at': None},
                   'p_expected_revision': 0}, tok)
        R.add('2. save draft (RPC)', s == 200, f'HTTP {s} {d if s >= 300 else ""}')
        R.add('2. a saved draft is invisible to the app', public_row(row_id) is None)
        s, live = http('GET', f'/rest/v1/app_content?id=eq.{row_id}&select=title,active', None, tok)
        R.add('2. the live row is unchanged by the draft', s == 200 and isinstance(live, list) and len(live) == 1 and live[0]['title'] == title0 and live[0]['active'] is False)

        s, d = rpc('cms_publish', {'p_type': 'app_content', 'p_id': row_id, 'p_expected_revision': 1, 'p_reason': 'E2E 게시 점검'}, tok)
        R.add('3. publish now (RPC)', s == 200, f'HTTP {s} {d if s >= 300 else ""}')
        pub = public_row(row_id)
        R.add('3. the app now sees the published title (no rebuild, no code deploy)', pub is not None and pub.get('title') == title1, str(pub))

        s, d = rpc('cms_unpublish', {'p_type': 'app_content', 'p_id': row_id, 'p_reason': 'E2E 게시 점검 종료'}, tok)
        R.add('5. unpublish (RPC)', s == 200, f'HTTP {s} {d if s >= 300 else ""}')
        R.add('5. the app no longer sees it', public_row(row_id) is None)

        if '--with-schedule' in argv:
            s, st = rpc('cms_state', {'p_type': 'app_content', 'p_id': row_id}, tok)
            live2 = st['live'] if s == 200 and isinstance(st, dict) else {}
            s, d = rpc('cms_save_draft', {'p_type': 'app_content', 'p_id': row_id, 'p_data': {**live2, 'title': title1 + ' (예약)', 'active': True}, 'p_expected_revision': 0}, tok)
            R.add('4. save draft for the schedule', s == 200, f'HTTP {s}')
            run_at = (dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=2)).isoformat()
            s, job = rpc('cms_schedule', {'p_type': 'app_content', 'p_id': row_id, 'p_expected_revision': 1, 'p_run_at': run_at, 'p_unpublish_at': None, 'p_reason': 'E2E 예약 점검'}, tok)
            R.add('4. schedule (RPC)', s == 200, f'HTTP {s} {job if s >= 300 else ""}')
            R.add('4. invisible before the scheduled time', public_row(row_id) is None)
            print('     waiting for pg_cron (cms-run-due-jobs) - up to 4 minutes ...', flush=True)
            seen = None
            for _ in range(24):
                time.sleep(10)
                seen = public_row(row_id)
                if seen:
                    break
            R.add('4. the SERVER (pg_cron) published it on schedule, with no browser open', seen is not None, str(seen))
            rpc('cms_unpublish', {'p_type': 'app_content', 'p_id': row_id, 'p_reason': 'E2E 예약 점검 종료'}, tok)
            R.add('4. unpublished again', public_row(row_id) is None)
    except _Abort:
        pass                                   # the failing check is already recorded
    except Exception as e:                     # a crash is a failed run, not a pass and not a stack trace only
        R.add('unexpected error: ' + type(e).__name__, False, str(e)[:200])
    finally:
        if row_id:
            # make sure nothing stays visible, then remove the staged row (allowed only while switched off)
            try:
                rpc('cms_unpublish', {'p_type': 'app_content', 'p_id': row_id, 'p_reason': 'E2E cleanup'}, tok)
                s, _ = http('DELETE', f'/rest/v1/app_content?id=eq.{row_id}', None, tok)
                gs, left = http('GET', f'/rest/v1/app_content?id=eq.{row_id}&select=id', None, tok)
                R.add('6. cleanup: the staged row is deleted', s in (200, 204) and gs == 200 and left == [] and public_row(row_id) is None, f'HTTP {s}')
            except Exception as e:             # report it; never hide the original outcome
                R.add('6. cleanup: the staged row is deleted', False, f'cleanup raised {type(e).__name__}: {str(e)[:150]} - REMOVE the "[E2E]" announcement by hand')
    return R.finish()


if __name__ == '__main__':
    sys.exit(main())
