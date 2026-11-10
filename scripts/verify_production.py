#!/usr/bin/env python3
"""Read-only check of a Supabase project against what the app and the admin need.

Uses ONLY the publishable (anon) key, so it can run anywhere and changes
nothing. It proves what is DEPLOYED (tables, columns, functions, bucket, edge
function, hosting); it cannot prove admin-to-app synchronisation, which needs
signed-in accounts (see docs/production-acceptance.md).

Config (env vars, names only): SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, or
admin/.env's VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY. Optional:
FLUTTER_WEB_URL, ADMIN_URL.
Exit status: 0 = all checks passed, 1 = something is missing.
"""
import json, os, pathlib, re, sys, urllib.error, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
U0 = '00000000-0000-4000-8000-000000000000'


def load_env():
    d = dict(os.environ)
    p = ROOT / 'admin' / '.env'
    if p.exists():
        for line in p.read_text().splitlines():
            m = re.match(r'\s*([A-Z_]+)\s*=\s*(.*)', line)
            if m:
                d.setdefault(m.group(1), m.group(2).strip().strip('"\''))
    return d


ENV = load_env()
URL = (ENV.get('SUPABASE_URL') or ENV.get('VITE_SUPABASE_URL') or '').rstrip('/')
KEY = ENV.get('SUPABASE_PUBLISHABLE_KEY') or ENV.get('VITE_SUPABASE_ANON_KEY') or ''
if not URL or not KEY:
    sys.exit('Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (or admin/.env).')
HEAD = {'apikey': KEY, 'Authorization': 'Bearer ' + KEY, 'Content-Type': 'application/json'}
results = []


def check(name, ok, detail=''):
    results.append((ok, name, detail))
    print(('PASS ' if ok else 'FAIL ') + name + (f'  [{detail}]' if detail else ''))


def call(path, body=None, method=None, headers=None, timeout=20):
    req = urllib.request.Request(URL + path, data=None if body is None else json.dumps(body).encode(),
                                 headers=headers or HEAD, method=method or ('POST' if body is not None else 'GET'))
    try:
        r = urllib.request.urlopen(req, timeout=timeout)
        return r.status, r.read().decode('utf8', 'ignore'), r.headers
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf8', 'ignore'), e.headers
    except Exception as e:  # network
        return 0, f'{type(e).__name__}: {e}', {}


print(f'Project: {URL}\n')

# --- public tables must be readable (RLS shows only published rows); private ones must refuse anon
PUBLIC = ['universities', 'restaurant_overrides', 'restaurant_menus', 'restaurant_photos', 'campus_cafeterias',
          'cafeteria_meals', 'app_content', 'student_reviews']
PRIVATE = ['admin_roles', 'audit_log', 'reports', 'user_contributions', 'monthly_campaigns', 'missions',
           'user_mission_progress', 'point_transactions', 'user_badges', 'activity_events']
for t in PUBLIC:
    s, b, _ = call(f'/rest/v1/{t}?select=*&limit=1')
    check(f'table {t} exists and is publicly readable (published rows only)', s == 200, f'HTTP {s}')
for t in PRIVATE:
    s, b, _ = call(f'/rest/v1/{t}?select=*&limit=1')
    check(f'table {t} exists and REFUSES anonymous reads', s in (401, 403) and '42501' in b, f'HTTP {s}')

# --- columns added by 20261111000100
for t, c in [('restaurant_overrides', 'kakao_registered_at'), ('restaurant_overrides', 'featured'),
             ('restaurant_menus', 'status'), ('restaurant_menus', 'recommended'), ('restaurant_menus', 'price_verified_on'),
             ('cafeteria_meals', 'extra'), ('cafeteria_meals', 'badge')]:
    s, _, _ = call(f'/rest/v1/{t}?select={c}&limit=1')
    check(f'column {t}.{c}', s == 200, f'HTTP {s}')
