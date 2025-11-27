# Career Planner Database (Supabase/Postgres)

This folder contains the database schema, row-level security (RLS), and a data ingestion utility to seed catalog data (roles, competencies, mappings, adjacency, and role cards) from the provided attachments.

Important:
- This container starts ONLY PostgreSQL and essential init scripts (see startup.sh).
- Idempotent startup: if PostgreSQL is already running, startup.sh skips start and performs a healthcheck, exiting 0 on success.
- Healthcheck: use ./healthcheck.sh (pg_isready → psql) targeting 127.0.0.1:${PGPORT:-5000}. Readiness is based on the PostgreSQL port only; there is no check on 3020.
- Explicit logs: startup.sh and healthcheck.sh print the exact PGPORT used for readiness and explicitly state that no 3020 checks exist.
- No references to port 3020 exist; readiness is strictly the PostgreSQL port (${PGPORT:-5000}). EXPOSED_PORTS emits this value for platforms that require it.
- KEEP_ALIVE: by default KEEP_ALIVE=true, so after a successful healthcheck, startup.sh enters a lightweight supervise loop to keep the container alive on platforms that expect a long-lived process. Set KEEP_ALIVE=false to have the script exit 0 immediately after healthcheck (useful for CI tests).
- ENABLE_DB_VIEWER and RUN_IN_SEPARATE_CONTAINER both default to false. npm start in db_visualizer is a guarded no-op unless BOTH are true AND you run in a separate viewer container.
- Defensive guard: startup.sh prints a guard notice, and will not start Node; do NOT chain commands like `&& cd db_visualizer && npm start` after it in this container.
- The optional Node.js "db_visualizer" is provided for local diagnostics only and must NOT be auto-started from this container. Use a separate container/process; npm start inside this container will no-op and exit 0.
- Dry-run expectation: `sudo ./startup.sh && cd db_visualizer && npm start` will complete with exit code 0 and only print guard messages (no server starts).

## Structure
- schema/
  - 001_init.sql — tables, enums, constraints
  - 002_rbac_rls.sql — RLS policies and admin bypass
- ingestion/
  - ingest.py — idempotent ingestion script
  - mapping_specs.md — source-to-target mapping documentation
- .env.example — required environment variables for ingestion

## Requirements
- Supabase project (or PostgREST-compatible Postgres with auth extension)
- Python 3.10+
- pip packages: pandas, openpyxl, python-dotenv, requests

Install dependencies:
```
pip install -r requirements.txt
```

## Apply schema
Use psql against your Supabase/Postgres database:
```
psql "$POSTGRES_URL" -f schema/001_init.sql
psql "$POSTGRES_URL" -f schema/002_rbac_rls.sql
```

For Supabase, you can also paste these files as SQL migrations in the SQL editor.

Note: Set up at least one user profile row for your admin user in `users` table and mark `is_admin = true` to manage catalog data through the app:
```
INSERT INTO public.users (id, email, full_name, is_admin)
VALUES ('<auth.uid()>', 'admin@example.com', 'Admin', true)
ON CONFLICT (id) DO UPDATE SET is_admin = EXCLUDED.is_admin;
```

## Ingestion
1) Copy `.env.example` to `.env` and fill:
- SUPABASE_URL
- SUPABASE_SERVICE_ROLE_KEY

2) Run:
```
python ingestion/ingest.py --attachments-dir ../../attachments
```

The script will:
- Upsert roles and role descriptions
- Upsert competencies and role_competencies with levels and weights
- Upsert role_adjacency edges
- Upsert role_cards parsed from Role_Card_*.txt
- Log run status to `ingestion_runs`

Re-running is safe (idempotent upserts).

## Notes
- RLS is enabled. The ingestion uses the service role key to bypass RLS.
- Catalog tables (roles, competencies, mappings) are readable by any authenticated user.
- User-owned tables (plans, goals, user_competencies) restricted to `auth.uid()`; admins bypass via `users.is_admin`.
- A helper view `vw_user_role_gaps` provides a simple evidence gap check comparing self_level vs required_level.

## Troubleshooting
- Ensure your Supabase service role key is set. If unauthorized errors occur, verify the key and the REST URL.
- For header variations in spreadsheets, the parser supports common variants; inspect `mapping_specs.md` for expected columns.
- Readiness/health is strictly PostgreSQL on ${PGPORT:-5000}. Verify with:
  - ./healthcheck.sh (prints host:port)
  - pg_isready -h 127.0.0.1 -p ${PGPORT:-5000}
  - psql "postgresql://appuser:dbuser123@127.0.0.1:${PGPORT:-5000}/myapp" -c "SELECT 1;"
- There should be no checks on port 3020. If your platform expects a metadata file, see EXPOSED_PORTS which outputs ${PGPORT:-5000}.

