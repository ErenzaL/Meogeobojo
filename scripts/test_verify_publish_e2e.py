"""Unit tests for scripts/verify_publish_e2e.py. They never touch a real project: HTTP, RPC and sleeping are
replaced by an in-memory fake.   python3 -m unittest scripts/test_verify_publish_e2e.py -v"""
import contextlib, importlib.util, io, pathlib, types, unittest

_spec = importlib.util.spec_from_file_location('e2e', pathlib.Path(__file__).with_name('verify_publish_e2e.py'))
e2e = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(e2e)

FLAG = '--yes-i-approve-production-write'


class ResultsTest(unittest.TestCase):
    def make(self):
        return e2e.Results(echo=False)

    def test_every_value_is_recorded_as_a_real_bool(self):
        # the original crash: `a and b and some_list` stored the list, then sum() raised TypeError
        r = self.make()
        for value in ([{'id': 'x'}], [], None, {}, {'a': 1}, 0, 1, 'text', '', True, False):
            r.add('check', value)
        self.assertTrue(all(type(ok) is bool for ok, _, _ in r.items))
        self.assertEqual([ok for ok, _, _ in r.items], [True, False, False, False, True, False, True, True, False, True, False])

    def test_add_returns_the_bool_so_callers_can_branch(self):
        r = self.make()
        self.assertIs(r.add('a', [1]), True)
        self.assertIs(r.add('b', []), False)

    def test_summary_counts_passed_failed_and_total(self):
        r = self.make()
        r.add('one', True); r.add('two', [1, 2]); r.add('three', False); r.add('four', None)
        self.assertEqual((r.passed, r.total, r.failed), (2, 4, ['three', 'four']))
        self.assertEqual(r.summary(), '2/4 checks passed. 2 FAILED: three; four')

    def test_summary_with_only_passes_has_no_failure_list(self):
        r = self.make()
        r.add('one', True); r.add('two', [0])
        self.assertEqual(r.summary(), '2/2 checks passed.')

    def test_exit_code(self):
        r = self.make()
        self.assertEqual(r.exit_code(), 1, 'nothing verified is not a success')
        r.add('a', True); r.add('b', 'yes')
        self.assertEqual(r.exit_code(), 0)
        r.add('c', False)
        self.assertEqual(r.exit_code(), 1, 'one failure fails the run')

    def test_finish_prints_the_summary_and_returns_the_code(self):
        r = e2e.Results(echo=False)
        r.add('a', True); r.add('b', False)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = r.finish()
        self.assertEqual(code, 1)
        self.assertIn('1/2 checks passed. 1 FAILED: b', out.getvalue())

    def test_echo_prints_pass_and_fail_lines(self):
        r = e2e.Results(echo=True)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            r.add('good', True, 'HTTP 200'); r.add('bad', False)
        self.assertIn('PASS good  [HTTP 200]', out.getvalue())
        self.assertIn('FAIL bad', out.getvalue())


class FakeBackend:
    """Just enough of Supabase for the script: one app_content row, drafts, publish, unpublish, schedule, pg_cron."""

    def __init__(self, **flags):
        self.flags, self.row, self.draft, self.scheduled, self.sleeps, self.calls = flags, None, None, None, 0, []

    def sleep(self, _seconds):
        self.sleeps += 1

    def _apply(self, data):
        self.row.update(title=data['title'], active=bool(data.get('active', True)))

    def http(self, method, path, body=None, token=None, extra=None):
        self.calls.append((method, path.split('?')[0], 'anon' if token is None else 'admin'))
        if path.startswith('/auth/v1/token'):
            return (400, {'error': 'invalid login'}) if self.flags.get('bad_login') else (200, {'access_token': 'TOKEN'})
        if method == 'POST' and path == '/rest/v1/app_content':
            if self.flags.get('insert_fails'):
                return 403, {'message': 'permission denied'}
            self.row = {'id': 'row-1', 'title': body['title'], 'active': False}
            return 201, [{'id': 'row-1'}]
        if method == 'GET' and path.startswith('/rest/v1/app_content?id=eq.'):
            if self.scheduled and self.row and self.sleeps >= 2:                    # pg_cron fires, once
                self._apply(self.scheduled)
                self.scheduled = None
            if token is None and self.flags.get('boom_on_public_read') and self.draft:
                raise RuntimeError('network went away')
            if self.row is None:
                return 200, []
            if token is None:                                                      # the app: live rows only
                return (200, [dict(self.row)]) if self.row['active'] else (200, [])
            return 200, [dict(self.row)]
        if method == 'DELETE':
            if self.flags.get('delete_fails'):
                return 500, {'message': 'boom'}
            self.row = None
            return 204, None
        raise AssertionError(f'unexpected call {method} {path}')

    def rpc(self, name, args, token):
        self.calls.append(('RPC', name, 'admin'))
        if name == 'cms_health':
            return 200, {'cron': {'available': True, 'job_found': True, 'active': True}, 'jobs': {'overdue': 0}}
        if name == 'cms_save_draft':
            self.draft = args['p_data']
            return 200, {'revision': 1}
        if name == 'cms_publish':
            if self.flags.get('publish_fails'):
                return 400, {'message': 'refused'}
            self._apply(self.draft)
            return 200, 1
        if name == 'cms_unpublish':
            self.row['active'] = False
            return 200, 2
        if name == 'cms_state':
            return 200, {'live': {'title': self.row['title'], 'body': 'x', 'image_url': None, 'link_url': None, 'kakao_place_id': None,
                                  'university_id': None, 'active': False, 'sort_order': 0, 'starts_at': None, 'ends_at': None}}
        if name == 'cms_schedule':
            self.scheduled = self.draft
            return 200, 7
        raise AssertionError(f'unexpected rpc {name}')


