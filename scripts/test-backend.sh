#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export JAVA_HOME="$PWD/.local/toolchains/jdk"
export PATH="$JAVA_HOME/bin:$PATH"
# Mock-based tests should never connect to or log a real database connection.
unset SUPABASE_DB_URL SUPABASE_DB_USER SUPABASE_DB_PASSWORD DB_URL DB_USERNAME DB_PASSWORD
exec mvn -B -f backend/pom.xml \
  -Dspring.autoconfigure.exclude=org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration,org.springframework.boot.autoconfigure.orm.jpa.HibernateJpaAutoConfiguration \
  -Dapp.bootstrap.enabled=false test
