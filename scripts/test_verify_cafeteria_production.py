"""Unit tests for scripts/verify_cafeteria_production.py. No network: HTTP is replaced by an in-memory model of the parts of Supabase
the script uses (multi-week drafts, versions, atomic and per-day publish, rollback, the dish-aware CSV import, the scheduler, student
visibility = active cafeteria + published menus). The point: the script's own logic, its refusals and its cleanup on failure.
   python3 -m unittest scripts/test_verify_cafeteria_production.py -v"""
import contextlib, copy, datetime as dt, importlib.util, io, pathlib, unittest

_spec = importlib.util.spec_from_file_location('cafe_prod', pathlib.Path(__file__).with_name('verify_cafeteria_production.py'))
p = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(p)

FLAG = '--yes-i-approve-production-write'
URL = f'https://{p.PRODUCTION_REF}.supabase.co'
ENV = {'SUPABASE_URL': URL, 'SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_x', 'ADMIN_EMAIL': 'a@x.org', 'ADMIN_PASSWORD': 'pw'}
NOENVFILE = pathlib.Path('/nonexistent')


class ArgsTest(unittest.TestCase):
    def test_needs_the_flag_the_production_url_and_credentials(self):
        self.assertFalse(p.check_args([], ENV)[0])
        for k in ('SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY', 'ADMIN_EMAIL', 'ADMIN_PASSWORD'):
            self.assertFalse(p.check_args([FLAG], {x: v for x, v in ENV.items() if x != k})[0], k)
        self.assertEqual(p.check_args([FLAG], ENV), (True, ''))

    def test_refuses_any_other_project(self):
        ok, msg = p.check_args([FLAG], {**ENV, 'SUPABASE_URL': 'https://stagingref.supabase.co'})
        self.assertFalse(ok); self.assertIn('not the production project', msg)

    def test_refuses_a_service_role_key(self):
        import base64, json
        seg = lambda o: base64.urlsafe_b64encode(json.dumps(o).encode()).decode().rstrip('=')
        key = '.'.join([seg({'alg': 'HS256'}), seg({'role': 'service_role', 'ref': 'x' * 30, 'pad': 'y' * 40}), 'sig'])
        ok, msg = p.check_args([FLAG], {**ENV, 'SUPABASE_PUBLISHABLE_KEY': key})
        self.assertFalse(ok); self.assertIn('service-role', msg)

    def test_main_returns_2_without_touching_the_network(self):
        calls, saved = [], p.base.http
        p.base.http = lambda *a, **k: calls.append(a) or (500, None)
        p.http = p.base.http
        try:
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(p.main([], {**ENV}), 2)
                self.assertEqual(p.main([FLAG], {**ENV, 'SUPABASE_URL': 'https://other.supabase.co'}), 2)
        finally:
            p.base.http = saved; p.http = saved
        self.assertEqual(calls, [])


class WeekDataTest(unittest.TestCase):
    def test_a_structured_week_is_15_meals_with_dishes_in_table_order_and_one_label(self):
        w = p.structured_week(dt.date(2026, 11, 9))
        self.assertEqual(len(w), 15)
        self.assertEqual(len({(x['date'], x['meal_type']) for x in w}), 15)
        lunch = next(x for x in w if x['date'] == '2026-11-09' and x['meal_type'] == 'lunch')
        self.assertEqual([i['kind'] for i in lunch['menu_items']], ['main', 'side', 'side', 'soup', 'kimchi', 'salad', 'dessert'])
        self.assertEqual([i['name_ko'] for i in lunch['menu_items'] if i.get('shared')], ['김치', '샐러드', '후식차'])
        self.assertEqual([(x['date'], x['meal_type']) for x in w if x['extra'].get('labels')], [('2026-11-13', 'lunch')])
        self.assertTrue(all(x['extra']['labels_verified'] for x in w if x['extra'].get('labels')))
        self.assertTrue(all(x['extra']['origin'] and x['extra']['notice'] for x in w))


