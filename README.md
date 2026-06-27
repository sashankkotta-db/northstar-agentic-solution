# NorthStar Brand Copilot — CPG AI Agent on Databricks

An end-to-end demo of **authoring & deploying an AI agent on Databricks**, for the **Consumer Packaged Goods** industry. A LangGraph agent ("NorthStar Brand Copilot") helps CPG brand & sales teams by routing each question to the right Databricks-native tool:

- **Vector Search** — RAG over product specs, consumer reviews, brand guidelines, trade-promo playbook, competitive briefs
- **Genie** — NL→SQL over sales (sell-in/sell-out), trade promotions & ROI, inventory, distribution, market share
- **Lakebase** — long-term memory (decisions, action items) with semantic recall

Built with the latest docs-recommended pattern: **MLflow `ResponsesAgent` + AgentServer running inside a Databricks App**, deployed via **Asset Bundles**, powered by **Claude Sonnet 4.5**, traced & evaluated with **MLflow**.

## Architecture
The app is a **single Databricks App with two tabs** — 📊 **Dashboard** (static CPG analytics, charts from a `/api/analytics` SQL endpoint) and 💬 **Assistant** (the agent chatbot via `/invocations`). One app, one URL, one deploy.

```
Databricks App (custom 2-tab UI: Dashboard + Assistant)  ── MLflow ResponsesAgent + autolog
        └─ LangGraph agent (Claude Sonnet 4.5)
              ├─ Vector Search index   (MCP)   → …northstar_cpg.documents_index
              ├─ Genie space           (MCP)   → space REPLACE_WITH_GENIE_SPACE_ID
              └─ Lakebase memory  (AsyncDatabricksStore) → instance northstar-lakebase
   Data + tools governed by Unity Catalog · traces/eval in MLflow experiment REPLACE_WITH_EXPERIMENT_ID
```

## Workspace / key resources
- Workspace profile: `YOUR_WORKSPACE`
- UC schema (all data/index): `REPLACE_WITH_CATALOG.northstar_cpg`
- App URL: https://YOUR_APP_URL.aws.databricksapps.com

> **All deploy-time values are configured in one gitignored file** — `deployment/config.env`
> (copy from `config.env.example`). See [Configuration](#configuration--scripts) below.

## Repo layout
```
data_generation/   generate_cpg_data_databricks.py  → 8 Delta tables (run-on-Databricks)
                   generate_cpg_data.py             → local Polars equivalent (reference)
setup/             01_create_vector_search.sh       → VS endpoint + Delta-sync index
                   02_create_genie_space.py         → Genie space (serialized payload)
                   03_lakebase_setup.py             → Lakebase schema/tables
                   05_validate_agent.py             → exercise agent integration paths
                   07_trace_demo.py                 → generate fully-detailed MLflow traces
                   08_agent_eval.py                 → MLflow Agent Evaluation (scorers)
                   09_eval_results.py               → aggregate eval assessments
agent_app/         the Databricks App (agent-langgraph template, customized)
                   agent_server/agent.py            → the agent (supervisor + tools)  ← main logic
                   databricks.yml, app.yaml         → bundle + resource grants
deployment/        deploy.sh, grant_resources.sh, grant_lakebase.py, config.env.example
```

## Deployment steps
1. **Data** — run `data_generation/generate_cpg_data_databricks.py` as a Databricks notebook/job → tables in `…northstar_cpg`.
2. **Vector Search** — `bash setup/01_create_vector_search.sh`.
3. **Genie** — `python3 setup/02_create_genie_space.py` then `databricks genie create-space --json @/tmp/genie_space.json`.
4. **Lakebase** — create instance `northstar-lakebase`; run `setup/03_lakebase_setup.py` as a notebook.
5. **Create `config.env`** — copy the template and fill in your IDs (profile, catalog, warehouse, Genie space, experiment). This one gitignored file is the single source for every deploy-time value:
   ```bash
   cp deployment/config.env.example deployment/config.env
   # then edit deployment/config.env and fill in:
   #   DATABRICKS_PROFILE, CATALOG, WAREHOUSE_ID, GENIE_SPACE_ID, EXPERIMENT_ID
   #   (SCHEMA, LAKEBASE_INSTANCE_NAME, MODEL_ENDPOINT, EMBEDDING_ENDPOINT have working defaults)
   ```
6. **Deploy the app, then grant access** — run both scripts in order (they read `config.env`):
   ```bash
   bash deployment/deploy.sh           # validates config.env, deploys the app bundle, starts the app
   bash deployment/grant_resources.sh  # grants the app's service principal UC + warehouse + Lakebase access
   ```
   > The dashboard graphs and the agent's Genie tool only work **after** `grant_resources.sh` completes.
7. **(Optional) Evaluate / traces** — run `setup/08_agent_eval.py` and `setup/07_trace_demo.py` as notebooks.

## Local development
The app (`agent_app/`) is a FastAPI + LangGraph server managed with [`uv`](https://docs.astral.sh/uv/). To run the 2-tab UI + agent on your machine:
```bash
cd agent_app
uv run quickstart --profile <your-databricks-profile>   # one-time: auth + generate .env
uv run start-app                                         # serve the Dashboard + Assistant locally
```
The agent's logic lives in `agent_app/agent_server/agent.py`.

## Configuration & scripts

**`config.env` is the single source of truth.** Both deploy scripts source it, and it exports the
`BUNDLE_VAR_*` variables that `agent_app/databricks.yml`'s `${var.*}` placeholders read — you never
edit `databricks.yml` or `app.yaml` by hand. It's gitignored, so real workspace IDs never get committed.

> Prefer not to use a file? Pass the same values inline:
> `databricks bundle deploy --var="catalog=...,warehouse_id=...,genie_space_id=...,experiment_id=..."`

**What each script does:**
- `deploy.sh` — sources `config.env`, validates required values, injects them into `app.yaml`, then runs
  `databricks bundle validate → deploy → run` against `agent_app/` and prints the app URL + SP client id.
- `grant_resources.sh` — grants the app's service principal: **(A)** UC `USAGE` on catalog/schema + `SELECT`
  on tables (Genie runs SQL as the SP), **(B)** `CAN_USE` on the SQL warehouse, **(C)** a Lakebase Postgres
  role + grants on the `AsyncDatabricksStore` memory tables (submitted as a Databricks job via `grant_lakebase.py`).
  The bundle itself already grants `CAN_QUERY` on the LLM/embedding endpoints, `CAN_RUN` on the Genie space,
  `SELECT` on the Vector Search index, and `CAN_CONNECT_AND_CREATE` on the Lakebase instance.

**Bundle variables** (in `agent_app/databricks.yml` under `variables:`; set via `config.env`, `--var`, or `BUNDLE_VAR_<name>`):

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

**Test the deployed app:**
```bash
TOKEN=$(databricks auth token --profile "$DATABRICKS_PROFILE" | jq -r '.access_token')
curl -X POST <app-url>/invocations \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"input":[{"role":"user","content":"Which trade promotions had negative ROI last quarter?"}],
       "custom_inputs":{"user_id":"you@example.com"}}'
```

**Notes:**
- Apps are queryable only via **OAuth token** (not PAT). `bundle run` is required after `deploy` to start the app.
- The chat UI is cloned + built at app startup on the Databricks side.
- Re-run `grant_resources.sh` once after the first agent invocation if the Lakebase store tables didn't exist yet at grant time.
