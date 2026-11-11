#!/bin/zsh
# Scratch-PostgreSQL test run for all migrations. Needs a local PostgreSQL
# (set PGBIN) and uses TCP only. Does NOT touch any hosted project.
set -e
PGBIN=${PGBIN:-/Library/PostgreSQL/18/bin}
WORK=${1:?usage: run_local.sh <scratch-dir>}
HERE=${0:A:h}; MIG=$HERE/../migrations
PORT=54329
rm -rf $WORK/pgdata; mkdir -p $WORK
$PGBIN/initdb -D $WORK/pgdata -U postgres --auth=trust -E UTF8 >/dev/null
$PGBIN/pg_ctl -D $WORK/pgdata -o "-p $PORT -c unix_socket_directories='' -c listen_addresses=127.0.0.1" -l $WORK/pg.log -w start >/dev/null
trap "$PGBIN/pg_ctl -D $WORK/pgdata stop -m fast >/dev/null" EXIT
P() { $PGBIN/psql -h 127.0.0.1 -p $PORT -U postgres -v ON_ERROR_STOP=1 -q "$@"; }
P -f $HERE/auth_stub.sql
for f in $(ls $MIG/*.sql | sort | grep -v -E '2026110100050|20261101000[6-9]|202611(0[2-9]|[1-9][0-9])'); do P -f $f >/dev/null 2>&1 || { echo "FAILED: $f"; exit 1; }; done
P -f $HERE/legacy_seed.sql >/dev/null
echo "--- apply 20261101000500 (1st run)"; P -f $MIG/20261101000500_nickname_and_companions.sql >/dev/null
P -f $HERE/migration_0500_test.sql 2>&1 | grep -E "NOTICE:  OK|ERROR" | sed 's/^psql:[^ ]* NOTICE:  //'
echo "--- apply 20261101000500 (2nd run: idempotent)"; P -f $MIG/20261101000500_nickname_and_companions.sql >/dev/null
P -c "select count(*) filter (where cardinality(companion_types)>0) as migrated from public.user_preferences" | sed -n 3p
P -c "delete from auth.users"
echo "--- RLS / RPC suite"; P -f $HERE/rls_test.sql 2>&1 | grep -E "NOTICE:  OK|ERROR" | sed 's/^psql:[^ ]* NOTICE:  //' | cut -c1-120
for f in $(ls $MIG/*.sql | sort | grep -E '20261101000[6-9]|202611(0[2-9]|[1-9][0-9])'); do echo "--- apply $(basename $f) (twice: idempotent)"; P -f $f >/dev/null 2>&1; P -f $f >/dev/null 2>&1 || { echo "FAILED re-run: $f"; exit 1; }; done
echo "--- cafeteria schema / RLS suite"; P -f $HERE/cafeteria_test.sql 2>&1 | grep -E "NOTICE:  OK|ERROR" | sed 's/^psql:[^ ]* NOTICE:  //'
echo "--- admin foundation / authorization suite"; P -f $HERE/admin_test.sql 2>&1 | grep -E "NOTICE:  OK|ERROR|DETAIL|CONTEXT" | sed 's/^psql:[^ ]* NOTICE:  //' | cut -c1-220
echo "--- mission system suite"; P -f $HERE/missions_test.sql 2>&1 | grep -E "NOTICE:  OK|ERROR|DETAIL|CONTEXT" | sed 's/^psql:[^ ]* NOTICE:  //' | cut -c1-220
echo "--- admin content (photos / menus) suite"; P -f $HERE/admin_content_test.sql 2>&1 | grep -E "NOTICE:  OK|ERROR|DETAIL|CONTEXT" | sed 's/^psql:[^ ]* NOTICE:  //' | cut -c1-220
echo "--- CMS publishing suite"; P -f $HERE/cms_publishing_test.sql 2>&1 | grep -E "NOTICE:  OK|ERROR|DETAIL|CONTEXT" | sed 's/^psql:[^ ]* NOTICE:  //' | cut -c1-260
echo "--- bulk publish (the existing cms_set_visibility, per restaurant)"; P -f $HERE/bulk_publish_test.sql 2>&1 | grep -E "NOTICE:  OK|ERROR|DETAIL|CONTEXT" | sed 's/^psql:[^ ]* NOTICE:  //' | cut -c1-260
echo "--- weekly cafeteria management"; P -f $HERE/cafeteria_weekly_test.sql 2>&1 | grep -E "NOTICE:  OK|ERROR|DETAIL|CONTEXT" | sed 's/^psql:[^ ]* NOTICE:  //' | cut -c1-300 || true
echo "--- cafeteria CSV import (server side)"; P -f $HERE/cafeteria_import_test.sql 2>&1 | grep -E "NOTICE:  OK|ERROR|DETAIL|CONTEXT" | sed 's/^psql:[^ ]* NOTICE:  //' | cut -c1-320 || true
echo "--- live-update signal (content_sync)"; P -f $HERE/content_sync_test.sql 2>&1 | grep -E "NOTICE:  OK|ERROR|DETAIL|CONTEXT" | sed 's/^psql:[^ ]* NOTICE:  //' | cut -c1-260 || true
echo "--- preservation (migrations 20261112..18 on populated data)"; P -f $HERE/preservation_test.sql 2>&1 | grep -E "NOTICE:  OK|ERROR|DETAIL|CONTEXT" | sed 's/^psql:[^ ]* NOTICE:  //' | cut -c1-300
echo "--- production read-only checklist (scratch DB has no pg_cron, so only scheduler rows may fail)"
P -f $HERE/../../scripts/prod_readonly_checks.sql > $WORK/checks.out 2>&1 || true
grep -E "ERROR" $WORK/checks.out || true
echo "checklist rows: $(grep -c -E "PASS|FAIL|INFO" $WORK/checks.out), unexpected FAIL outside the scheduler: $(grep FAIL $WORK/checks.out | grep -vc "6 scheduler" || true)"
grep FAIL $WORK/checks.out | grep -v "6 scheduler" | cut -c1-200 || true
echo "--- CSV importer end to end"
U=5c0a8f3e-0001-4a6e-9b1d-000000000001; PY=$HERE/../cafeteria/import_cafeteria_csv.py; T=$WORK/csv; mkdir -p $T
printf 'university_id,cafeteria_id,kind,name_ko,name_en,name_zh,location_description,sort_order\n%s,c9c9c9c9-0000-4000-8000-000000000009,student,,,,,0\n%s,,dormitory,,,,,1\n' $U $U > $T/caf.csv
python3 $PY cafeterias $T/caf.csv > $T/caf.sql && P -f $T/caf.sql >/dev/null && P -f $T/caf.sql >/dev/null
P -t -c "select 'cafeterias after importing twice: ' || count(*) from public.campus_cafeterias"
H='action,university_id,cafeteria_id,meal_date,meal_type,option_name,option_order,menu_items,price_krw,start_time,end_time,status,source_url,verified_at'
C=c9c9c9c9-0000-4000-8000-000000000009
printf '%s\nupsert,%s,%s,2026-11-02,lunch,,0,main:김치찌개|rice:쌀밥,5500,11:30,13:30,published,https://example.org/w,2026-11-02T09:00:00+09:00\nupsert,%s,%s,2026-11-02,lunch,B코너,1,main:돈까스,6000,,,published,,2026-11-02T09:00:00+09:00\nupsert,%s,%s,2026-11-03,dinner,,0,,,,,closed,https://example.org/w,2026-11-02T09:00:00+09:00\n' "$H" $U $C $U $C $U $C > $T/m1.csv
python3 $PY meals $T/m1.csv > $T/m1.sql && P -f $T/m1.sql >/dev/null
P -t -c "select 'meals after import: ' || count(*) from public.cafeteria_meals"
printf '%s\nupsert,%s,%s,2026-11-02,lunch,,0,main:수정된메뉴,5800,,,published,https://example.org/w,2026-11-03T09:00:00+09:00\ndelete,%s,%s,2026-11-03,dinner,,,,,,,,,\n' "$H" $U $C $U $C > $T/m2.csv
python3 $PY meals $T/m2.csv > $T/m2.sql && P -f $T/m2.sql >/dev/null
P -t -c "select 'after update+delete: ' || count(*) || ' rows; lunch price ' || (select price_krw from public.cafeteria_meals where meal_type='lunch' and option_name='') || '; B option kept: ' || exists(select 1 from public.cafeteria_meals where option_name='B코너')::text from public.cafeteria_meals"
printf '%s\nupsert,%s,%s,2026-11-04,lunch,,0,main:x,,,,published,,2026-11-03T09:00:00+09:00\n' "$H" 22222222-2222-4222-8222-222222222222 $C > $T/m3.csv
python3 $PY meals $T/m3.csv > $T/m3.sql
P -f $T/m3.sql 2>&1 | grep -c "import aborted" | sed 's/^/mismatched university aborted the import (1 = yes): /'
P -t -c "select 'rows after aborted import (unchanged): ' || count(*) from public.cafeteria_meals"