class FakeProd:
    def __init__(self, **flags):
        self.flags = flags
        self.unis = [{'id': 'u1', 'name_ko': '순천향대학교'}]
        self.cafs, self.weeks = {}, {}
        self.draft, self.live, self.versions = {}, {}, {}
        self.sched, self.sleeps, self.n, self.deleted = {}, 0, 0, []
        self.real_cafe = {'id': 'real-c', 'name_ko': '실제 식당', 'status': 'active', 'university_id': 'u1'}
        if flags.get('leftover'):
            self.cafs['old'] = {'id': 'old', 'name_ko': '[E2E] 주간 점검 000000', 'status': 'inactive', 'university_id': 'u1'}

    def uid(self, x):
        self.n += 1; return f'{x}{self.n}'

    def visible(self):
        out = []
        for c in [self.real_cafe, *self.cafs.values()]:
            if c['status'] != 'active':
                continue
            for e, (cid, ws) in self.weeks.items():
                if cid == c['id']:
                    out += [dict(id=f'{e}-{m["date"]}-{m["meal_type"]}', cafeteria_id=cid, meal_date=m['date'], meal_type=m['meal_type'], option_name=m['option_name'],
                                 price_krw=m['price_krw'], badge=m['badge'], menu_items=m['menu_items'], extra=m['extra'], status='published') for m in self.live.get(e, [])]
        return out

    def tick(self):
        for e, due in list(self.sched.items()):
            if self.sleeps >= due:
                self.publish(e); self.sched.pop(e)

    def publish(self, e):
        self.live[e] = copy.deepcopy(self.draft.pop(e)); self.versions.setdefault(e, []).append(copy.deepcopy(self.live[e]))

    def http(self, method, path, body=None, token=None, extra=None):
        if path.startswith('/auth/v1/token'):
            return (400, {}) if self.flags.get('bad_login') else (200, {'access_token': 'T'})
        if path.startswith('/rest/v1/universities'):
            return 200, copy.deepcopy(self.unis)
        if path.startswith('/rest/v1/campus_cafeterias?name_ko=like'):
            return 200, [{'id': c['id'], 'name_ko': c['name_ko']} for c in self.cafs.values() if '[E2E]' in c['name_ko']]
        if path.startswith('/rest/v1/campus_cafeterias?select=id'):
            return 200, [{'id': c['id']} for c in [self.real_cafe, *self.cafs.values()] if c['status'] == 'active']
        if path.startswith('/rest/v1/cafeteria_meals?select=id'):
            return 200, [{'id': m['id']} for m in self.visible()]
        if method == 'POST' and path == '/rest/v1/campus_cafeterias':
            if self.flags.get('create_fails'):
                return 403, {'message': 'denied'}
            c = {**body, 'id': self.uid('c')}; self.cafs[c['id']] = c
            return 201, [{'id': c['id']}]
        if method == 'PATCH' and '/campus_cafeterias?id=eq.' in path:
            self.cafs[path.split('eq.')[1]].update(body); return 204, None
        if method == 'DELETE' and '/campus_cafeterias?id=eq.' in path:
            if self.flags.get('delete_fails'):
                return 403, {'message': 'denied'}
            cid = path.split('eq.')[1]; self.cafs.pop(cid, None); self.deleted.append(cid)
            for e in [e for e, (c, _) in self.weeks.items() if c == cid]:
                self.weeks.pop(e); self.live.pop(e, None); self.draft.pop(e, None)
            return 204, None
        if method == 'GET' and path.startswith('/rest/v1/campus_cafeterias?id=eq.'):
            cid = path.split('eq.')[1].split('&')[0]; return 200, [{'id': cid}] if cid in self.cafs else []
        if path.startswith('/rest/v1/cafeteria_meals?cafeteria_id=eq.'):
            cid = path.split('eq.')[1].split('&')[0]; self.tick()
            rows = [m for m in self.visible() if m['cafeteria_id'] == cid]
            if 'meal_date=gte.' in path:
                rows = [m for m in rows if m['meal_date'] >= path.split('meal_date=gte.')[1].split('&')[0]]
            return 200, sorted(rows, key=lambda m: (m['meal_date'], m['meal_type']))
        raise AssertionError(f'unexpected {method} {path}')

    def rpc(self, name, a, token):
        if name == 'cafeteria_week_entity':
            ws = dt.date.fromisoformat(a['p_week']); ws = (ws - dt.timedelta(days=ws.weekday())).isoformat()
            for e, k in self.weeks.items():
                if k == (a['p_cafeteria'], ws):
                    return 200, e
            e = self.uid('w'); self.weeks[e] = (a['p_cafeteria'], ws); return 200, e
        if name == 'cms_save_draft':
            for m in a['p_data']['meals']:
                ex = m.get('extra') or {}
                if ex.get('labels') and ex.get('labels_verified') is not True:
                    return 400, {'message': 'HALAL needs confirmation'}
            self.draft[a['p_id']] = copy.deepcopy(a['p_data']['meals']); return 200, {'revision': 1}
        e = a.get('p_id')
        if name == 'cms_state':
            return 200, {'live': {'meals': self.live.get(e, [])}, 'live_version': len(self.versions.get(e, [])),
                         'draft': {'revision': 1, 'data': {'meals': self.draft[e]}} if e in self.draft else None}
        if name == 'cms_publish':
            if self.flags.get('publish_fails'):
                return 400, {'message': 'refused'}
            self.publish(e); return 200, len(self.versions[e])
        if name == 'cms_publish_week_days':
            days = set(a['p_days']); d = self.draft[e]
            kept = [m for m in self.live.get(e, []) if m['date'] not in days] + [m for m in d if m['date'] in days]
            self.live[e] = copy.deepcopy(kept); self.versions.setdefault(e, []).append(copy.deepcopy(kept))
            self.draft[e] = [m for m in d if m['date'] not in days] + [m for m in d if m['date'] in days]   # the rest stays a draft
            return 200, len(days)
        if name == 'cms_rollback':
            self.live[e] = copy.deepcopy(self.versions[e][a['p_version'] - 1]); self.versions[e].append(copy.deepcopy(self.live[e])); return 200, len(self.versions[e])
        if name == 'cms_unpublish':
            if e in self.live and self.live[e]:
                self.live[e] = []; self.versions.setdefault(e, []).append([])
            return 200, None
        if name == 'cms_schedule':
            self.sched[e] = self.sleeps + 2; return 200, {'id': 1}
        if name == 'cafeteria_import':
            return self.do_import(a)
        raise AssertionError(f'unexpected rpc {name}')

    def do_import(self, a):
        s = {'created': 0, 'updated': 0, 'unchanged': 0, 'failed': 0, 'skipped': 0, 'weeks_changed': 0}
        touched = set()
        for r in a['p_rows']:
            cid = next((c['id'] for c in self.cafs.values() if c['name_ko'] == r['cafeteria_name']), None)
            if cid is None:
                s['failed'] += 1; continue
            d = dt.date.fromisoformat(r['date']); ws = (d - dt.timedelta(days=d.weekday())).isoformat()
            e = next((e for e, k in self.weeks.items() if k == (cid, ws)), None) or self.rpc('cafeteria_week_entity', {'p_cafeteria': cid, 'p_week': ws}, None)[1]
            items = [{'name_ko': r['menu_name'], 'kind': 'main'}] + [{**x} for x in r['dishes']]
            meals = self.draft.get(e) or copy.deepcopy(self.live.get(e, []))
            new = {'date': r['date'], 'meal_type': r['meal_type'], 'option_name': '', 'option_order': 0, 'menu_items': items, 'price_krw': None, 'start_time': None, 'end_time': None,
                   'status': 'published', 'badge': None, 'source_url': None, 'verified_at': 'x', 'extra': {'origin': r.get('origin'), 'notice': r.get('notes')}}
            old = next((m for m in meals if m['date'] == r['date'] and m['meal_type'] == r['meal_type']), None)
            if old and old['menu_items'] == items:
                s['unchanged'] += 1; continue
            if not a['p_dry_run']:
                self.draft[e] = [m for m in meals if m is not old] + [new]
            s['updated' if old else 'created'] += 1; touched.add(e)
        s['weeks_changed'] = len(touched) if not a['p_dry_run'] else 0
        return 200, {'summary': s, 'dry_run': a['p_dry_run']}


