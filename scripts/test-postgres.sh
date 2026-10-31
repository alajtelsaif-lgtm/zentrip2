#!/usr/bin/env bash
# Full suite against a new disposable local database, never the configured Supabase database.
set -euo pipefail
cd "$(dirname "$0")/.."
export JAVA_HOME="$PWD/.local/toolchains/jdk"
export PATH="$JAVA_HOME/bin:$PATH"
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
export ZENTRIP_POSTGRES_TEST_URL="jdbc:postgresql://127.0.0.1:$port/zentrip_test"
export ZENTRIP_POSTGRES_TEST_USER=zentrip_test
mvn -B -f backend/pom.xml \
  -Dspring.datasource.url="$ZENTRIP_POSTGRES_TEST_URL" \
  -Dspring.datasource.username="$ZENTRIP_POSTGRES_TEST_USER" \
  -Dspring.datasource.password= -Dapp.bootstrap.enabled=false test
