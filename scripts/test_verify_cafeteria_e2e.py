"""Unit tests for scripts/verify_cafeteria_e2e.py. No network: HTTP is replaced by an in-memory model of the server
(drafts, atomic publish, versions, student visibility = active cafeterias + published menus, a simple CSV import).
   python3 -m unittest scripts/test_verify_cafeteria_e2e.py -v"""
import contextlib, copy, importlib.util, io, pathlib, re, unittest

_spec = importlib.util.spec_from_file_location('cafe_e2e', pathlib.Path(__file__).with_name('verify_cafeteria_e2e.py'))
m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(m)

FLAG = '--yes-write-to-staging'
ENV = {'STAGING_SUPABASE_URL': 'https://stagingref.supabase.co', 'STAGING_SUPABASE_PUBLISHABLE_KEY': 'k', 'STAGING_ADMIN_EMAIL': 'a@x.org', 'STAGING_ADMIN_PASSWORD': 'pw'}


class ArgsTest(unittest.TestCase):
    def test_needs_the_flag_and_all_staging_variables(self):
        self.assertFalse(m.check_args([], ENV)[0])
        for k in ENV:
            self.assertFalse(m.check_args([FLAG], {x: v for x, v in ENV.items() if x != k})[0], k)
        self.assertEqual(m.check_args([FLAG], ENV), (True, ''))

    def test_refuses_the_production_project_and_non_https(self):
        prod = {**ENV, 'STAGING_SUPABASE_URL': f'https://{m.PRODUCTION_REF}.supabase.co'}
        ok, msg = m.check_args([FLAG], prod)
        self.assertFalse(ok); self.assertIn('PRODUCTION', msg)
        self.assertTrue(m.check_args([FLAG, '--i-understand-this-is-production'], prod)[0])
        self.assertFalse(m.check_args([FLAG], {**ENV, 'STAGING_SUPABASE_URL': 'http://x'})[0])

    def test_ignores_the_ordinary_supabase_variables(self):
        # the script must never fall back to SUPABASE_URL / admin/.env (which point at production)
        self.assertFalse(m.check_args([FLAG], {'SUPABASE_URL': 'https://x.supabase.co', 'SUPABASE_PUBLISHABLE_KEY': 'k', 'ADMIN_EMAIL': 'a', 'ADMIN_PASSWORD': 'b'})[0])

    def test_main_returns_2_without_touching_the_network(self):
        calls = []
        saved = m.http
        m.http = lambda *a, **k: calls.append(a) or (500, None)
        try:
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(m.main([], ENV), 2)
                self.assertEqual(m.main([FLAG], {**ENV, 'STAGING_SUPABASE_URL': f'https://{m.PRODUCTION_REF}.supabase.co'}), 2)
        finally:
            m.http = saved
        self.assertEqual(calls, [])


class WeekDataTest(unittest.TestCase):
    def test_a_week_is_15_slots_plus_one_option_with_the_programme_on_one_date(self):
        import datetime as dt
        w = m.week_meals(dt.date(2026, 11, 9))
        self.assertEqual(len(w), 16)
        self.assertEqual(len({(x['date'], x['meal_type']) for x in w}), 15)
        self.assertEqual([x['date'] for x in w if x['badge']], ['2026-11-09'])
        self.assertTrue(all(x['source_url'] for x in w if x['badge']))
        self.assertEqual(sorted({x['date'] for x in w}), ['2026-11-09', '2026-11-10', '2026-11-11', '2026-11-12', '2026-11-13'])
        self.assertEqual([x['option_name'] for x in w if x['date'] == '2026-11-10' and x['meal_type'] == 'lunch'], ['', 'B코너'])

    def test_next_monday_is_always_a_future_monday(self):
        import datetime as dt
        for d in (dt.date(2026, 11, 9), dt.date(2026, 11, 10), dt.date(2026, 11, 15)):
            n = m.next_monday(d)
            self.assertEqual(n.weekday(), 0); self.assertGreater(n, d)


