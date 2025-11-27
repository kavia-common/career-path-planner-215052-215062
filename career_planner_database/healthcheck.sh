#!/bin/bash
# PUBLIC_INTERFACE
# Minimal healthcheck for PostgreSQL in this container (idempotent safe).
# Checks readiness via pg_isready against 127.0.0.1:${PGPORT} (or DB_PORT),
# falling back to a psql SELECT 1; exits 0 on success.

set -u

DB_NAME="${DB_NAME:-myapp}"
DB_USER="${DB_USER:-appuser}"
DB_PASSWORD="${DB_PASSWORD:-dbuser123}"
DB_PORT="${DB_PORT:-5000}"
PGPORT="${PGPORT:-${DB_PORT}}"
PGHOST="127.0.0.1"

PG_VERSION=$(ls /usr/lib/postgresql/ 2>/dev/null | head -1)
if [ -z "${PG_VERSION:-}" ]; then
  echo "PostgreSQL client not found (version dir missing)"
  exit 2
fi
PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"
if [ ! -x "${PG_BIN}/psql" ]; then
  echo "PostgreSQL client not found (psql missing)"
  exit 2
fi

# Prefer pg_isready if available
if [ -x "${PG_BIN}/pg_isready" ]; then
  if "${PG_BIN}/pg_isready" -h "${PGHOST}" -p "${PGPORT}" >/dev/null 2>&1; then
    echo "DB health: OK (pg_isready)"
    exit 0
  fi
fi

# Fallback to simple psql ping
PGPASSWORD="${DB_PASSWORD}" "${PG_BIN}/psql" -h "${PGHOST}" -p "${PGPORT}" -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT 1;" >/dev/null 2>&1
EC=$?
if [ $EC -ne 0 ]; then
  echo "DB health: FAIL"
  exit $EC
fi
echo "DB health: OK (psql)"
exit 0
