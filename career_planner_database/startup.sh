#!/bin/bash

# Minimal PostgreSQL startup script with full paths and explicit Node viewer guard + healthcheck
DB_NAME="${DB_NAME:-myapp}"
DB_USER="${DB_USER:-appuser}"
DB_PASSWORD="${DB_PASSWORD:-dbuser123}"
DB_PORT="${DB_PORT:-5000}"

# Explicit guard: do NOT enable the viewer in this container
: "${ENABLE_DB_VIEWER:=false}"

echo "Starting PostgreSQL setup..."

# Find PostgreSQL version and set paths
PG_VERSION=$(ls /usr/lib/postgresql/ 2>/dev/null | head -1)
if [ -z "$PG_VERSION" ]; then
  echo "ERROR: PostgreSQL binaries not found under /usr/lib/postgresql/"
  exit 127
fi
PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"

echo "Found PostgreSQL version: ${PG_VERSION}"

# Function: health check via psql
psql_ping() {
  PGPASSWORD="${DB_PASSWORD}" "${PG_BIN}/psql" -h localhost -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT 1;" >/dev/null 2>&1
  return $?
}

# Check if PostgreSQL is already running on the specified port
if sudo -u postgres "${PG_BIN}/pg_isready" -p "${DB_PORT}" > /dev/null 2>&1; then
    echo "PostgreSQL is already running on port ${DB_PORT}!"
    echo "Database: ${DB_NAME}"
    echo "User: ${DB_USER}"
    echo "Port: ${DB_PORT}"
    echo ""
    echo "To connect to the database, use:"
    echo "psql -h localhost -U ${DB_USER} -d ${DB_NAME} -p ${DB_PORT}"

    if [ -f "db_connection.txt" ]; then
        echo "Or use: $(cat db_connection.txt)"
    fi

    # Healthcheck: verify psql connectivity
    if ! psql_ping; then
        echo "ERROR: PostgreSQL is running but psql connectivity failed."
        exit 2
    fi

    echo ""
    echo "Script stopped - server already running."
    exit 0
fi

# Also check if there's a PostgreSQL process running (in case pg_isready fails)
if pgrep -f "postgres.*-p ${DB_PORT}" > /dev/null 2>&1; then
    echo "Found existing PostgreSQL process on port ${DB_PORT}"
    echo "Attempting to verify connection..."

    if sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d "${DB_NAME}" -c '\q' 2>/dev/null; then
        echo "Database ${DB_NAME} is accessible."
        # Healthcheck as above
        if ! psql_ping; then
            echo "ERROR: PostgreSQL is running but psql connectivity failed."
            exit 2
        fi
        echo "Script stopped - server already running."
        exit 0
    fi
fi

# Initialize PostgreSQL data directory if it doesn't exist
if [ ! -f "/var/lib/postgresql/data/PG_VERSION" ]; then
    echo "Initializing PostgreSQL..."
    sudo -u postgres "${PG_BIN}/initdb" -D /var/lib/postgresql/data
fi

# Start PostgreSQL server in background
echo "Starting PostgreSQL server..."
sudo -u postgres "${PG_BIN}/postgres" -D /var/lib/postgresql/data -p "${DB_PORT}" &

# Wait for PostgreSQL to start
echo "Waiting for PostgreSQL to start..."
sleep 5

# Check if PostgreSQL is running
READY=false
for i in {1..15}; do
    if sudo -u postgres "${PG_BIN}/pg_isready" -p "${DB_PORT}" > /dev/null 2>&1; then
        echo "PostgreSQL is ready!"
        READY=true
        break
    fi
    echo "Waiting... ($i/15)"
    sleep 2
done

if [ "${READY}" != "true" ]; then
    echo "ERROR: PostgreSQL failed to become ready on port ${DB_PORT}"
    exit 1
fi

# Create database and user
echo "Setting up database and user..."
sudo -u postgres "${PG_BIN}/createdb" -p "${DB_PORT}" "${DB_NAME}" 2>/dev/null || echo "Database might already exist"

# Set up user and permissions with proper schema ownership
sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d postgres << EOF
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
        CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';
    END IF;
    ALTER ROLE ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
END
\$\$;

GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};

\c ${DB_NAME}

GRANT USAGE ON SCHEMA public TO ${DB_USER};
GRANT CREATE ON SCHEMA public TO ${DB_USER};

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TYPES TO ${DB_USER};

GRANT ALL ON SCHEMA public TO ${DB_USER};

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO ${DB_USER};
EOF

# Additionally, connect to the specific database to ensure permissions
sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d "${DB_NAME}" << EOF
GRANT ALL ON SCHEMA public TO ${DB_USER};
GRANT CREATE ON SCHEMA public TO ${DB_USER};
EOF

# Save connection command to a file
echo "psql postgresql://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}" > db_connection.txt
echo "Connection string saved to db_connection.txt"

# Save environment variables to a file for optional viewer use (kept inert by default)
mkdir -p db_visualizer
cat > db_visualizer/postgres.env << EOF
export POSTGRES_URL="postgresql://localhost:${DB_PORT}/${DB_NAME}"
export POSTGRES_USER="${DB_USER}"
export POSTGRES_PASSWORD="${DB_PASSWORD}"
export POSTGRES_DB="${DB_NAME}"
export POSTGRES_PORT="${DB_PORT}"
EOF

# Final healthcheck (psql ping). Exit non-zero if fails.
if ! psql_ping; then
    echo "ERROR: PostgreSQL healthcheck failed (psql ping)."
    exit 2
fi

echo "PostgreSQL setup complete!"
echo "Database: ${DB_NAME}"
echo "User: ${DB_USER}"
echo "Port: ${DB_PORT}"
echo ""

echo "Environment variables saved to db_visualizer/postgres.env"
echo "Note: This database container starts ONLY PostgreSQL. The optional Node.js viewer is not started here."
echo "ENABLE_DB_VIEWER is '${ENABLE_DB_VIEWER}'. It must be set to 'true' and run manually OUTSIDE this container to start the viewer."

echo "To connect to the database, use one of the following commands:"
echo "psql -h localhost -U ${DB_USER} -d ${DB_NAME} -p ${DB_PORT}"
echo "$(cat db_connection.txt)"
