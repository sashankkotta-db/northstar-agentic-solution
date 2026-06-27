#!/usr/bin/env bash
# Deploy the NorthStar Brand Copilot agent to Databricks Apps (Asset Bundle).
#
# This is the latest docs-recommended deployment: the LangGraph agent runs INSIDE the
# Databricks App (ResponsesAgent + AgentServer), deployed via DABs. No Model Serving endpoint.
#
# All deploy-time values come from deployment/config.env (copy it from
# config.env.example and fill it in). This script sources that file, which exports
# the BUNDLE_VAR_* variables that databricks.yml's ${var.*} placeholders read.
#
# Usage:  bash deployment/deploy.sh
# NOTE: `uv run preflight` is intentionally skipped — it starts the server locally, which
#       requires pypi access this environment doesn't have. The app installs deps on the
#       Databricks side at runtime.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/config.env"
if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: $CONFIG not found." >&2
  echo "  Copy the template and fill in your values:" >&2
  echo "    cp deployment/config.env.example deployment/config.env" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG"

# Required values (friendly errors instead of a cryptic bundle failure)
PROFILE="${DATABRICKS_PROFILE:?set DATABRICKS_PROFILE in deployment/config.env}"
: "${BUNDLE_VAR_catalog:?set CATALOG in deployment/config.env}"
: "${BUNDLE_VAR_warehouse_id:?set WAREHOUSE_ID in deployment/config.env}"
: "${BUNDLE_VAR_genie_space_id:?set GENIE_SPACE_ID in deployment/config.env}"
: "${BUNDLE_VAR_experiment_id:?set EXPERIMENT_ID in deployment/config.env}"

APP_DIR="$(cd "$SCRIPT_DIR/../agent_app" && pwd)"
APP_NAME="northstar-brand-copilot"
RESOURCE_KEY="agent_langgraph"

# Databricks Apps reads its runtime env from app.yaml in the deployed source — NOT from
# the databricks.yml `config.env` block (that only drives resources/grants). app.yaml is
# committed with REPLACE_WITH_* placeholders so no real IDs live in git; inject the real
# values from config.env for this deploy only, and restore the placeholders on exit.
APP_YAML="$APP_DIR/app.yaml"
: "${GENIE_SPACE_ID:?set GENIE_SPACE_ID in deployment/config.env}"
: "${CATALOG:?set CATALOG in deployment/config.env}"
: "${WAREHOUSE_ID:?set WAREHOUSE_ID in deployment/config.env}"
# Back up the placeholder app.yaml OUTSIDE the repo (mktemp) and restore it on exit, so the
# committed file never retains real IDs and no backup is left in the working tree.
APP_YAML_BAK="$(mktemp)"
cp "$APP_YAML" "$APP_YAML_BAK"
trap 'cp -f "$APP_YAML_BAK" "$APP_YAML"; rm -f "$APP_YAML_BAK"' EXIT
# perl -i is portable across macOS (BSD) and Linux (GNU); `sed -i ''` is BSD-only.
GENIE_SPACE_ID="$GENIE_SPACE_ID" CATALOG="$CATALOG" WAREHOUSE_ID="$WAREHOUSE_ID" \
perl -i -pe '
  s/\QREPLACE_WITH_GENIE_SPACE_ID\E/$ENV{GENIE_SPACE_ID}/g;
  s/\QREPLACE_WITH_CATALOG\E/$ENV{CATALOG}/g;
  s/\QREPLACE_WITH_WAREHOUSE_ID\E/$ENV{WAREHOUSE_ID}/g;
' "$APP_YAML"
echo "==> 0. Injected runtime env into app.yaml from config.env (placeholders restored on exit)"

cd "$APP_DIR"
echo "==> 1. Validate bundle (profile: $PROFILE)"
databricks bundle validate --profile="$PROFILE"

echo "==> 2. Deploy bundle (uploads code, creates app + service principal, applies resource grants)"
databricks bundle deploy --profile="$PROFILE"

echo "==> 3. Run the app (starts/restarts with the uploaded code) — REQUIRED"
databricks bundle run "$RESOURCE_KEY" --profile="$PROFILE"

echo "==> 4. App details"
databricks apps get "$APP_NAME" --profile="$PROFILE" --output json \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('URL:', d.get('url')); print('SP client id:', d.get('service_principal_client_id')); print('status:', (d.get('app_status') or {}).get('state'))"

echo ""
echo "NEXT: grant the app service principal access to data + Lakebase:"
echo "  bash deployment/grant_resources.sh"
