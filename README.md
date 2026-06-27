# NorthStar Brand Copilot — CPG AI Agent on Databricks

An end-to-end demo of **authoring & deploying an AI agent on Databricks**, for the **Consumer Packaged Goods** industry. A LangGraph agent ("NorthStar Brand Copilot") helps CPG brand & sales teams by routing each question to the right Databricks-native tool:

- **Vector Search** — RAG over product specs, consumer reviews, brand guidelines, trade-promo playbook, competitive briefs
- **Genie** — NL→SQL over sales (sell-in/sell-out), trade promotions & ROI, inventory, distribution, market share
- **Lakebase** — long-term memory (decisions, action items) with semantic recall

Built with the latest docs-recommended pattern: **MLflow `ResponsesAgent` + AgentServer running inside a Databricks App**, deployed via **Asset Bundles**, powered by **Claude Sonnet 4.5**, traced & evaluated with **MLflow**.

> See **[DEMO_SCRIPT.md](DEMO_SCRIPT.md)** for the presenter walkthrough and **[PLAN.md](PLAN.md)** for the design.

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

> **All deployment values are configured in one file:** `deployment/config.env`
> (copy from `config.env.example`). See **[deployment/README.md](deployment/README.md)**.

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
deployment/        deploy.sh, grant_resources.sh, grant_lakebase.py, README.md
DEMO_SCRIPT.md     presenter walkthrough
PLAN.md            design & decisions
```

## Rebuild order
1. **Data** — run `data_generation/generate_cpg_data_databricks.py` as a Databricks notebook/job → tables in `…northstar_cpg`.
2. **Vector Search** — `bash setup/01_create_vector_search.sh`.
3. **Genie** — `python3 setup/02_create_genie_space.py` then `databricks genie create-space --json @/tmp/genie_space.json`.
4. **Lakebase** — create instance `northstar-lakebase`; run `setup/03_lakebase_setup.py` as a notebook.
5. **Configure + Deploy** — copy `deployment/config.env.example` → `deployment/config.env` and fill in your IDs (catalog, warehouse, Genie space, experiment), then `bash deployment/deploy.sh` followed by `bash deployment/grant_resources.sh`. Every deploy-time variable lives in that one file.
6. **(Optional) Evaluate / traces** — run `setup/08_agent_eval.py` and `setup/07_trace_demo.py` as notebooks.

> **Environment note:** this build ran on a machine with **no pypi/npm egress**, so Python-dependent steps run **on Databricks** (notebook/job) rather than locally; the CLI/bundle steps run locally. See PLAN.md and the in-repo notes.

## Validated results
- All 3 capabilities work on the live app (Genie, Vector Search, Lakebase memory).
- MLflow Agent Evaluation: **Safety 1.0 · Relevance 0.9 · Correctness 0.8** (10-question CPG eval set).
- Detailed routing traces (Genie vs. Vector Search) in experiment `REPLACE_WITH_EXPERIMENT_ID`.

## Known limitation
Live-app MLflow **trace upload** is blocked by a Databricks Apps storage-egress restriction in this FEVM workspace (`Connection refused` to the trace artifact store). The agent is unaffected; use `setup/07_trace_demo.py` (cluster has egress) for the trace reveal.
