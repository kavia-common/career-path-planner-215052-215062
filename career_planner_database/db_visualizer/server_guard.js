#!/usr/bin/env node
// PUBLIC_INTERFACE
/**
 * Guarded start entry for the optional DB viewer.
 * Behavior:
 * - If ENABLE_DB_VIEWER !== 'true' OR RUN_IN_SEPARATE_CONTAINER !== 'true', print message and exit 0 (no-op).
 * - This prevents accidental startup within the database container.
 * - Even if both are true, this script still warns to run in a separate container/process.
 */
const enable = String(process.env.ENABLE_DB_VIEWER || 'false').toLowerCase() === 'true';
const separate = String(process.env.RUN_IN_SEPARATE_CONTAINER || 'false').toLowerCase() === 'true';

if (!enable || !separate) {
  console.log('[db_visualizer] Disabled. To enable, set ENABLE_DB_VIEWER=true AND RUN_IN_SEPARATE_CONTAINER=true in a dedicated viewer container. No-op exit 0.');
  process.exit(0);
}

// Additional hard safety for this DB container: always no-op.
console.log('[db_visualizer] Guard: Even with flags true, this career_planner_database container will not start the viewer. Start it in a separate container/process from db_visualizer directory.');
process.exit(0);
