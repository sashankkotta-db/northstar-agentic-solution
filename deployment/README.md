# Deployment — NorthStar Brand Copilot

Deploys the LangGraph agent **inside a Databricks App** (ResponsesAgent + AgentServer via
Asset Bundles) — the latest docs-recommended pattern. No Model Serving endpoint.

## Single config file

All deploy-time values live in **one** place — `deployment/config.env`. Both scripts source
it, and it exports the `BUNDLE_VAR_*` variables that `agent_app/databricks.yml`'s `${var.*}`
placeholders read. You never edit `databricks.yml` or `app.yaml` by hand.

```bash
cp deployment/config.env.example deployment/config.env
# then edit deployment/config.env and fill in:
#   DATABRICKS_PROFILE, CATALOG, WAREHOUSE_ID, GENIE_SPACE_ID, EXPERIMENT_ID
#   (SCHEMA, LAKEBASE_INSTANCE_NAME, MODEL_ENDPOINT, EMBEDDING_ENDPOINT have working defaults)
```

`config.env` is gitignored, so your real workspace IDs never get committed.

> Prefer not to use a file? You can pass the same values inline instead:
> `databricks bundle deploy --var="catalog=...,warehouse_id=...,genie_space_id=...,experiment_id=..."`

## Prerequisites
- Databricks CLI authenticated to the profile you put in `config.env` (`databricks auth profiles`).
- Setup phases 1–5 complete: tables, Vector Search index, Genie space, Lakebase instance, and an
  MLflow experiment — these produce the IDs you paste into `config.env`.

## Steps
```bash
# 1. Configure once
cp deployment/config.env.example deployment/config.env   # then edit it

# 2. Deploy + start the app
bash deployment/deploy.sh

# 3. Grant the app's service principal data + Lakebase access
bash deployment/grant_resources.sh
```

`deploy.sh` sources `config.env`, validates required values, then runs
`databricks bundle validate → deploy → run` against `agent_app/` and prints the app URL +
service-principal client id.

`grant_resources.sh` grants the SP:
- **A.** UC `USAGE` on the catalog/schema + `SELECT` on the tables (Genie runs SQL as the SP).
- **B.** `CAN_USE` on the SQL warehouse.
- **C.** A Lakebase Postgres role + grants on the `AsyncDatabricksStore` memory tables
  (submitted as a Databricks job via `grant_lakebase.py`, since it needs `databricks_ai_bridge`).
  The workspace path is derived from the authenticated user — no hardcoded paths.

The bundle itself (via `agent_app/databricks.yml` `resources:`) already grants the SP `CAN_QUERY`
on the LLM + embedding endpoints, `CAN_RUN` on the Genie space, `SELECT` on the Vector Search index,
and `CAN_CONNECT_AND_CREATE` on the Lakebase instance.

## Bundle variables reference
Defined in `agent_app/databricks.yml` under `variables:`. Set via `config.env` (recommended),
`--var="name=value"`, or `BUNDLE_VAR_<name>` env vars. Variables without a default are required.

| Variable | Required | Default | Used for |
|---|---|---|---|
| `catalog` | ✅ | — | UC catalog (env `VS_CATALOG` + VS index grant) |
| `warehouse_id` | ✅ | — | SQL warehouse (env `WAREHOUSE_ID` + `CAN_USE` grant) |
| `genie_space_id` | ✅ | — | Genie space (env `GENIE_SPACE_ID` + `CAN_RUN` grant) |
| `experiment_id` | ✅ | — | MLflow experiment (resource grant; env auto-injected) |
| `schema` | — | `northstar_cpg` | schema within the catalog |
| `lakebase_instance_name` | — | `northstar-lakebase` | Lakebase memory instance |
| `model_endpoint` | — | `databricks-claude-sonnet-4-5` | agent LLM endpoint |
| `embedding_endpoint` | — | `databricks-gte-large-en` | Vector Search embeddings |

## Test the deployed app
```bash
TOKEN=$(databricks auth token --profile "$DATABRICKS_PROFILE" | jq -r '.access_token')
curl -X POST <app-url>/invocations \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"input":[{"role":"user","content":"Which trade promotions had negative ROI last quarter?"}],
       "custom_inputs":{"user_id":"you@example.com"}}'
```

## Notes
- Apps are queryable only via **OAuth token** (not PAT).
- `bundle run` is required after `deploy` to start the app with new code.
- The chat UI is cloned + built at app startup on the Databricks side.
- Re-run `grant_resources.sh` once after the first agent invocation if the Lakebase store tables
  didn't exist yet at grant time.
