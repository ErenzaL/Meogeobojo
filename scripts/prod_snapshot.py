#!/usr/bin/env python3
"""Fingerprint of everything students can read (publishable key only; READ-ONLY).

  python3 scripts/prod_snapshot.py --save before.json      # before the release
  python3 scripts/prod_snapshot.py --compare before.json   # after the release: nothing may have changed

For each public table it records the row count and a hash of every row (so an edited, hidden or deleted row
is noticed). Row-level security decides what the key can see, so this is exactly what the apps see.
Exit status 0 = identical.
"""
import hashlib, json, os, pathlib, re, sys, urllib.error, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
def env():
    d = dict(os.environ)
    p = ROOT / 'admin' / '.env'
    if p.exists():
        for line in p.read_text().splitlines():
            m = re.match(r'\s*([A-Z_]+)\s*=\s*(.*)', line)
            if m: d.setdefault(m.group(1), m.group(2).strip().strip('"\''))
    return d
E = env(); URL = (E.get('SUPABASE_URL') or E.get('VITE_SUPABASE_URL') or '').rstrip('/'); KEY = E.get('SUPABASE_PUBLISHABLE_KEY') or E.get('VITE_SUPABASE_ANON_KEY') or ''
if not URL or not KEY: sys.exit('Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (or admin/.env).')
TABLES = ['universities', 'restaurant_overrides', 'restaurant_menus', 'restaurant_photos', 'campus_cafeterias', 'cafeteria_meals', 'app_content', 'student_reviews']

def fetch(table):
    rows, off = [], 0
    while True:
        req = urllib.request.Request(f'{URL}/rest/v1/{table}?select=*&order=id&limit=1000&offset={off}', headers={'apikey': KEY, 'Authorization': 'Bearer ' + KEY})
        try: page = json.loads(urllib.request.urlopen(req, timeout=30).read())
        except urllib.error.HTTPError as e: return {'error': f'HTTP {e.code}'}
        rows += page
        if len(page) < 1000: break
        off += 1000
    h = hashlib.sha256(json.dumps(rows, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:16]
    ids = hashlib.sha256(json.dumps([r.get('id') for r in rows]).encode()).hexdigest()[:16]
    return {'rows': len(rows), 'content_hash': h, 'id_hash': ids}

snap = {t: fetch(t) for t in TABLES}
if '--save' in sys.argv:
    pathlib.Path(sys.argv[sys.argv.index('--save') + 1]).write_text(json.dumps(snap, indent=1, ensure_ascii=False))
    for t, v in snap.items(): print(f'{t:22s} {v}')
    print('saved.'); sys.exit(0)
if '--compare' in sys.argv:
    before = json.loads(pathlib.Path(sys.argv[sys.argv.index('--compare') + 1]).read_text()); bad = 0
    for t in TABLES:
        a, b = before.get(t), snap[t]
        same = a == b
        bad += not same
        print(('SAME ' if same else 'DIFF ') + f'{t:22s} rows {a.get("rows")} -> {b.get("rows")}' + ('' if same else f'   ({a} -> {b})'))
    print('\nidentical: nothing students can read has changed.' if not bad else f'\n{bad} table(s) differ (expected only if someone published or edited content in between).')
    sys.exit(1 if bad else 0)
for t, v in snap.items(): print(f'{t:22s} {v}')
