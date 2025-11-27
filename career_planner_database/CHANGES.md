# Change Log — Fix Node.js MODULE_NOT_FOUND in database container

Date: 2025-11-27

Summary:
- Ensured the career_planner_database container starts ONLY PostgreSQL and essential init scripts.
- Removed any implication to start the Node.js db viewer from the DB container and documented optional use separately.
- Made startup.sh idempotent: if Postgres already running, skip start and perform healthcheck (exit 0 on success).

Changes:
- startup.sh: PostgreSQL-only; idempotent; clear exit codes. Added defensive guard to prevent chained commands (e.g., `&& cd db_visualizer && npm start`) from running in this container context. ENABLE_DB_VIEWER is forced false.
- README.md (db root): Expanded Important notes with idempotency, viewer behavior, and defensive guard.
- db_visualizer/README.md: Clarified optional local usage and mandatory `npm install` before `npm start`; reiterated it is never auto-started by DB container.
- db_visualizer/server.js: Header comment clarifying standalone, optional tool.
- db_visualizer/start: No-op guard script that exits 0 unless ENABLE_DB_VIEWER=true (still advises not to run viewer here).
- db_visualizer/package.json: "start" now invokes server_guard.js which exits 0 unless ENABLE_DB_VIEWER=true AND RUN_IN_SEPARATE_CONTAINER=true, and still refuses to start in DB container.
- db_visualizer/server_guard.js: New defensive script; always exits 0 in DB container context.
- Procfile: Kept inert to avoid accidental Node/web starts.
- healthcheck.sh: Minimal psql-based healthcheck (public interface).
- .env.example: Added with ENABLE_DB_VIEWER=false and DISABLE_CHAINED_CMDS=true.
- verify_startup_idempotent.sh: Helper verifies no Node process starts.

Notes:
- Existing PostgreSQL initialization and port (5000) defaults remain unchanged.
- If you want to use the viewer, run `npm install && npm start` inside `career_planner_database/db_visualizer` on your local machine or a separate helper container; failures to install should not affect DB container health.