class FakeServer:
    """A faithful-enough model of the parts of Supabase the script exercises."""

    def __init__(self, **flags):
        self.flags = flags
        self.unis = [{'id': 'u1', 'name_ko': '가대학교'}, {'id': 'u2', 'name_ko': '나대학교'}]
        self.cafs, self.weeks, self.drafts, self.versions, self.meals = {}, {}, {}, {}, {}   # meals: cafeteria_id -> list
        self.n = 0
        self.import_drafts_seen = set()
        self.deleted, self.scheduled, self.sleeps = [], {}, 0

    def uid(self, p):
        self.n += 1
        return f'{p}{self.n}'

    def student_cafs(self, uni):
        return [c for c in self.cafs.values() if c['university_id'] == uni and c['status'] == 'active']

    def http(self, method, path, body=None, token=None, extra=None):
        if path.startswith('/auth/v1/token'):
            return (400, {'error': 'bad'}) if self.flags.get('bad_login') else (200, {'access_token': 'T'})
        if path.startswith('/rest/v1/universities'):
            return 200, copy.deepcopy(self.unis)
        if method == 'POST' and path == '/rest/v1/campus_cafeterias':
            if self.flags.get('create_fails'):
                return 403, {'message': 'denied'}
            c = {**body, 'id': self.uid('c')}
            self.cafs[c['id']] = c
            return 201, [{'id': c['id']}]
        if method == 'PATCH' and path.startswith('/rest/v1/campus_cafeterias?id=eq.'):
            self.cafs[path.split('eq.')[1]].update(body)
            return 204, None
        if method == 'DELETE' and path.startswith('/rest/v1/campus_cafeterias?id=eq.'):
            if self.flags.get('delete_fails'):
                return 403, {'message': 'denied'}
            cid = path.split('eq.')[1]
            self.cafs.pop(cid, None); self.meals.pop(cid, None); self.deleted.append(cid)
            return 204, None
        if path.startswith('/rest/v1/campus_cafeterias?id=eq.') and method == 'GET':
            cid = path.split('eq.')[1].split('&')[0]
            return 200, [{'id': cid}] if cid in self.cafs else []
        if path.startswith('/rest/v1/campus_cafeterias?university_id=eq.'):
            return 200, [{'id': c['id'], 'name_ko': c['name_ko'], 'status': 'active'} for c in self.student_cafs(path.split('eq.')[1].split('&')[0])]
        if path.startswith('/rest/v1/cafeteria_meals?cafeteria_id=eq.'):
            cid = path.split('eq.')[1].split('&')[0]
            if cid not in self.cafs or self.cafs[cid]['status'] != 'active':
                return 200, []
            self.sleep_tick(cid)
            return 200, [dict(meal_date=x['date'], meal_type=x['meal_type'], option_name=x['option_name'], price_krw=x['price_krw'], badge=x['badge'], menu_items=x['menu_items'], status='published')
                         for x in self.meals.get(cid, [])]
        raise AssertionError(f'unexpected {method} {path}')

    def sleep_tick(self, cid):
        if self.scheduled.get(cid) and self.sleeps >= 2:                # pg_cron fires once
            self.meals[cid] = copy.deepcopy(self.drafts.pop(self.weeks_of(cid))); self.scheduled.pop(cid)

    def weeks_of(self, cid):
        return next(e for e, c in self.weeks.items() if c == cid)

    def rpc(self, name, args, token):
        if name == 'cafeteria_week_entity':
            key = (args['p_cafeteria'], args['p_week'])
            for e, c in self.weeks.items():
                if c == args['p_cafeteria']:
                    return 200, e
            e = self.uid('w'); self.weeks[e] = args['p_cafeteria']
            return 200, e
        if name == 'cms_save_draft':
            for mm in args['p_data']['meals']:
                if mm.get('badge') == '천원의 아침밥' and not mm.get('source_url'):
                    return 400, {'message': '천원의 아침밥은 공식 출처 주소가 있어야 해요'}
            self.drafts[args['p_id']] = copy.deepcopy(args['p_data']['meals'])
            return 200, {'revision': 1}
        cid = self.weeks.get(args.get('p_id'))
        if name == 'cms_publish':
            if self.flags.get('publish_fails'):
                return 400, {'message': 'refused'}
            self.meals[cid] = copy.deepcopy(self.drafts.pop(args['p_id']))
            self.versions.setdefault(args['p_id'], []).append(copy.deepcopy(self.meals[cid]))
            return 200, len(self.versions[args['p_id']])
        if name == 'cms_publish_week_days':
            cid = self.weeks[args['p_id']]
            keep = [x for x in self.meals.get(cid, []) if x['date'] not in args['p_days']]
            new = [x for x in self.drafts[args['p_id']] if x['date'] in args['p_days']]
            self.meals[cid] = keep + new
            self.versions.setdefault(args['p_id'], []).append(copy.deepcopy(self.meals[cid]))
            return 200, 2
        if name == 'cms_schedule':
            self.scheduled[cid] = True
            return 200, 5
        if name == 'cms_unpublish':
            self.meals[cid] = []
            return 200, 9
        if name == 'cms_state':
            return 200, {'live': {'meals': self.meals.get(cid, [])}}
        if name == 'cms_rollback':
            self.meals[cid] = copy.deepcopy(self.versions[args['p_id']][args['p_version'] - 1])
            return 200, 10
        if name == 'cafeteria_import':
            return self.do_import(args)
        raise AssertionError(f'unexpected rpc {name}')

    def do_import(self, a):
        rows, unis = a['p_rows'], {r['university'] for r in a['p_rows']}
        created = unchanged = failed = 0
        keys = set()
        for r in rows:
            if not re.match(r'^\d{4}-\d{2}-\d{2}$', r['date']) or r['date'].endswith('-30') and r['date'][5:7] == '02':
                failed += 1; continue
            k = (r['university'], r['cafeteria_name'], r['date'], r['meal_type'])
            if k in self.import_drafts_seen:
                unchanged += 1
            else:
                created += 1
                if not a['p_dry_run']:
                    keys.add(k)
        multi = len(unis) > 1
        if not a['p_dry_run']:
            if multi and not a['p_allow_multi_university']:
                return 400, {'message': '여러 대학교'}
            self.import_drafts_seen |= keys
        return 200, {'multi_university': multi, 'summary': {'created': created, 'unchanged': unchanged, 'failed': failed, 'weeks_changed': created if not a['p_dry_run'] else 0, 'skipped': 0, 'updated': 0}}


