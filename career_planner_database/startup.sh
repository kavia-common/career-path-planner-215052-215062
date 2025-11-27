#!/bin/bash
# PUBLIC_INTERFACE
# Hardened PostgreSQL-only startup script (idempotent).
# - Starts ONLY PostgreSQL; never starts Node.js viewer.
# - If Postgres is already running, skip start and perform healthcheck.
# - Clear exit codes: only fail when PostgreSQL is unhealthy or not found.
# Guard note: Orchestrators should not chain Node viewer commands after this script.

# Avoid globally aborting on any non-zero to prevent unrelated commands from
# causing a non-zero propagation at script end. We will check errors explicitly.
set -u
IFS=$' \t\n'

# Defensive guard message
if [ "${DISABLE_CHAINED_CMDS:-true}" = "true" ]; then
  echo "[startup] Defensive guard enabled (DISABLE_CHAINED_CMDS=true). Do not chain Node viewer commands after startup.sh."
fi

DB_NAME="${DB_NAME:-myapp}"
DB_USER="${DB_USER:-appuser}"
DB_PASSWORD="${DB_PASSWORD:-dbuser123}"
DB_PORT="${DB_PORT:-5000}"
export PGPORT="${PGPORT:-${DB_PORT}}"
PGHOST="127.0.0.1"
echo "[startup] Config: host=${PGHOST} port=${PGPORT} db=${DB_NAME} user=${DB_USER}"
echo "[startup] Readiness target: PostgreSQL on ${PGHOST}:${PGPORT} (PGPORT). No readiness on port 3020."

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
  echo "[startup][debug] psql ping to ${PGHOST}:${PGPORT}/${DB_NAME} as ${DB_USER}"
  PGPASSWORD="${DB_PASSWORD}" "${PG_BIN}/psql" -h "${PGHOST}" -p "${PGPORT}" -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT 1;" >/dev/null 2>&1
  return $?
}

# If Postgres is already running, do not try to start it again (idempotent behavior)
if sudo -u postgres "${PG_BIN}/pg_isready" -h "${PGHOST}" -p "${PGPORT}" >/dev/null 2>&1; then
  echo "[startup] PostgreSQL already running on ${PGHOST}:${PGPORT}. Performing healthcheck..."
  if ! psql_ping; then
    echo "[startup][ERROR] PostgreSQL is running but psql connectivity to ${DB_NAME} as ${DB_USER} failed."
    exit 2
  fi
  echo "[startup] Healthcheck OK. Skipping start. Exiting 0."
  exit 0
fi

# Secondary check by process grep for robustness
if pgrep -fa "postgres.*-p ${PGPORT}" >/dev/null 2>&1; then
  echo "[startup] Detected postgres process on port ${PGPORT}. Verifying connectivity..."
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
  if ! sudo -u postgres "${PG_BIN}/initdb" -D /var/lib/postgresql/data; then
    echo "[startup][ERROR] initdb failed"
    exit 1
  fi
fi

# Start PostgreSQL (foregrounded in background)
echo "[startup] Starting PostgreSQL server on ${PGHOST}:${PGPORT}..."
if ! sudo -u postgres "${PG_BIN}/postgres" -D /var/lib/postgresql/data -p "${PGPORT}" & then
  echo "[startup][ERROR] failed to spawn postgres"
  exit 1
fi
POSTGRES_PID=$!

# Wait until ready with extended retries to avoid flapping
echo "[startup] Waiting for PostgreSQL to become ready at ${PGHOST}:${PGPORT}..."
ready=0
for i in $(seq 1 60); do
  if sudo -u postgres "${PG_BIN}/pg_isready" -h "${PGHOST}" -p "${PGPORT}" >/dev/null 2>&1; then
    echo "[startup] PostgreSQL is ready (pg_isready) on attempt ${i}."
    ready=1
    break
  fi
  echo "[startup] ... waiting for readiness (${i}/60) at ${PGHOST}:${PGPORT}"
  sleep 2
done

if [ "$ready" -ne 1 ]; then
  echo "[startup][ERROR] PostgreSQL failed to become ready on ${PGHOST}:${PGPORT}"
  # Ensure we don't leave orphan process if it started
  if ps -p ${POSTGRES_PID} >/dev/null 2>&1; then
    kill ${POSTGRES_PID} >/dev/null 2>&1 || true
  fi
  exit 1
fi

# Create DB and role idempotently
echo "[startup] Ensuring database and role exist..."
sudo -u postgres "${PG_BIN}/createdb" -h "${PGHOST}" -p "${PGPORT}" "${DB_NAME}" >/dev/null 2>&1 || echo "[startup] Database '${DB_NAME}' already exists"

sudo -u postgres "${PG_BIN}/psql" -h "${PGHOST}" -p "${PGPORT}" -d postgres <<EOF
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
sudo -u postgres "${PG_BIN}/psql" -h "${PGHOST}" -p "${PGPORT}" -d "${DB_NAME}" <<EOF
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
echo "psql postgresql://${DB_USER}:${DB_PASSWORD}@${PGHOST}:${PGPORT}/${DB_NAME}" > db_connection.txt

# Write inert viewer env for local-only use
mkdir -p db_visualizer
cat > db_visualizer/postgres.env <<EOF
export POSTGRES_URL="postgresql://localhost:${PGPORT}/${DB_NAME}"
export POSTGRES_USER="${DB_USER}"
export POSTGRES_PASSWORD="${DB_PASSWORD}"
export POSTGRES_DB="${DB_NAME}"
export POSTGRES_PORT="${PGPORT}"
EOF

# Final healthcheck with visibility
if ! psql_ping; then
  echo "[startup][ERROR] PostgreSQL healthcheck failed (psql ping to ${PGHOST}:${PGPORT}/${DB_NAME})"
  exit 2
fi

echo "[startup] PostgreSQL setup complete."
echo "[startup] Database: ${DB_NAME} | User: ${DB_USER} | Port: ${PGPORT}"
echo "[startup] Connection helper saved to db_connection.txt"
echo "[startup] Viewer env saved to db_visualizer/postgres.env (viewer is NOT started here)."

# Important: Never start Node viewer here; even if ENABLE_DB_VIEWER=true, we skip it safely.
if [ "${ENABLE_DB_VIEWER}" = "true" ]; then
  echo "[startup] ENABLE_DB_VIEWER=true was set, but viewer is disabled in this container."
  echo "[startup] To use it, run 'npm install && npm start' from db_visualizer in a separate process/container."
fi

# Keep the container alive if required by the platform.
# Default KEEP_ALIVE=true so orchestrators that rely on a long-lived process do not stop the container.
KEEP_ALIVE="${KEEP_ALIVE:-true}"
if [ "${KEEP_ALIVE}" = "true" ]; then
  echo "[startup] KEEP_ALIVE=true -> entering supervise loop to keep container alive."
  # Graceful shutdown handler
  trap 'echo "[startup] Caught SIGTERM, forwarding to postgres (${POSTGRES_PID}) and exiting..."; \
        if ps -p ${POSTGRES_PID} >/dev/null 2>&1; then kill ${POSTGRES_PID}; fi; exit 0' TERM INT

  # Supervise loop: periodically verify pg_isready and sleep
  while true; do
    if ! sudo -u postgres "${PG_BIN}/pg_isready" -h "${PGHOST}" -p "${PGPORT}" >/dev/null 2>&1; then
      echo "[startup][warn] pg_isready reports not ready at ${PGHOST}:${PGPORT}. Will keep running and retry..."
    fi
    sleep 10
  done
fi

# Clean success exit to prevent chained commands within this script context.
exit 0
