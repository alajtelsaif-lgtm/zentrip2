#!/usr/bin/env bash
# Read-only duplicate report. There is intentionally no apply mode.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" != "--dry-run" || "${2:-}" != "--backup" || -z "${3:-}" ]]; then
  echo "Usage: $0 --dry-run --backup /path/to/verified-database-backup"
  exit 2
fi

backup_reference="$3"
if [[ ! -s "$backup_reference" || ! -r "$backup_reference" ]]; then
  echo "A readable, non-empty database backup file is required before the audit."
  exit 2
fi

database_url="${SUPABASE_DB_URL:-${DB_URL:-}}"
database_url="${database_url#jdbc:}"
if [[ -z "$database_url" ]]; then
  echo "Set SUPABASE_DB_URL to the database used for the audit."
  exit 2
fi
if ! command -v psql >/dev/null 2>&1; then
  echo "psql is required to run the read-only report."
  exit 2
fi

export PGPASSWORD="${SUPABASE_DB_PASSWORD:-${DB_PASSWORD:-}}"
psql_args=(-X -v ON_ERROR_STOP=1 --dbname "$database_url")
if [[ -n "${SUPABASE_DB_USER:-}" ]]; then
  psql_args+=(--username "$SUPABASE_DB_USER")
fi

echo "Running read-only landmark duplicate audit. No rows will be changed."
psql "${psql_args[@]}" \
  -f backend/src/main/resources/migrations/landmark_duplicate_audit.sql
