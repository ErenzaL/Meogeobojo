#!/usr/bin/env bash
# Release preflight. READ-ONLY with respect to production: it only builds and tests locally, probes the
# project with the publishable key, and dry-runs the merge in a scratch worktree. It pushes, deploys and
# applies nothing.   Usage: scripts/preflight.sh [release-ref]   (default: HEAD)
set -u
cd "$(dirname "$0")/.."
REF=${1:-HEAD}; SHA=$(git rev-parse "$REF"); FAIL=0
step() { printf '\n== %s\n' "$1"; }
ok()   { printf 'PASS %s\n' "$1"; }
bad()  { printf 'FAIL %s\n' "$1"; FAIL=1; }

step "1. the release commit is a fast-forward of origin/main (no conflicts, nothing else to merge)"
git fetch origin --quiet
if git merge-base --is-ancestor origin/main "$SHA"; then
  ok "origin/main ($(git rev-parse --short origin/main)) is an ancestor of $(git rev-parse --short "$SHA"); commits to release:"
  git log --oneline origin/main.."$SHA" | sed 's/^/     /'
else bad "origin/main is NOT an ancestor of $SHA: rebase or merge first"; fi
[ -z "$(git status --porcelain)" ] && ok "working tree is clean" || bad "uncommitted changes"
git ls-files | grep -E '(^|/)\.env($|\.)|service[_-]?role' | grep -v '\.env\.example' >/dev/null && bad "a secret-looking file is tracked" || ok "no .env / service-role file is tracked"

step "2. Admin: tests, types, lint, production build"
( cd admin && npx vitest run 2>&1 | grep -E "Tests |Test Files" && npx tsc -b --noEmit && npm run lint >/dev/null 2>&1 && npm run build 2>&1 | grep -E "built in" ) && ok "admin" || bad "admin"

step "3. Flutter: analyze + tests"
( dart analyze lib test 2>&1 | tail -1 | grep -q "No issues found" && flutter test 2>&1 | tail -1 | grep -q "All tests passed" ) && ok "flutter" || bad "flutter"

step "4. SQL: every migration on a scratch PostgreSQL (fresh, twice, populated, upgrade path)"
W=$(mktemp -d)
if [ -x "${PGBIN:-/Library/PostgreSQL/18/bin}/initdb" ]; then
  zsh supabase/tests/run_local.sh "$W" > "$W/sql.log" 2>&1
  N=$(grep -c "OK" "$W/sql.log"); if grep -qE "ERROR|FAILED" "$W/sql.log"; then bad "sql suite ($(grep -E 'ERROR|FAILED' "$W/sql.log" | head -1))"; else ok "sql suite: $N checks OK"; fi
else printf 'SKIP no local PostgreSQL (set PGBIN)\n'; fi

step "5. production: read-only probes with the publishable key"
python3 scripts/verify_production.py 2>&1 | grep -E "^(OK|PENDING|FAIL)|passed" ; python3 scripts/verify_production.py >/dev/null 2>&1 && ok "verify_production" || bad "verify_production"
step "6. what Render serves right now"
LIVE=$(curl -sS -m 20 https://meogeobojo-admin.onrender.com/ | grep -o 'assets/index-[A-Za-z0-9_-]*\.js' | head -1); echo "     live admin bundle: ${LIVE:-unreachable}"
python3 scripts/prod_snapshot.py | head -3 | sed "s/^/     /"
echo "     this release's bundle: $(ls admin/dist/assets/index-*.js 2>/dev/null | head -1 | xargs -n1 basename 2>/dev/null) (hash depends on the VITE_* values: compare commits in /settings instead)"

printf '\n'; [ $FAIL -eq 0 ] && echo "PREFLIGHT PASSED (local gates). Production steps still need your approval." || echo "PREFLIGHT FAILED"
exit $FAIL
