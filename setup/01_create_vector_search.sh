#!/usr/bin/env bash
# Phase 2 — Create the Vector Search endpoint + Delta-synced index for NorthStar Brand Copilot.
#
# Indexes the authored unstructured docs in `...northstar_cpg.documents` (1 vector per doc,
# embedding the whole `content` column via managed embeddings). The non-content columns
# (doc_type, title, brand, category, last_updated) are synced as retrievable metadata.
#
# Prereqs: Phase 1 complete (documents table exists with Change Data Feed enabled),
#          databricks CLI authenticated to the profile below.
#
# Usage:  bash setup/01_create_vector_search.sh
set -euo pipefail

PROFILE="YOUR_WORKSPACE"
CATALOG="REPLACE_WITH_CATALOG"
SCHEMA="northstar_cpg"
ENDPOINT="northstar_vs"
INDEX="${CATALOG}.${SCHEMA}.documents_index"
EMBEDDING_ENDPOINT="databricks-gte-large-en"   # managed embeddings, 1024 dims

echo "==> 1. Create the Vector Search endpoint (STANDARD)"
databricks vector-search-endpoints create-endpoint "$ENDPOINT" STANDARD --profile="$PROFILE" \
  || echo "   (endpoint may already exist — continuing)"

echo "==> 2. Create the Delta-synced index over the documents table"
cat > /tmp/vs_index.json <<JSON
{
  "name": "${INDEX}",
  "endpoint_name": "${ENDPOINT}",
  "primary_key": "doc_id",
  "index_type": "DELTA_SYNC",
  "delta_sync_index_spec": {
    "source_table": "${CATALOG}.${SCHEMA}.documents",
    "pipeline_type": "TRIGGERED",
    "embedding_source_columns": [
      { "name": "content", "embedding_model_endpoint_name": "${EMBEDDING_ENDPOINT}" }
    ]
  }
}
JSON
databricks vector-search-indexes create-index --json @/tmp/vs_index.json --profile="$PROFILE" \
  || echo "   (index may already exist — continuing)"

echo "==> 3. Wait until the index is READY (fresh STANDARD endpoints can take ~10-20 min)"
until databricks vector-search-indexes get-index "$INDEX" --profile="$PROFILE" 2>/dev/null \
      | python3 -c "import sys,json; sys.exit(0 if json.load(sys.stdin).get('status',{}).get('ready') else 1)"; do
  echo "   ...still provisioning/syncing"; sleep 30
done
echo "   READY."

echo "==> 4. Validate with a similarity query"
# NOTE: the CLI 'query-index' currently has a Go-SDK response-unmarshal bug, so we hit the
# REST endpoint directly via 'databricks api post' (returns 200 + raw JSON).
cat > /tmp/vs_query.json <<'JSON'
{"query_text":"what allergens are in Aurora oat milk and what do customers dislike about it",
 "columns":["doc_id","doc_type","title","content"],"num_results":4}
JSON
databricks api post \
  "/api/2.0/vector-search/indexes/${INDEX}/query" \
  --json @/tmp/vs_query.json --profile="$PROFILE" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin); da=d.get('result',{}).get('data_array',[]) or []
print(f'hits: {len(da)}')
for r in da: print(f'  [{r[1]}] {r[2]}  (score={round(float(r[-1]),3)})')
"

echo "DONE. Index ${INDEX} is ready on endpoint ${ENDPOINT}."
echo "MCP URL for the agent: <host>/api/2.0/mcp/vector-search/${CATALOG}/${SCHEMA}"
