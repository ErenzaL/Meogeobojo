#!/usr/bin/env bash
# Applies EVERY migration, in order, to a STAGING database (a separate Supabase project). Never production.
#
#   STAGING_DATABASE_URL='postgresql://postgres:<password>@db.<staging-ref>.supabase.co:5432/postgres' \
#     scripts/staging_apply_migrations.sh [--dry-run] [--from 20261117000100]
#
# * reads only STAGING_DATABASE_URL (the password is part of it: keep it in your shell, never in a file in the repo)
# * refuses the production project (ref below) and any URL that does not look like a Supabase / local database
# * --dry-run lists what would run; --from starts at a later migration (to continue after a failure)
# * every file is applied with ON_ERROR_STOP; the script stops at the first error and tells you which file
# * the migrations from 20261101000600 on are idempotent (re-run them freely); some OLDER ones (for example 20261031000300) are
#   not, so apply the whole chain once to a fresh project and afterwards use --from <first new migration>
set -euo pipefail
PRODUCTION_REF="jnnofemlolwdyonfhzje"
cd "$(dirname "$0")/.."
URL="${STAGING_DATABASE_URL:-}"; DRY=0; FROM=""
while [ $# -gt 0 ]; do case "$1" in --dry-run) DRY=1;; --from) FROM="$2"; shift;; *) echo "unknown option $1" >&2; exit 2;; esac; shift; done
[ -n "$URL" ] || { echo "Set STAGING_DATABASE_URL (the staging project's Postgres connection string)." >&2; exit 2; }
case "$URL" in *"$PRODUCTION_REF"*) echo "REFUSING: that is the PRODUCTION project ($PRODUCTION_REF)." >&2; exit 2;; esac
case "$URL" in postgres://*|postgresql://*) ;; *) echo "STAGING_DATABASE_URL must be a postgres:// URL" >&2; exit 2;; esac
PSQL="${PSQL:-psql}"
files=$(ls supabase/migrations/*.sql | sort)
n=0
for f in $files; do
  v=$(basename "$f" | cut -d_ -f1)
  if [ -n "$FROM" ] && [ "$v" \< "$FROM" ]; then continue; fi
  n=$((n+1))
  if [ $DRY -eq 1 ]; then echo "would apply $(basename "$f")"; continue; fi
  printf 'applying %s ... ' "$(basename "$f")"
  if "$PSQL" "$URL" -v ON_ERROR_STOP=1 -q -f "$f" >/dev/null 2>"${TMPDIR:-/tmp}/staging_migration_err.txt"; then echo ok
  else echo FAILED; cat "${TMPDIR:-/tmp}/staging_migration_err.txt" >&2; echo "stopped at $(basename "$f"); fix it, then re-run with --from $v" >&2; exit 1; fi
done
echo "$n migration file(s) $( [ $DRY -eq 1 ] && echo listed || echo applied )."
