#!/usr/bin/env bash
# reset_demo1.sh — Cleanup and re-setup Demo 1 (Impact Radar)
# Usage: bash demo1/reset_demo1.sh
set -euo pipefail

CONN="${SNOWFLAKE_CONNECTION_NAME:?Set SNOWFLAKE_CONNECTION_NAME}"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Demo 1: Cleanup ==="
snow sql -c "$CONN" -f "$DIR/setup/99_cleanup.sql"

echo ""
echo "=== Demo 1: Re-setup ==="
snow sql -c "$CONN" -f "$DIR/setup/01_staging_tables.sql"
snow sql -c "$CONN" -f "$DIR/setup/02_marts.sql"
snow sql -c "$CONN" -f "$DIR/setup/03_semantic_view.sql"
snow sql -c "$CONN" -f "$DIR/setup/04_agent.sql"

echo ""
echo "=== Demo 1: Verify lineage ==="
snow sql -c "$CONN" -f "$DIR/setup/05_verify_lineage.sql"

echo ""
echo "=== Demo 1: Reset git demo file ==="
git checkout -- "$DIR/demo/sql/fct_orders.sql" 2>/dev/null || true

echo ""
echo "Demo 1 reset complete."