s, b, _ = call('/rest/v1/restaurant_overrides?select=kakao_source&limit=1')
check('no raw Kakao document column (identity-only storage)', s != 200, f'HTTP {s}')

# --- functions: a function that exists answers "permission denied" (42501) to anon; a missing one PGRST202.
FUNCS = {
    'sync_my_missions': {}, 'log_activity': {'p_event': 'x', 'p_ref': ''},
    'save_user_preferences': None,  # name differs per migration; skipped
    'admin_save_mission': {'p': {}}, 'admin_save_campaign': {'p': {}},
    'admin_set_campaign_publish': {'p_id': U0, 'p_state': 'draft', 'p_reason': 'x'},
    'admin_set_mission_status': {'p_id': U0, 'p_status': 'draft', 'p_reason': 'x'},
    'admin_duplicate_mission': {'p_id': U0}, 'admin_mission_stats': {},
    'admin_review_contribution': {'p_id': U0, 'p_status': 'approved', 'p_note': ''},
    'submit_contribution': {'p_kind': 'menu_photo', 'p_place': '1', 'p_payload': {}},
    'admin_revoke_reward': {'p_tx': 1, 'p_reason': 'x'},
    'admin_moderate_review': {'p_review': U0, 'p_status': 'hidden', 'p_reason': 'x'},
    'admin_resolve_report': {'p_report': U0, 'p_status': 'resolved', 'p_notes': 'x'},
    'admin_set_account_status': {'p_user': U0, 'p_status': 'active', 'p_reason': 'x'},
    'admin_register_kakao_places': {'p_university': U0, 'p_places': []},
}
for f, args in FUNCS.items():
    if args is None:
        continue
    s, b, _ = call(f'/rest/v1/rpc/{f}', args)
    check(f'function {f} deployed and not callable anonymously', s in (401, 403) and '42501' in b, f'HTTP {s}')

# --- migrations that may still be waiting for approval: reported as PENDING, not as failures
def pending(name, applied):
    print(('OK   ' if applied else 'PENDING ') + name)

s_, b_, _ = call('/rest/v1/campus_cafeterias?select=status,operating_note&limit=1')
pending('20261113000100 cafeteria management (campus_cafeterias.status, operating_note)', s_ == 200)
s_, b_, _ = call('/rest/v1/rpc/delete_my_contribution', {'p_id': U0})
pending('20261114000100 student contributions (delete_my_contribution)', s_ in (401, 403) and '42501' in b_)
# (the private bucket cannot be told apart from a missing one with the anon key: check it in the Supabase dashboard)
s_, b_, _ = call('/rest/v1/rpc/cms_state', {'p_type': 'restaurant', 'p_id': U0})
pending('20261115000100 publishing: functions (cms_state, ...)', s_ in (401, 403) and '42501' in b_)
for t_ in ('content_drafts', 'content_versions', 'publication_jobs'):
    s_, b_, _ = call(f'/rest/v1/{t_}?select=*&limit=1')
    pending(f'20261115000100 publishing: table {t_} exists and refuses anonymous reads', s_ in (401, 403) and '42501' in b_)
# the FINAL 20261115000100 (all content types) versus an earlier edition that only knew restaurants / meals
for fn_, body_, what_ in (('_campaign_save', {'p': {}}, 'campaigns + app content + universities + missions'),
                          ('_mission_save', {'p': {}}, 'missions'),
                          ('cms_overview', {'p_type': 'restaurant', 'p_parent': None}, 'cms_overview(p_type, p_parent)')):
    s_, b_, _ = call(f'/rest/v1/rpc/{fn_}', body_)
    pending(f'20261115000100 publishing: final edition ({what_})', s_ in (401, 403) and '42501' in b_)
s_, b_, _ = call('/rest/v1/rpc/cms_health', {})
pending('20261116000100 publishing health (cms_health) for the /settings page', s_ in (401, 403) and '42501' in b_)
s_, b_, _ = call('/rest/v1/content_sync?select=id,source&limit=1')
pending('20261117000100 live-update signal (content_sync: take-downs reach running apps at once)', s_ == 200)
print('  (pg_cron must also be enabled for scheduled publishing: check Dashboard -> Database -> Extensions and cron.job)')
print()