class MainFlowTest(unittest.TestCase):
    def run_main(self, argv, **flags):
        fake = FakeBackend(**flags)
        saved = {k: getattr(e2e, k) for k in ('E', 'URL', 'KEY', 'http', 'rpc', 'time')}
        e2e.E = {'ADMIN_EMAIL': 'a@example.org', 'ADMIN_PASSWORD': 'pw'}
        e2e.URL, e2e.KEY = 'https://example.supabase.co', 'publishable'
        e2e.http, e2e.rpc, e2e.time = fake.http, fake.rpc, types.SimpleNamespace(sleep=fake.sleep)
        out = io.StringIO()
        try:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
                code = e2e.main(argv)
        finally:
            for k, v in saved.items():
                setattr(e2e, k, v)
        return code, out.getvalue(), fake

    def test_happy_path_with_schedule(self):
        code, out, fake = self.run_main([FLAG, '--with-schedule'])
        self.assertEqual(code, 0, out)
        self.assertRegex(out, r'(\d+)/\1 checks passed\.')
        self.assertNotIn('FAIL', out)
        self.assertIsNone(fake.row, 'the throw-away row is deleted')

    def test_happy_path_without_schedule_skips_the_cron_wait(self):
        code, out, fake = self.run_main([FLAG])
        self.assertEqual(code, 0, out)
        self.assertEqual(fake.sleeps, 0)
        self.assertNotIn('pg_cron', out.split('scheduler:')[-1].split('checks passed')[0].replace('scheduler:', ''))
        self.assertIsNone(fake.row)

    def test_a_failed_first_step_is_a_failed_run_with_a_summary(self):
        # used to `return` from main(): no summary and exit status 0
        code, out, fake = self.run_main([FLAG], insert_fails=True)
        self.assertEqual(code, 1)
        self.assertIn('FAIL 1. staged (switched-off) row can be created', out)
        self.assertIn('checks passed', out)
        self.assertNotIn(('DELETE', '/rest/v1/app_content', 'admin'), fake.calls, 'nothing was created, nothing to clean up')

    def test_a_failed_publish_fails_the_run_but_cleanup_still_runs(self):
        code, out, fake = self.run_main([FLAG], publish_fails=True)
        self.assertEqual(code, 1)
        self.assertIn('FAIL 3. publish now (RPC)', out)
        self.assertIn('FAIL 3. the app now sees the published title', out)
        self.assertIsNone(fake.row, 'cleanup ran in the finally block')
        self.assertIn('PASS 6. cleanup', out)

    def test_a_crash_midway_is_reported_cleaned_up_and_nonzero(self):
        code, out, fake = self.run_main([FLAG], boom_on_public_read=True)
        self.assertEqual(code, 1)
        self.assertIn('FAIL unexpected error: RuntimeError', out)
        self.assertIn('checks passed', out)
        self.assertIn(('DELETE', '/rest/v1/app_content', 'admin'), fake.calls, 'cleanup was attempted after the crash')

    def test_a_failed_cleanup_is_a_failure_and_tells_you_what_to_remove(self):
        code, out, fake = self.run_main([FLAG], delete_fails=True)
        self.assertEqual(code, 1)
        self.assertIn('FAIL 6. cleanup: the staged row is deleted', out)

    def test_bad_login_stops_before_anything_is_written(self):
        code, out, fake = self.run_main([FLAG], bad_login=True)
        self.assertEqual(code, 1)
        self.assertIn('FAIL admin sign-in', out)
        self.assertIn('0/1 checks passed', out)
        self.assertEqual([c for c in fake.calls if c[0] in ('POST', 'DELETE') and 'auth' not in c[1]], [])

    def test_refuses_without_the_approval_flag_and_touches_nothing(self):
        code, out, fake = self.run_main([])
        self.assertEqual((code, fake.calls), (2, []))

    def test_every_recorded_check_is_a_bool_in_a_real_run(self):
        # run through Results directly: the crash was triggered by the real step-1 expression
        fake = FakeBackend()
        saved = {k: getattr(e2e, k) for k in ('E', 'URL', 'KEY', 'http', 'rpc', 'time', 'Results')}
        captured = []

        class Spy(e2e.Results):
            def __init__(self, echo=True):
                super().__init__(echo=False)
                captured.append(self)

        e2e.E, e2e.URL, e2e.KEY = {'ADMIN_EMAIL': 'a', 'ADMIN_PASSWORD': 'b'}, 'https://x', 'k'
        e2e.http, e2e.rpc, e2e.time, e2e.Results = fake.http, fake.rpc, types.SimpleNamespace(sleep=fake.sleep), Spy
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                e2e.main([FLAG, '--with-schedule'])
        finally:
            for k, v in saved.items():
                setattr(e2e, k, v)
        self.assertTrue(captured and captured[0].total >= 15)
        self.assertTrue(all(type(ok) is bool for ok, _, _ in captured[0].items))


if __name__ == '__main__':
    unittest.main()