class FlowTest(unittest.TestCase):
    def run_main(self, argv, **flags):
        srv = FakeServer(**flags)
        saved = (m.http, m.rpc, m.sleep)
        m.http, m.rpc, m.sleep = srv.http, srv.rpc, lambda s: setattr(srv, 'sleeps', srv.sleeps + 1)
        out = io.StringIO()
        try:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
                code = m.main(argv, ENV)
        finally:
            m.http, m.rpc, m.sleep = saved
        return code, out.getvalue(), srv

    def test_the_whole_flow_passes_and_cleans_up(self):
        code, out, srv = self.run_main([FLAG, '--with-schedule'])
        self.assertEqual(code, 0, out)
        self.assertNotIn('FAIL', out)
        self.assertRegex(out, r'(\d+)/\1 checks passed\.')
        self.assertEqual(srv.cafs, {}, 'the test cafeterias are removed')
        self.assertEqual(len(srv.deleted), 2)

    def test_it_really_checks_the_things_that_matter(self):
        _, out, _ = self.run_main([FLAG, '--with-schedule'])
        for needle in ('a draft week is invisible to students', 'students see all 16 menus', 'five weekdays x three meals', 'two lunch options on Tuesday',
                       '천원의 아침밥 on exactly one date', 'university separation', 'publish only Tuesday', 'Tuesday changed, Thursday did not',
                       'CSV preview (dry run)', 'importing two universities without confirmation is refused', 'the same CSV again changes nothing', 'the SERVER published the scheduled week',
                       'students see NOTHING again', 'the first published week is back'):
            self.assertIn('PASS ' + needle, out, needle)

    def test_it_detects_a_leak_between_universities(self):
        # a server that shows cafeteria B's menus under A would be caught by the separation check
        srv = FakeServer()
        orig = srv.http
        def leaky(method, path, body=None, token=None, extra=None):
            s, rows = orig(method, path, body, token, extra)
            if path.startswith('/rest/v1/cafeteria_meals?cafeteria_id=eq.') and rows == [] and 'c2' in path:
                return 200, [{'meal_date': 'x', 'meal_type': 'lunch', 'option_name': '', 'price_krw': 1, 'badge': None, 'menu_items': [], 'status': 'published'}]
            return s, rows
        saved = (m.http, m.rpc, m.sleep)
        m.http, m.rpc, m.sleep = leaky, srv.rpc, lambda s: None
        out = io.StringIO()
        try:
            with contextlib.redirect_stdout(out):
                code = m.main([FLAG], ENV)
        finally:
            m.http, m.rpc, m.sleep = saved
        self.assertEqual(code, 1)
        self.assertIn('FAIL university separation', out.getvalue())

    def test_a_failing_publish_fails_the_run_and_still_cleans_up(self):
        code, out, srv = self.run_main([FLAG], publish_fails=True)
        self.assertEqual(code, 1)
        self.assertIn('FAIL publish the whole week', out)
        self.assertEqual(srv.cafs, {})

    def test_a_failed_cleanup_is_reported_with_what_to_remove(self):
        code, out, srv = self.run_main([FLAG], delete_fails=True)
        self.assertEqual(code, 1 if 'FAIL' in out else 0)
        self.assertIn('archived', out)
        self.assertTrue(all(c['status'] == 'archived' for c in srv.cafs.values()), 'a cafeteria that cannot be deleted is at least archived (hidden from students)')

    def test_stops_early_when_the_cafeteria_cannot_be_created(self):
        code, out, srv = self.run_main([FLAG], create_fails=True)
        self.assertEqual(code, 1)
        self.assertIn('FAIL create a cafeteria', out)

    def test_bad_login_writes_nothing(self):
        code, out, srv = self.run_main([FLAG], bad_login=True)
        self.assertEqual((code, srv.cafs), (1, {}))
        self.assertIn('0/1 checks passed', out)

    def test_a_crash_is_a_failed_run_and_cleans_up(self):
        srv = FakeServer()
        orig = srv.rpc
        def boom(name, args, token):
            if name == 'cms_publish':
                raise RuntimeError('network went away')
            return orig(name, args, token)
        saved = (m.http, m.rpc, m.sleep)
        m.http, m.rpc, m.sleep = srv.http, boom, lambda s: None
        out = io.StringIO()
        try:
            with contextlib.redirect_stdout(out):
                code = m.main([FLAG], ENV)
        finally:
            m.http, m.rpc, m.sleep = saved
        self.assertEqual(code, 1)
        self.assertIn('FAIL unexpected error: RuntimeError', out.getvalue())
        self.assertEqual(srv.cafs, {})


class ResultsTest(unittest.TestCase):
    def test_values_become_bools_and_zero_checks_is_not_success(self):
        r = m.Results(echo=False)
        self.assertEqual(r.exit_code(), 1)
        r.add('a', [1]); r.add('b', []); r.add('c', 'x')
        self.assertEqual((r.passed, r.total, r.failed), (2, 3, ['b']))
        self.assertTrue(all(type(ok) is bool for ok, _, _ in r.items))
        self.assertEqual(r.exit_code(), 1)


if __name__ == '__main__':
    unittest.main()
