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
unset SUPABASE_DB_URL SUPABASE_DB_USER SUPABASE_DB_PASSWORD DB_URL DB_USERNAME DB_PASSWORD
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
CREATE ROLE zentrip_api_runtime NOLOGIN;
GRANT zentrip_api_runtime TO zentrip_test;
GRANT USAGE ON SCHEMA public TO zentrip_api_runtime;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO zentrip_api_runtime;
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO zentrip_api_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE zentrip_test IN SCHEMA public
    GRANT ALL PRIVILEGES ON TABLES TO zentrip_api_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE zentrip_test IN SCHEMA public
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO zentrip_api_runtime;
SQL
export ZENTRIP_POSTGRES_TEST_URL="jdbc:postgresql://127.0.0.1:$port/zentrip_test"
export ZENTRIP_POSTGRES_TEST_USER=zentrip_test
mvn -B -f backend/pom.xml \
  -Dspring.datasource.url="$ZENTRIP_POSTGRES_TEST_URL" \
  -Dspring.datasource.username="$ZENTRIP_POSTGRES_TEST_USER" \
  -Dspring.datasource.password= -Dapp.bootstrap.enabled=false test
