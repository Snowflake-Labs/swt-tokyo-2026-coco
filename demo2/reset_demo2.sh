#!/usr/bin/env bash
# reset_demo2.sh — Cleanup and re-setup Demo 2 (Fraud Investigation)
# Usage: bash demo2/reset_demo2.sh
set -euo pipefail

CONN="${SNOWFLAKE_CONNECTION_NAME:?Set SNOWFLAKE_CONNECTION_NAME}"
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"

echo "=== Demo 2: Cleanup ==="
snow sql -c "$CONN" -f "$DIR/setup/99_cleanup.sql"

echo ""
echo "=== Demo 2: Re-setup (Snowflake objects) ==="
snow sql -c "$CONN" -f "$DIR/setup/00_account_prerequisites.sql"
snow sql -c "$CONN" -f "$DIR/setup/01_create_tables.sql"
snow sql -c "$CONN" -f "$DIR/setup/02_create_transformation_layer.sql"
snow sql -c "$CONN" -f "$DIR/setup/03_create_feature_store.sql"
snow sql -c "$CONN" -f "$DIR/setup/04_create_model_objects.sql"

echo ""
echo "=== Demo 2: Generate synthetic data (with drift) ==="
uv run python "$DIR/scripts/generate_synthetic_data.py" --backdate-days 60

echo ""
echo "=== Demo 2: Upload data ==="
uv run python "$DIR/scripts/upload_data.py"

echo ""
echo "NOTE: Run notebook demo2/notebooks/02_train_fraud_model.ipynb for:"
echo "  - XGBoost training"
echo "  - Model Registry registration"
echo "  - mv.run() batch inference → FRAUD_SCORES"
echo ""
echo "After notebook completes:"
echo "  snow sql -c $CONN -f $DIR/setup/05_create_agent_objects.sql"
echo "  snow sql -c $CONN -f $DIR/setup/06_create_model_monitor.sql"
echo ""
echo "Demo 2 partial reset complete. Finish by running the notebook + agent setup."
