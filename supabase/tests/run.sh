#!/usr/bin/env bash
# Datenbank-Tests gegen ein lokales Postgres: PGHOST/PGPORT/PGUSER setzen, dann: bash supabase/tests/run.sh
set -euo pipefail
cd "$(dirname "$0")/.."
psql -q -c "drop database if exists tricoach_test" -c "create database tricoach_test"
psql -q -d tricoach_test -v ON_ERROR_STOP=1 -f tests/stub_supabase.sql -f migrations/20261022000000_init.sql -f migrations/20261022180000_integrations.sql -f migrations/20261022200000_integrations_cache.sql 2>&1 | grep -v -e wal_level -e HINT || true
out=$(psql -q -d tricoach_test -f tests/rls_test.sql 2>&1 | sed 's/.*NOTICE:  //')
echo "$out"
echo "$out" | grep -q "ALLE DATENBANK-TESTS BESTANDEN" && ! echo "$out" | grep -q -e FEHLER -e ERROR
