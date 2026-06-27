# Databricks notebook source
# MAGIC %md
# MAGIC # Grant Lakebase Postgres role + memory-store grants to the app service principal
# MAGIC Runs on Databricks (needs databricks_ai_bridge from pypi). Parameters: sp_client_id, instance_name.
# MAGIC Mirrors the template's scripts/grant_lakebase_permissions.py for memory_type=langgraph.

# COMMAND ----------
# MAGIC %pip install -U "databricks-langchain[memory]" databricks-ai-bridge --quiet
# COMMAND ----------
dbutils.library.restartPython()

# COMMAND ----------
dbutils.widgets.text("sp_client_id", "")
dbutils.widgets.text("instance_name", "northstar-lakebase")
SP = dbutils.widgets.get("sp_client_id")
INSTANCE = dbutils.widgets.get("instance_name")
assert SP, "sp_client_id is required"

from databricks_ai_bridge.lakebase import (
    LakebaseClient, SchemaPrivilege, SequencePrivilege, TablePrivilege,
)

# AsyncDatabricksStore (langgraph long-term memory) tables live in the public schema.
STORE_TABLES = [
    "store", "store_vectors", "store_migrations", "vector_migrations",
    "checkpoints", "checkpoint_writes", "checkpoint_blobs", "checkpoint_migrations",
]

with LakebaseClient(instance_name=INSTANCE) as client:
    print(f"Instance: {INSTANCE} | SP: {SP}")
    try:
        client.create_role(SP, "SERVICE_PRINCIPAL")
        print("Role created.")
    except Exception as e:
        print("create_role:", e)

    try:
        client.grant_schema(grantee=SP, schemas=["public"],
                            privileges=[SchemaPrivilege.USAGE, SchemaPrivilege.CREATE])
    except Exception as e:
        print("grant_schema:", e)

    try:
        client.grant_table(grantee=SP, tables=[f"public.{t}" for t in STORE_TABLES],
                           privileges=[TablePrivilege.SELECT, TablePrivilege.INSERT,
                                       TablePrivilege.UPDATE, TablePrivilege.DELETE])
    except Exception as e:
        print("grant_table (ok if tables not created yet):", e)

    try:
        client.grant_all_sequences_in_schema(grantee=SP, schemas=["public"],
            privileges=[SequencePrivilege.USAGE, SequencePrivilege.SELECT, SequencePrivilege.UPDATE])
    except Exception as e:
        print("grant_sequences:", e)

print("DONE. If table grants warned (tables not yet created), re-run after first agent use.")
