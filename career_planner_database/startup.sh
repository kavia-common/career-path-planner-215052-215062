#!/bin/bash
# PUBLIC_INTERFACE
# Hardened PostgreSQL-only startup script (idempotent).
# - Starts ONLY PostgreSQL; never starts Node.js viewer.
# - If Postgres is already running, skip start and perform healthcheck then exit 0.
# - Clear exit codes: only fail when PostgreSQL is unhealthy or not found.

set -euo pipefail

DB_NAME="${DB_NAME:-myapp}"
DB_USER="${DB_USER:-appuser}"
DB_PASSWORD="${DB_PASSWORD:-dbuser123}"
DB_PORT="${DB_PORT:-5000}"

# Explicit guard: do NOT enable or start the viewer in this container
: "${ENABLE_DB_VIEWER:=false}"
if [ "${ENABLE_DB_VIEWER}" != "true" ]; then
  export ENABLE_DB_VIEWER="false"
fi

echo "[startup] PostgreSQL-only startup initializing..."

# Locate PostgreSQL
PG_VERSION=$(ls /usr/lib/postgresql/ 2>/dev/null | head -1 || true)
if [ -z "${PG_VERSION}" ]; then
  echo "[startup][ERROR] PostgreSQL binaries not found under /usr/lib/postgresql/"
  exit 127
fi
PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"
echo "[startup] Found PostgreSQL version: ${PG_VERSION}"

# Healthcheck helper
psql_ping() {
  PGPASSWORD="${DB_PASSWORD}" "${PG_BIN}/psql" -h localhost -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT 1;" >/dev/null 2>&1
  return $?
}

# If Postgres is already running, do not try to start it again (idempotent behavior)
if sudo -u postgres "${PG_BIN}/pg_isready" -p "${DB_PORT}" >/dev/null 2>&1; then
  echo "[startup] PostgreSQL already running on port ${DB_PORT}. Performing healthcheck..."
  if ! psql_ping; then
    echo "[startup][ERROR] PostgreSQL is running but psql connectivity to ${DB_NAME} as ${DB_USER} failed."
    exit 2
  fi
  echo "[startup] Healthcheck OK. Skipping start. Exiting 0."
  exit 0
fi

# Secondary check by process grep for robustness
if pgrep -fa "postgres.*-p ${DB_PORT}" >/dev/null 2>&1; then
  echo "[startup] Detected postgres process on port ${DB_PORT}. Verifying connectivity..."
  if ! psql_ping; then
    echo "[startup][ERROR] PostgreSQL process detected but psql connectivity failed."
    exit 2
  fi
  echo "[startup] Healthcheck OK. Skipping start. Exiting 0."
  exit 0
fi

# Ensure data dir initialized
if [ ! -f "/var/lib/postgresql/data/PG_VERSION" ]; then
  echo "[startup] Initializing PostgreSQL data directory..."
  sudo -u postgres "${PG_BIN}/initdb" -D /var/lib/postgresql/data
fi

# Start PostgreSQL (foregrounded in background)
echo "[startup] Starting PostgreSQL server..."
sudo -u postgres "${PG_BIN}/postgres" -D /var/lib/postgresql/data -p "${DB_PORT}" &
POSTGRES_PID=$!

# Wait until ready
echo "[startup] Waiting for PostgreSQL to become ready..."
for i in $(seq 1 20); do
  if sudo -u postgres "${PG_BIN}/pg_isready" -p "${DB_PORT}" >/dev/null 2>&1; then
    echo "[startup] PostgreSQL is ready."
    break
  fi
  echo "[startup] ... waiting (${i}/20)"
  sleep 2
done

if ! sudo -u postgres "${PG_BIN}/pg_isready" -p "${DB_PORT}" >/dev/null 2>&1; then
  echo "[startup][ERROR] PostgreSQL failed to become ready on port ${DB_PORT}"
  # Ensure we don't leave orphan process if it started
  if ps -p ${POSTGRES_PID} >/dev/null 2>&1; then
    kill ${POSTGRES_PID} >/dev/null 2>&1 || true
  fi
  exit 1
fi

# Create DB and role idempotently
echo "[startup] Ensuring database and role exist..."
sudo -u postgres "${PG_BIN}/createdb" -p "${DB_PORT}" "${DB_NAME}" >/dev/null 2>&1 || echo "[startup] Database '${DB_NAME}' already exists"

sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d postgres <<EOF
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';
  END IF;
  ALTER ROLE ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
END
\$\$;

GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
EOF

# Ensure schema permissions
sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d "${DB_NAME}" <<EOF
GRANT USAGE, CREATE ON SCHEMA public TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TYPES TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO ${DB_USER};
EOF

# Save connection helper
echo "psql postgresql://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}" > db_connection.txt

# Write inert viewer env for local-only use
mkdir -p db_visualizer
cat > db_visualizer/postgres.env <<EOF
export POSTGRES_URL="postgresql://localhost:${DB_PORT}/${DB_NAME}"
export POSTGRES_USER="${DB_USER}"
export POSTGRES_PASSWORD="${DB_PASSWORD}"
export POSTGRES_DB="${DB_NAME}"
export POSTGRES_PORT="${DB_PORT}"
EOF

# Final healthcheck
if ! psql_ping; then
  echo "[startup][ERROR] PostgreSQL healthcheck failed (psql ping)."
  exit 2
fi

echo "[startup] PostgreSQL setup complete."
echo "[startup] Database: ${DB_NAME} | User: ${DB_USER} | Port: ${DB_PORT}"
echo "[startup] Connection helper saved to db_connection.txt"
echo "[startup] Viewer env saved to db_visualizer/postgres.env (viewer is NOT started here)."

# Important: Never start Node viewer here; even if ENABLE_DB_VIEWER=true, we skip it safely.
if [ "${ENABLE_DB_VIEWER}" = "true" ]; then
  echo "[startup] ENABLE_DB_VIEWER=true was set, but viewer is disabled in this container."
  echo "[startup] To use it, run 'npm install && npm start' from db_visualizer in a separate process/container."
fi

exit 0
