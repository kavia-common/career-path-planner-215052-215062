# Simple DB Viewer (Optional)

This folder contains a simple Node.js-based database viewer intended for local development diagnostics only.

Important:
- The career_planner_database container MUST NOT start this viewer. The database container should only start PostgreSQL and its init scripts.
- ENABLE_DB_VIEWER defaults to false and is ignored by this container. Even if set true, the DB container will SKIP starting Node.
- If you need to use the viewer locally, run it outside of the database container (or in a separate helper container).

How to use locally (optional):
1) Ensure Node.js >= 18 is installed.
2) From this directory:
   npm install
   # optional: sets POSTGRES_* env vars for local viewer
   source ./postgres.env
   npm start
3) Open http://localhost:3000 and select "postgres".

Notes:
- The viewer requires 'express' and other dependencies listed in package.json. You must run `npm install` successfully before `npm start`.
- If you see "MODULE_NOT_FOUND: './lib/express'", node_modules is missing or you ran from the wrong directory. Run npm install here.
- Do not modify the database container to start this viewer automatically.
- To use in a dedicated helper container, create a separate Dockerfile that runs only Node here; do not extend the DB container.
