# Change Log — Fix Node.js MODULE_NOT_FOUND in database container

Date: 2025-11-27

Summary:
- Ensured the career_planner_database container starts ONLY PostgreSQL and essential init scripts.
- Removed any implication to start the Node.js db viewer from the DB container and documented optional use separately.
- Made startup.sh idempotent: if Postgres already running, skip start and perform healthcheck (exit 0 on success).

Changes:
- startup.sh: PostgreSQL-only; idempotent; clear exit codes (fail only if Postgres unhealthy/not found). ENABLE_DB_VIEWER defaults to false and is ignored; never starts Node.
- README.md (db root): Expanded Important notes with idempotency and viewer behavior.
- db_visualizer/README.md: Clarified optional local usage and mandatory `npm install` before `npm start`; reiterated it is never auto-started by DB container.
- db_visualizer/server.js: Header comment clarifying standalone, optional tool.
- Procfile: Left intentionally empty to prevent any process manager from starting Node/web.
- healthcheck.sh: Minimal psql-based healthcheck (public interface).
- .env.example: Added sample envs including ENABLE_DB_VIEWER=false.
- verify_startup_idempotent.sh: Helper script to validate idempotent behavior and ensure no Node process starts.

Notes:
- Existing PostgreSQL initialization and port (5000) defaults remain unchanged.
- If you want to use the viewer, run `npm install && npm start` inside `career_planner_database/db_visualizer` on your local machine or a separate helper container; failures to install should not affect DB container health.
