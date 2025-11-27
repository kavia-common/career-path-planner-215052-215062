# Change Log — Fix Node.js MODULE_NOT_FOUND in database container

Date: 2025-11-27

Summary:
- Ensured the career_planner_database container starts ONLY PostgreSQL and essential init scripts.
- Removed any implication to start the Node.js db viewer from the DB container and documented optional use separately.

Changes:
- startup.sh: Clarified that only Postgres starts; viewer not started here.
- README.md (db root): Added "Important" note clarifying container behavior.
- db_visualizer/README.md: New file with local usage instructions and explicit guidance not to auto-start in DB container.
- db_visualizer/server.js: Header comment clarifying standalone, optional tool.
- Procfile: Added a no-op web process to prevent accidental Node startup by generic process managers.

Notes:
- Existing PostgreSQL initialization, port (5000), and pg_hba.conf warnings remain unchanged.
- If you want to use the viewer, run `npm install && npm start` inside `career_planner_database/db_visualizer` on your local machine or a separate helper container.
