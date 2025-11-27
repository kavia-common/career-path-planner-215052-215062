#!/bin/bash
# PUBLIC_INTERFACE
# Minimal healthcheck for PostgreSQL in this container (idempotent safe).
# Checks readiness via pg_isready against PGHOST/PGPORT with explicit constants,
# falling back to a psql SELECT 1; exits 0 on success. Adds verbose logs and retries.

set -u

DB_NAME="${DB_NAME:-myapp}"
DB_USER="${DB_USER:-appuser}"
DB_PASSWORD="${DB_PASSWORD:-dbuser123}"

# Determine effective port from env with safe fallback
EFFECTIVE_PORT="${DATABASE_PORT:-}"
EFFECTIVE_PORT="${EFFECTIVE_PORT:-${DB_PORT:-}}"
EFFECTIVE_PORT="${EFFECTIVE_PORT:-${PORT:-}}"
EFFECTIVE_PORT="${EFFECTIVE_PORT:-5000}"

# Explicit readiness constants to avoid platform env ambiguity
READINESS_HOST="127.0.0.1"
export PGHOST="${READINESS_HOST}"
export PGPORT="${EFFECTIVE_PORT}"

echo "[healthcheck] READINESS_PORT=${PGPORT}"
echo "[healthcheck] Checking PostgreSQL at ${PGHOST}:${PGPORT} (db=${DB_NAME} user=${DB_USER})"
echo "[healthcheck] Readiness uses PGHOST=${PGHOST} PGPORT=${PGPORT}. There is no check on any web process."

PG_VERSION=$(ls /usr/lib/postgresql/ 2>/dev/null | sort -r | head -1)
if [ -z "${PG_VERSION:-}" ]; then
  echo "[healthcheck][ERROR] PostgreSQL client not found (version dir missing)"
  exit 2
fi
PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"
if [ ! -x "${PG_BIN}/psql" ]; then
  echo "[healthcheck][ERROR] PostgreSQL client not found (psql missing)"
  exit 2
fi

# Quick readiness pre-check (pg_isready), but do NOT exit success solely based on this; we must validate psql connectivity
if [ -x "${PG_BIN}/pg_isready" ]; then
  for i in $(seq 1 20); do
    if "${PG_BIN}/pg_isready" -h "${PGHOST}" -p "${PGPORT}" >/dev/null 2>&1; then
      echo "[healthcheck] pg_isready OK on attempt ${i}; verifying psql connectivity..."
      break
    fi;
    echo "[healthcheck] Waiting for pg_isready OK (${i}/20) at ${PGHOST}:${PGPORT}"
    sleep 2
  done
fi

# Mandatory psql connectivity check with more retries
for i in $(seq 1 30); do
  PGPASSWORD="${DB_PASSWORD}" "${PG_BIN}/psql" -h "${PGHOST}" -p "${PGPORT}" -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT 1;" >/dev/null 2>&1
  EC=$?
  if [ $EC -eq 0 ]; then
    echo "[healthcheck] DB health: OK (psql) on attempt ${i}"
    exit 0
  fi
  echo "[healthcheck] psql ping failed (attempt ${i}/30) to ${PGHOST}:${PGPORT}/${DB_NAME} as ${DB_USER}"
  echo "[healthcheck] Hint: ensure DB_USER/DB_NAME/DB_PASSWORD match server credentials and SCRAM password is set; port=${PGPORT}"
  sleep 2
done

echo "[healthcheck] DB health: FAIL at ${PGHOST}:${PGPORT}"
exit 2
