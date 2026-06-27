#!/usr/bin/env bash
# Grant the deployed app's service principal the permissions it needs at runtime.
#
# The Asset Bundle already grants (via databricks.yml `resources:`):
#   - CAN_QUERY on the LLM + embedding serving endpoints
#   - CAN_RUN on the Genie space
#   - SELECT on the Vector Search index (uc_securable)
#   - CAN_CONNECT_AND_CREATE on the Lakebase instance
#
# This script adds what the bundle can't express:
#   A. UC USAGE on catalog/schema + SELECT on the underlying tables (Genie executes SQL as the SP)
#   B. CAN_USE on the SQL warehouse (Genie needs a warehouse to run)
#   C. The Lakebase Postgres role for the SP + grants on the memory-store tables
#
# Usage:  bash deployment/grant_resources.sh
set -euo pipefail

PROFILE="YOUR_WORKSPACE"
APP_NAME="northstar-brand-copilot"
CATALOG="REPLACE_WITH_CATALOG"
SCHEMA="northstar_cpg"
WAREHOUSE_ID="REPLACE_WITH_WAREHOUSE_ID"
LAKEBASE_INSTANCE="northstar-lakebase"

SP=$(databricks apps get "$APP_NAME" --profile="$PROFILE" --output json \
     | python3 -c "import sys,json;print(json.load(sys.stdin)['service_principal_client_id'])")
echo "App service principal: $SP"

echo "==> A. UC grants (catalog/schema USAGE + table SELECT) via SQL"
# The SQL Statement API runs ONE statement per call, so issue each grant separately.
run_sql() {
  cat > /tmp/grant_uc.json <<JSON
{"warehouse_id":"${WAREHOUSE_ID}","statement":"$1","wait_timeout":"30s"}
JSON
  databricks api post /api/2.0/sql/statements --json @/tmp/grant_uc.json --profile="$PROFILE" \
    | python3 -c "import sys,json;s=json.load(sys.stdin).get('status',{});print('  ',s.get('state'),(s.get('error') or {}).get('message','')[:160])"
}
run_sql "GRANT USAGE ON CATALOG ${CATALOG} TO \`${SP}\`"
run_sql "GRANT USAGE ON SCHEMA ${CATALOG}.${SCHEMA} TO \`${SP}\`"
run_sql "GRANT SELECT ON SCHEMA ${CATALOG}.${SCHEMA} TO \`${SP}\`"

echo "==> B. Grant the SP CAN_USE on the SQL warehouse"
cat > /tmp/grant_wh.json <<JSON
{"access_control_list":[{"service_principal_name":"${SP}","permission_level":"CAN_USE"}]}
JSON
databricks api patch "/api/2.0/permissions/warehouses/${WAREHOUSE_ID}" --json @/tmp/grant_wh.json --profile="$PROFILE" >/dev/null \
  && echo "  warehouse CAN_USE granted"

echo "==> C. Lakebase Postgres role + memory-store grants (runs on Databricks via a job)"
echo "      See deployment/grant_lakebase.py (submitted as a serverless job by this script)."
WSDIR="/Users/you@example.com/northstar_cpg_build"
databricks workspace import "$WSDIR/grant_lakebase" \
  --file "$(cd "$(dirname "$0")" && pwd)/grant_lakebase.py" \
  --language PYTHON --format SOURCE --overwrite --profile="$PROFILE"
cat > /tmp/grant_lakebase_run.json <<JSON
{"run_name":"northstar_grant_lakebase","tasks":[{"task_key":"grant","notebook_task":{"notebook_path":"${WSDIR}/grant_lakebase","base_parameters":{"sp_client_id":"${SP}","instance_name":"${LAKEBASE_INSTANCE}"}}}]}
JSON
databricks jobs submit --json @/tmp/grant_lakebase_run.json --profile="$PROFILE" \
  | python3 -c "import sys,json;print('  lakebase grant run:', json.load(sys.stdin))"

echo "DONE. Re-run this after the first agent invocation if Lakebase store tables didn't exist yet."
