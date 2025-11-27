# Change Log — Fix Node.js MODULE_NOT_FOUND in database container

Date: 2025-11-27

Summary:
- Ensured the career_planner_database container starts ONLY PostgreSQL and essential init scripts.
- Removed any implication to start the Node.js db viewer from the DB container and documented optional use separately.

Changes:
- startup.sh: Clarified that only Postgres starts; viewer not started here. Added ENABLE_DB_VIEWER=false guard (default) and a psql healthcheck that exits non-zero if Postgres is unhealthy.
- README.md (db root): Added "Important" note clarifying container behavior.
- db_visualizer/README.md: Local usage instructions updated with guard note; explicit guidance not to auto-start in DB container.
- db_visualizer/server.js: Header comment clarifying standalone, optional tool.
- Procfile: Emptied to prevent any process manager auto-detection or accidental Node/web start.
- healthcheck.sh: New minimal psql-based healthcheck script.

Notes:
- Existing PostgreSQL initialization, port (5000), and pg_hba.conf warnings remain unchanged.
- If you want to use the viewer, run `npm install && npm start` inside `career_planner_database/db_visualizer` on your local machine or a separate helper container.
