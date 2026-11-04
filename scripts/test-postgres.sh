#!/usr/bin/env bash
# Full suite against a new disposable local database, never the configured Supabase database.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -x "$PWD/.local/toolchains/jdk/bin/java" ]]; then
  export JAVA_HOME="$PWD/.local/toolchains/jdk"
  export PATH="$JAVA_HOME/bin:$PATH"
elif [[ -n "${JAVA_HOME:-}" ]]; then
  export PATH="$JAVA_HOME/bin:$PATH"
fi
unset DATABASE_URL SUPABASE_DB_URL SUPABASE_DB_USER SUPABASE_DB_PASSWORD \
  DB_URL DB_USERNAME DB_PASSWORD \
  PGHOST PGHOSTADDR PGPORT PGUSER PGPASSWORD PGDATABASE PGSERVICE PGSERVICEFILE PGSSLMODE
cluster="$(mktemp -d /tmp/zentrip-postgres-tests.XXXXXX)"
port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
cleanup() {
  pg_ctl -D "$cluster/data" -m fast stop > /dev/null 2>&1 || true
  rm -rf "$cluster"
}
trap cleanup EXIT
initdb -D "$cluster/data" -U zentrip_test -A trust --no-locale -E UTF8 > "$cluster/init.log"
pg_ctl -D "$cluster/data" -o "-p $port -h 127.0.0.1 -k $cluster" -l "$cluster/server.log" start
createdb -h 127.0.0.1 -p "$port" -U zentrip_test zentrip_test
psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$port" -U zentrip_test -d zentrip_test \
  -f backend/src/main/resources/schema.sql > "$cluster/schema.log"
psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$port" -U zentrip_test -d zentrip_test <<'SQL'
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres') THEN
        CREATE ROLE postgres NOLOGIN;
    END IF;
END
$$;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$ SELECT NULL::UUID $$;
CREATE OR REPLACE FUNCTION public.current_app_user_id()
RETURNS BIGINT
LANGUAGE sql
STABLE
AS $$ SELECT NULL::BIGINT $$;
GRANT USAGE ON SCHEMA auth TO anon, authenticated;
SQL
psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$port" -U zentrip_test -d zentrip_test <<'SQL'
DROP TABLE IF EXISTS public.user_push_tokens;
DROP TABLE IF EXISTS public.landmark_merge_candidates;
DROP TABLE IF EXISTS public.landmark_place_aliases;
DROP TABLE IF EXISTS public.landmark_search_areas;
DROP TABLE IF EXISTS public.landmark_places;
DROP TABLE IF EXISTS public.hotel_destinations;
DROP TABLE IF EXISTS public.legacy_attraction_partner_reviews;
SQL
psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$port" -U zentrip_test -d zentrip_test \
  -f backend/src/main/resources/migrations/20261101_schema_migrations.sql \
  > "$cluster/schema-migrations.log"
psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$port" -U zentrip_test -d zentrip_test \
  -f backend/src/main/resources/migrations/20261101_global_airport_directory.sql \
  > "$cluster/airport-migration.log"
if psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$port" -U zentrip_test -d zentrip_test \
  -f backend/src/main/resources/migrations/20261102_landmark_catalog.sql \
  > "$cluster/missing-dependency.log" 2>&1; then
  echo "Landmark migration unexpectedly succeeded without the runtime role." >&2
  exit 1
fi
grep -Fq "requires 20261101_role_access_rls" "$cluster/missing-dependency.log"
psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$port" -U zentrip_test -d zentrip_test \
  -f backend/src/main/resources/migrations/20261101_role_access_rls.sql \
  > "$cluster/role-migration.log"
psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$port" -U zentrip_test -d zentrip_test <<'SQL'
GRANT zentrip_api_runtime TO zentrip_test;
SQL
psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$port" -U zentrip_test -d zentrip_test \
  -f backend/src/main/resources/migrations/20261102_landmark_catalog.sql \
  > "$cluster/landmark-migration.log"
psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$port" -U zentrip_test -d zentrip_test \
  -f backend/src/main/resources/migrations/20261102_landmark_catalog.sql \
  > "$cluster/landmark-idempotency.log"
psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$port" -U zentrip_test -d zentrip_test \
  -f backend/src/main/resources/migrations/20261103_hotel_destination_catalog.sql \
  > "$cluster/hotel-destination-migration.log"
psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$port" -U zentrip_test -d zentrip_test \
  -f backend/src/main/resources/migrations/20261103_hotel_destination_catalog.sql \
  > "$cluster/hotel-destination-idempotency.log"
psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$port" -U zentrip_test -d zentrip_test \
  -f backend/src/main/resources/migrations/20261104_core_data_rls.sql \
  > "$cluster/core-rls-migration.log"
psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$port" -U zentrip_test -d zentrip_test \
  -f backend/src/main/resources/migrations/20261104_core_data_rls.sql \
  > "$cluster/core-rls-idempotency.log"
psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$port" -U zentrip_test -d zentrip_test \
  -f backend/src/main/resources/migrations/20261104_payment_attempts.sql \
  > "$cluster/payment-attempts-migration.log"
psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$port" -U zentrip_test -d zentrip_test \
  -f backend/src/main/resources/migrations/20261104_payment_attempts.sql \
  > "$cluster/payment-attempts-idempotency.log"
psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$port" -U zentrip_test -d zentrip_test \
  -f backend/src/main/resources/migrations/20261105_user_push_tokens.sql \
  > "$cluster/user-push-tokens-migration.log"
psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$port" -U zentrip_test -d zentrip_test \
  -f backend/src/main/resources/migrations/20261105_user_push_tokens.sql \
  > "$cluster/user-push-tokens-idempotency.log"
psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$port" -U zentrip_test -d zentrip_test <<'SQL'
DO $$
DECLARE
    table_name TEXT;
    role_name TEXT;
BEGIN
    IF (SELECT COUNT(*) FROM public.schema_migrations) <> 8 THEN
        RAISE EXCEPTION 'Expected all 8 SQL migrations to be tracked';
    END IF;
    FOREACH table_name IN ARRAY ARRAY[
        'attraction_visit_counts', 'attraction_visit_dedup'
    ] LOOP
        IF NOT (SELECT relrowsecurity FROM pg_class
                WHERE oid = to_regclass('public.' || table_name)) THEN
            RAISE EXCEPTION 'RLS is not enabled on %', table_name;
        END IF;
        FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated'] LOOP
            IF has_table_privilege(role_name, 'public.' || table_name, 'SELECT')
               OR has_table_privilege(role_name, 'public.' || table_name, 'INSERT')
               OR has_table_privilege(role_name, 'public.' || table_name, 'UPDATE') THEN
                RAISE EXCEPTION '% has direct visit-table access to %',
                    role_name, table_name;
            END IF;
        END LOOP;
    END LOOP;
END
$$;
SQL
export ZENTRIP_POSTGRES_TEST_URL="jdbc:postgresql://127.0.0.1:$port/zentrip_test"
export ZENTRIP_POSTGRES_TEST_USER=zentrip_test
if [[ -z "${MAVEN_JAVA_VERSION:-}" ]]; then
  MAVEN_JAVA_VERSION="$(java -XshowSettings:properties -version 2>&1 \
    | awk -F ' = ' '/java.specification.version/ { print $2; exit }')"
fi
if [[ ! "$MAVEN_JAVA_VERSION" =~ ^[0-9]+$ ]]; then
  echo "Could not determine Maven Java release; set MAVEN_JAVA_VERSION explicitly." >&2
  exit 1
fi
python3 scripts/test_client_contract.py
mvn -B -f backend/pom.xml clean \
  -Djava.version="$MAVEN_JAVA_VERSION" \
  -Dspring.datasource.url="$ZENTRIP_POSTGRES_TEST_URL" \
  -Dspring.datasource.username="$ZENTRIP_POSTGRES_TEST_USER" \
  -Dspring.datasource.password= -Dapp.bootstrap.enabled=false test
