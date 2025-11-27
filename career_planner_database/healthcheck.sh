#!/bin/bash
# PUBLIC_INTERFACE
# Minimal healthcheck for PostgreSQL in this container.
# Exits 0 when psql can connect and run SELECT 1; non-zero otherwise.
# Env vars are aligned with startup.sh defaults.
DB_NAME="${DB_NAME:-myapp}"
DB_USER="${DB_USER:-appuser}"
DB_PASSWORD="${DB_PASSWORD:-dbuser123}"
DB_PORT="${DB_PORT:-5000}"

PG_VERSION=$(ls /usr/lib/postgresql/ 2>/dev/null | head -1)
PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"

if [ -z "${PG_VERSION}" ] || [ ! -x "${PG_BIN}/psql" ]; then
  echo "PostgreSQL client not found"
  exit 2
fi

PGPASSWORD="${DB_PASSWORD}" ${PG_BIN}/psql -h localhost -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT 1;" >/dev/null 2>&1
EC=$?
if [ $EC -ne 0 ]; then
  echo "DB health: FAIL"
  exit $EC
fi
echo "DB health: OK"
exit 0
