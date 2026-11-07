#!/usr/bin/env bash
# Checks the database end to end on a throwaway local Postgres: applies
# supabase/migrations to a stand-in for Supabase (tests/database/
# supabase_stub.sql), then plays an admin, a gym owner, front-desk staff and
# members through tests/database/scenario_test.sql, which checks every rule.
# Needs PostgreSQL 14+ installed (brew install postgresql). Touches nothing else.
#
#   scripts/test_database.sh
set -euo pipefail
cd "$(dirname "$0")/.."

port="${PGTEST_PORT:-54329}"
dir="$(mktemp -d)"
cleanup() { pg_ctl -D "$dir/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$dir"; }
trap cleanup EXIT

initdb -D "$dir/data" -U postgres --auth=trust -E UTF8 --locale=C >/dev/null
pg_ctl -D "$dir/data" -o "-p $port -c listen_addresses=127.0.0.1 -c unix_socket_directories=''" \
  -l "$dir/log.txt" -w start >/dev/null
db() { psql -h 127.0.0.1 -p "$port" -U postgres -d postgres -v ON_ERROR_STOP=1 -q "$@"; }

db -f tests/database/supabase_stub.sql 2>/dev/null
for migration in supabase/migrations/*.sql; do
  echo "Applying $(basename "$migration")"
  db -f "$migration" 2>&1 | grep -E "ERROR" && exit 1 || true
done
echo "Applying them again (they must be safe to re-run)"
for migration in supabase/migrations/*.sql; do db -f "$migration" >/dev/null 2>&1; done
db -f tests/database/scenario_test.sql 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED" | sed 's/^.*NOTICE:  //'
echo "Applying supabase/seed.sql (local test data)"
db -f supabase/seed.sql
