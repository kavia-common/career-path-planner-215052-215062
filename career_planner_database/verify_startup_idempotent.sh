#!/bin/bash
# PUBLIC_INTERFACE
# Helper to verify startup.sh idempotency behavior.
# - Runs healthcheck first (may fail if DB not up)
# - Runs startup.sh (should start Postgres or skip if already running)
# - Runs startup.sh again (should detect running and exit 0)
# - Confirms no Node processes are started from db_visualizer

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[verify] Running initial healthcheck (may fail if DB not up yet)..."
bash "${ROOT_DIR}/healthcheck.sh" || echo "[verify] Initial healthcheck failed (expected if DB not running)"

echo "[verify] First startup.sh run..."
bash "${ROOT_DIR}/startup.sh"

echo "[verify] Second startup.sh run (should be idempotent and exit 0)..."
bash "${ROOT_DIR}/startup.sh"

echo "[verify] Ensuring no Node viewer process was started..."
if pgrep -fa "node .*db_visualizer/server.js" >/dev/null 2>&1; then
  echo "[verify][ERROR] Detected Node viewer process unexpectedly."
  exit 3
fi
echo "[verify] No Node viewer process detected. OK."

echo "[verify] Final healthcheck..."
bash "${ROOT_DIR}/healthcheck.sh"

echo "[verify] Idempotent startup verification passed."
