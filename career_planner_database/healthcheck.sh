#!/bin/bash
# PUBLIC_INTERFACE
# Minimal healthcheck for PostgreSQL in this container (idempotent safe).
# Checks readiness via pg_isready against 127.0.0.1:${PGPORT} (or DB_PORT),
# falling back to a psql SELECT 1; exits 0 on success. Adds verbose logs and retries.

set -u

DB_NAME="${DB_NAME:-myapp}"
DB_USER="${DB_USER:-appuser}"
DB_PASSWORD="${DB_PASSWORD:-dbuser123}"
DB_PORT="${DB_PORT:-5000}"
PGPORT="${PGPORT:-${DB_PORT}}"
PGHOST="127.0.0.1"
echo "[healthcheck] Checking PostgreSQL at ${PGHOST}:${PGPORT} (db=${DB_NAME} user=${DB_USER})"
echo "[healthcheck] Readiness uses PGPORT=${PGPORT}. There is no check on port 3020."

PG_VERSION=$(ls /usr/lib/postgresql/ 2>/dev/null | head -1)
if [ -z "${PG_VERSION:-}" ]; then
  echo "[healthcheck][ERROR] PostgreSQL client not found (version dir missing)"
  exit 2
fi
PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"
if [ ! -x "${PG_BIN}/psql" ]; then
  echo "[healthcheck][ERROR] PostgreSQL client not found (psql missing)"
  exit 2
fi

# Try pg_isready with retries
if [ -x "${PG_BIN}/pg_isready" ]; then
  for i in $(seq 1 30); do
    if "${PG_BIN}/pg_isready" -h "${PGHOST}" -p "${PGPORT}" >/dev/null 2>&1; then
      echo "[healthcheck] DB health: OK (pg_isready) on attempt ${i}"
      exit 0
    fi
    echo "[healthcheck] Waiting for pg_isready OK (${i}/30) at ${PGHOST}:${PGPORT}"
    sleep 2
  done
fi

# Fallback to simple psql ping with retries
for i in $(seq 1 15); do
  PGPASSWORD="${DB_PASSWORD}" "${PG_BIN}/psql" -h "${PGHOST}" -p "${PGPORT}" -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT 1;" >/dev/null 2>&1
  EC=$?
  if [ $EC -eq 0 ]; then
    echo "[healthcheck] DB health: OK (psql) on attempt ${i}"
    exit 0
  fi
  echo "[healthcheck] psql ping failed (attempt ${i}/15) to ${PGHOST}:${PGPORT}/${DB_NAME} as ${DB_USER}"
  sleep 2
done

echo "[healthcheck] DB health: FAIL at ${PGHOST}:${PGPORT}"
exit 2