# --- the Kakao edge function, with a real campus
s, b, _ = call('/rest/v1/universities?select=name_ko,latitude,longitude&is_active=eq.true&limit=1')
campus = json.loads(b)[0] if s == 200 and b.startswith('[{') else None
if campus:
    s, b, h = call('/functions/v1/search_restaurants', {'query': '한식', 'latitude': campus['latitude'], 'longitude': campus['longitude']}, timeout=40)
    ok = s == 200 and '"restaurants"' in b
    n = len(json.loads(b).get('restaurants', [])) if ok else 0
    check(f"edge function search_restaurants returns places near {campus['name_ko']}", ok and n > 0, f'HTTP {s}, {n} places')
    s, _, h = call('/functions/v1/search_restaurants', None, method='OPTIONS',
                   headers={'Origin': 'https://example.org', 'Access-Control-Request-Method': 'POST',
                            'Access-Control-Request-Headers': 'authorization,apikey,content-type'})
    check('edge function allows browser (CORS) calls', s in (200, 204) and bool(h.get('Access-Control-Allow-Origin')), f'HTTP {s}')
else:
    check('a campus exists to test the edge function with', False)

# --- storage bucket: an unknown object in a real bucket is NoSuchKey, in a missing bucket NoSuchBucket
s, b, _ = call('/storage/v1/object/public/restaurant-images/__probe__.png', headers={'apikey': KEY})
check('storage bucket restaurant-images exists', 'NoSuchBucket' not in b, b[:60])

# --- hosting
for label, var, default in [('Flutter Web', 'FLUTTER_WEB_URL', 'https://meogeobojo.onrender.com'),
                            ('Admin Web', 'ADMIN_URL', 'https://meogeobojo-admin.onrender.com')]:
    u = ENV.get(var, default)
    try:
        r = urllib.request.urlopen(urllib.request.Request(u, headers={'User-Agent': 'verify'}), timeout=20)
        s, b = r.status, r.read().decode('utf8', 'ignore')
    except Exception as e:
        s, b = 0, str(e)
    m = re.search(r'<title>(.*?)</title>', b, re.S)
    check(f'{label} is publicly served at {u}', s == 200, f"HTTP {s}, title {m.group(1).strip() if m else None!r}")

# --- no privileged key in client code
bad = []
for base in ['lib', 'web', 'admin/src', 'admin/index.html']:
    p = ROOT / base
    files = [p] if p.is_file() else [f for f in p.rglob('*') if f.is_file() and f.suffix in ('.dart', '.ts', '.tsx', '.js', '.html')] if p.exists() else []
    for f in files:
        txt = f.read_text(errors='ignore')
        if re.search(r'service_role[\'"]?\s*[:=]\s*[\'"]eyJ|SERVICE_ROLE_KEY\s*=\s*[\'"][A-Za-z0-9._-]{20,}', txt):
            bad.append(str(f.relative_to(ROOT)))
check('no service-role key in Flutter / web / admin source', not bad, ', '.join(bad))
try:
    payload = KEY.split('.')[1] + '=' * (-len(KEY.split('.')[1]) % 4)
    import base64
    role = json.loads(base64.urlsafe_b64decode(payload)).get('role') if KEY.startswith('eyJ') else 'sb_publishable'
    check('the configured client key is a publishable/anon key', role in ('anon', 'sb_publishable'), f'role={role}')
except Exception:
    check('the configured client key is a publishable/anon key', KEY.startswith('sb_publishable'), 'opaque key')

failed = [r for r in results if not r[0]]
print(f'\n{len(results) - len(failed)}/{len(results)} checks passed.')
print('Not checked here (needs signed-in accounts): admin edits reaching the app, uploads, moderation, mission refresh.')
sys.exit(1 if failed else 0)
