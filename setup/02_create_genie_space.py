#!/usr/bin/env python3
"""
Phase 3 — Build the Genie Space serialized payload for NorthStar Brand Copilot.

Generates /tmp/genie_space.json (the Create Genie Space request body) which is then
submitted with:
  databricks genie create-space --json @/tmp/genie_space.json --profile <profile>

serialized_space schema (version 2): config.sample_questions, data_sources.tables,
instructions.text_instructions + example_question_sqls. IDs are 32-char lowercase hex.
Arrays are pre-sorted (tables by identifier; id-keyed arrays by id).
"""
import json
import uuid

CAT = "REPLACE_WITH_CATALOG"
SCH = "northstar_cpg"
WAREHOUSE_ID = "REPLACE_WITH_WAREHOUSE_ID"
PARENT_PATH = "/Users/you@example.com"
FQ = lambda t: f"{CAT}.{SCH}.{t}"          # noqa: E731
hexid = lambda: uuid.uuid4().hex            # 32-char lowercase hex  # noqa: E731

# --- data sources: the 7 structured tables (sorted by identifier) ---
TABLE_DESCS = {
    "distribution": "Weekly ACV% distribution and store counts by product and retailer.",
    "inventory": "Weekly on-hand units and weeks-of-supply by product and retailer.",
    "market_share": "Monthly brand dollar sales and dollar share within each category.",
    "products": "Product/SKU master: brand, category, subcategory, list price, unit cogs, allergens, claims.",
    "retailers": "Retailer accounts: channel (Mass/Grocery/Club/Drug/Convenience/eCommerce), region, store count.",
    "sales_facts": "Weekly sell-in (units_shipped, shipment_revenue) and sell-out (units_sold, pos_revenue) by product and retailer, with on_promo flag.",
    "trade_promotions": "Trade promotion events with promo_type, discount_depth_pct, promo_spend, baseline/promoted/incremental units, lift_pct and incremental roi.",
}
tables = [{"identifier": FQ(t), "description": [TABLE_DESCS[t]]}
          for t in sorted(TABLE_DESCS)]

# --- text instructions (business semantics so NL->SQL is reliable) ---
TEXT_INSTRUCTIONS = [
    "NorthStar Brands is a multi-category CPG company (Snacks, Beverages, Personal Care). "
    "Join sales_facts/inventory/distribution/trade_promotions to products on product_id and to "
    "retailers on retailer_id. The weekly grain column is week_ending.",
    "Sell-in = shipments from NorthStar to the retailer: sales_facts.units_shipped and shipment_revenue. "
    "Sell-out = consumer purchases at point of sale: sales_facts.units_sold and pos_revenue.",
    "Sell-through rate is a sell-out / sell-in ratio: SUM(units_sold) / NULLIF(SUM(units_shipped),0). "
    "Express it as a ratio rounded to 3 decimals (or a percentage when asked).",
    "trade_promotions.roi is incremental ROI = (incremental gross profit - promo_spend) / promo_spend. "
    "roi < 0 means the promotion lost money. discount_depth_pct is the funded discount depth. "
    "Feature+Display events tend to be most profitable; BOGO and deep TPRs are often negative.",
    "market_share.dollar_share_pct = brand_dollar_sales / category_dollar_sales for a brand within a "
    "category, by month. ACV is distribution.acv_pct (all-commodity-volume weighted distribution).",
    "When the user says 'last quarter', use the most recent 13 weeks: "
    "week_ending >= (SELECT MAX(week_ending) FROM sales_facts) - INTERVAL 13 WEEKS. "
    "To filter by a product, join to products and filter products.product_name; "
    "to filter by a retailer, join to retailers and filter retailers.retailer_name.",
]
# API allows at most one text_instructions item; combine into a single instruction.
text_instructions = [{"id": hexid(), "content": ["\n".join(f"- {t}" for t in TEXT_INSTRUCTIONS)]}]