def run(server, argv=None, env=None):
    saved = (p.base.http, p.base.rpc, p.http, p.rpc, p.base.sleep, p.student_meals)
    p.base.http = p.http = server.http
    p.base.rpc = p.rpc = server.rpc
    p.base.student_meals = None
    def _sleep(_s): server.sleeps += 1
    p.base.sleep = _sleep
    p.student_meals = lambda cid: (lambda s, rows: rows if s == 200 else None)(*server.http('GET', f'/rest/v1/cafeteria_meals?cafeteria_id=eq.{cid}&select=id', None))
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            code = p.main(argv if argv is not None else [FLAG], env or ENV)
    finally:
        p.base.http, p.base.rpc, p.http, p.rpc, p.base.sleep, p.student_meals = saved
    return code, out.getvalue()


class RunTest(unittest.TestCase):
    def setUp(self):
        self._read = p.read_env
        p.read_env = lambda env, root=None: dict(env)      # never read the real admin/.env in tests

    def tearDown(self):
        p.read_env = self._read

    def test_the_happy_path_passes_every_check_and_leaves_nothing_behind(self):
        srv = FakeProd()
        code, out = run(srv, [FLAG, '--with-schedule'])
        self.assertEqual(code, 0, out)
        self.assertNotIn('FAIL', out)
        self.assertIn('nothing else changed', out)
        self.assertEqual(len(srv.deleted), 1)
        self.assertEqual([c for c in srv.cafs.values() if '[E2E]' in c['name_ko']], [])
        self.assertIn('the SERVER published the scheduled week', out)

    def test_a_failed_publish_fails_the_run_but_still_cleans_up(self):
        srv = FakeProd(publish_fails=True)
        code, out = run(srv)
        self.assertEqual(code, 1, out)
        self.assertIn('FAIL Admin: 지금 게시', out)
        self.assertEqual(len(srv.deleted), 1)
        self.assertEqual([c for c in srv.cafs.values() if '[E2E]' in c['name_ko']], [])

    def test_a_cafeteria_that_cannot_be_deleted_is_archived_and_reported(self):
        srv = FakeProd(delete_fails=True)
        code, out = run(srv)
        self.assertEqual(code, 1, out)
        self.assertIn('REMOVE "[E2E] 주간 점검" by hand', out)
        self.assertTrue(all(c['status'] == 'archived' for c in srv.cafs.values()))

    def test_it_stops_before_writing_when_an_earlier_test_cafeteria_is_left(self):
        srv = FakeProd(leftover=True)
        code, out = run(srv)
        self.assertEqual(code, 1, out)
        self.assertEqual(list(srv.cafs), ['old'])      # nothing new was created
        self.assertEqual(srv.deleted, [])

    def test_a_bad_login_writes_nothing(self):
        srv = FakeProd(bad_login=True)
        code, out = run(srv)
        self.assertEqual(code, 1, out)
        self.assertEqual(srv.cafs, {})

    def test_a_create_failure_stops_without_leaving_anything(self):
        srv = FakeProd(create_fails=True)
        code, out = run(srv)
        self.assertEqual(code, 1, out)
        self.assertEqual(srv.cafs, {})

    def test_the_existing_real_cafeteria_is_never_touched(self):
        srv = FakeProd()
        before = copy.deepcopy(srv.real_cafe)
        code, out = run(srv, [FLAG, '--with-schedule'])
        self.assertEqual(code, 0, out)
        self.assertEqual(srv.real_cafe, before)


if __name__ == '__main__':
    unittest.main()
