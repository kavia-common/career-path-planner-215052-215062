# Career Planner Database (Supabase/Postgres)

This folder contains the database schema, row-level security (RLS), and a data ingestion utility to seed catalog data (roles, competencies, mappings, adjacency, and role cards) from the provided attachments.

Important:
- This container starts ONLY PostgreSQL and essential init scripts (see startup.sh).
- Healthcheck: use ./healthcheck.sh (psql ping). The container should exit non-zero only if PostgreSQL fails, never due to Node.
- The optional Node.js "db_visualizer" is provided for local diagnostics and must NOT be auto-started from this container. If needed, run it manually from career_planner_database/db_visualizer in a separate process/container.

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