# --- example question -> SQL pairs (curated for the demo) ---
EXAMPLES = [
    (["What was the sell-through rate for Summit Protein Bars at Kroger over the last quarter?"],
     ["SELECT p.product_name, r.retailer_name, SUM(s.units_sold) AS units_sold, "
      "SUM(s.units_shipped) AS units_shipped, "
      "ROUND(SUM(s.units_sold)/NULLIF(SUM(s.units_shipped),0),3) AS sell_through_rate "
      "FROM sales_facts s JOIN products p ON s.product_id=p.product_id "
      "JOIN retailers r ON s.retailer_id=r.retailer_id "
      "WHERE p.product_name='Summit Protein Bars' AND r.retailer_name='Kroger' "
      "AND s.week_ending >= (SELECT MAX(week_ending) FROM sales_facts) - INTERVAL 13 WEEKS "
      "GROUP BY p.product_name, r.retailer_name"]),
    (["Which trade promotions had negative ROI last quarter?"],
     ["SELECT tp.promo_id, p.product_name, r.retailer_name, tp.promo_type, "
      "tp.discount_depth_pct, tp.promo_spend, tp.lift_pct, tp.roi "
      "FROM trade_promotions tp JOIN products p ON tp.product_id=p.product_id "
      "JOIN retailers r ON tp.retailer_id=r.retailer_id "
      "WHERE tp.roi < 0 AND tp.start_date >= "
      "(SELECT MAX(start_date) FROM trade_promotions) - INTERVAL 13 WEEKS "
      "ORDER BY tp.roi ASC"]),
    (["How has Aurora's dollar share in the Beverages category trended over time?"],
     ["SELECT month, dollar_share_pct FROM market_share "
      "WHERE brand='Aurora' AND category='Beverages' ORDER BY month"]),
    (["Which retailers have the lowest weeks of supply for Pulse Energy Drink?"],
     ["SELECT r.retailer_name, AVG(i.weeks_of_supply) AS avg_weeks_of_supply "
      "FROM inventory i JOIN products p ON i.product_id=p.product_id "
      "JOIN retailers r ON i.retailer_id=r.retailer_id "
      "WHERE p.product_name='Pulse Energy Drink' "
      "GROUP BY r.retailer_name ORDER BY avg_weeks_of_supply ASC"]),
]
example_question_sqls = [{"id": hexid(), "question": q, "sql": s} for q, s in EXAMPLES]
example_question_sqls.sort(key=lambda x: x["id"])

# --- sample questions surfaced in the UI ---
SAMPLE_QS = [
    ["What was the sell-through rate for Summit Protein Bars at Kroger last quarter?"],
    ["Which trade promotions had negative ROI last quarter?"],
    ["How has Aurora's dollar share in Beverages trended over the last year?"],
    ["Which retailers have the lowest weeks of supply for Pulse Energy Drink?"],
]
sample_questions = [{"id": hexid(), "question": q} for q in SAMPLE_QS]
sample_questions.sort(key=lambda x: x["id"])

serialized_space = {
    "version": 2,
    "config": {"sample_questions": sample_questions},
    "data_sources": {"tables": tables},
    "instructions": {
        "text_instructions": text_instructions,
        "example_question_sqls": example_question_sqls,
    },
}

request_body = {
    "warehouse_id": WAREHOUSE_ID,
    "title": "NorthStar Brand Copilot — Sales & Promotions",
    "description": "Genie space over NorthStar Brands CPG sales, promotions, inventory, "
                   "distribution and market-share data.",
    "parent_path": PARENT_PATH,
    "serialized_space": json.dumps(serialized_space),
}

with open("/tmp/genie_space.json", "w") as f:
    json.dump(request_body, f, indent=2)
print("Wrote /tmp/genie_space.json")
print(f"  tables: {len(tables)}, sample_questions: {len(sample_questions)}, "
      f"text_instructions: {len(text_instructions)}, example_sqls: {len(example_question_sqls)}")
