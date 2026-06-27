# YOUR_WORKSPACE rebuild — resource IDs

Workspace: https://YOUR_WORKSPACE.cloud.databricks.com
Profile: YOUR_WORKSPACE
User: you@example.com

## Confirmed / created
- Catalog: `REPLACE_WITH_CATALOG` (managed, owned by me)
- Schema: `REPLACE_WITH_CATALOG.northstar_cpg` (created by data-gen job)
- LLM endpoint: `databricks-claude-sonnet-4-5` (exists)
- Embedding endpoint: `databricks-gte-large-en` (exists)
- Warehouse: `Shared Unity Catalog Serverless` id `REPLACE_WITH_WAREHOUSE_ID` (serverless PRO)
- MLflow experiment: `REPLACE_WITH_EXPERIMENT_ID` (/Users/you@example.com/northstar_cpg_experiment)
- Lakebase instance: `northstar-lakebase` (CU_1, pg_native_login=false / OAuth only)
- Data-gen job run_id: REDACTED

## Created
- Genie space_id: `REPLACE_WITH_GENIE_SPACE_ID`
- Lakebase rw_dns: `YOUR_LAKEBASE_RW_DNS` (copilot schema + 3 tables + seed row DONE)
- e2 bundle: build_e2/agent_app_e2/ (databricks.yml + app.yaml rewired, verified CLEAN of stale refs)

- VS endpoint: northstar_vs ; index: REPLACE_WITH_CATALOG.northstar_cpg.documents_index (READY, validated)
- App name: northstar-brand-copilot ; URL: https://YOUR_APP_URL.aws.databricksapps.com ; SP client id: REPLACE_WITH_SP_CLIENT_ID
- Scripts uploaded to: /Users/you@example.com/northstar_cpg/ (setup, data_generation, deployment, agent_app, build_e2)
- IP ACL note: workspace YOUR_WORKSPACE_ID has an IP allowlist; one SCIM call from REDACTED got 403 intermittently.
