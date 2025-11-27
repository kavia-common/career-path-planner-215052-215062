# Simple DB Viewer (Optional)

This folder contains a simple Node.js-based database viewer intended for local development diagnostics only.

Important:
- The career_planner_database container MUST NOT start this viewer. The database container should only start PostgreSQL and its init scripts.
- If you need to use the viewer locally, run it outside of the database container (or in a separate helper container).

How to use locally (optional):
1) Ensure Node.js >= 18 is installed.
2) From this directory:
   npm install
   source ./postgres.env   # optional: sets POSTGRES_* env vars for local viewer
   npm start
3) Open http://localhost:3000 and select "postgres".

Notes:
- The viewer requires 'express' and other dependencies which are listed in package.json.
- If you see "MODULE_NOT_FOUND: './lib/express'", you are likely not in this folder or node_modules is missing. Run npm install in this directory.
- Do not modify the database container to start this viewer automatically.
