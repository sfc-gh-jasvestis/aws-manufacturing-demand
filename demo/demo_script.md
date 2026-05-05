# Demo Script: Demand Forecast Optimization
## ~70-second walkthrough — AWS + Snowflake

---

## The Story
Electronics forecast accuracy at 56% — well below the 85% target. 156 SKUs at stockout risk. $85M of inventory at risk. Find the gap before the next stockout.

---

## Personas

| Persona | Tool | What they care about |
|---|---|---|
| Demand Planner | Streamlit on Snowflake | Per-SKU accuracy, stockout/overstock, demand signals |
| Operations COO | Amazon QuickSight + Amazon Q | Category accuracy trends, value-at-risk, capital tied up |

---

## Script

### [0:00–0:10] HOOK
> "Electronics forecast accuracy at 56% — target is 85%. 156 SKUs at stockout risk. $85M of inventory tied up. Let's see what's happening."

### [0:10–0:35] SNOWFLAKE — STREAMLIT
> Open `MANUFACTURING_DEMAND.APP.DEMAND_OPTIMIZATION_APP`.
> "Overview — red banner shows the Electronics gap. Forecast Accuracy page: weekly accuracy line by category, only Electronics drops below the 85% target. Inventory Health: four risk levels — STOCKOUT, LOW, HEALTHY, OVERSTOCK — and a Value at Risk by Category bar with Pharma the largest at $46M. Three Dynamic Tables refresh every five minutes."

### [0:35–0:50] CORTEX AI
> "Ask the Data: 'How many SKUs are at stockout risk?' Cortex Analyst returns 156. Snowflake ML.FORECAST and ANOMALY_DETECTION models run natively on the same data — no separate ML platform, no data movement."

### [0:50–1:05] AWS
> "QuickSight `mfg-demand-dashboard`: KPIs for accuracy, stockout, overstock, value-at-risk; trend line by category, value-at-risk by category. S3 stage `s3://sg-manufacturing-demos-2026/demand/` archives raw forecasts and POs. Amazon Q topic `mfg-demand-q`: the COO asks 'Which category has the lowest forecast accuracy?' from any device."

### [1:05–1:10] CLOSE
> "From RAW data in S3 to Snowflake Dynamic Tables to Streamlit and QuickSight — one pipeline, two audiences."

---

## Pre-Recording Checklist
- [ ] Verify Electronics avg accuracy ~56% in `FORECAST_ACCURACY`
- [ ] Verify 4 risk levels populated in `INVENTORY_HEALTH`
- [ ] Verify VAR spread across all 5 categories
- [ ] Open https://app.snowflake.com/SFSEAPAC/sg_demo43/#/streamlit-apps/MANUFACTURING_DEMAND.APP.DEMAND_OPTIMIZATION_APP
- [ ] Open https://us-west-2.quicksight.aws.amazon.com/sn/dashboards/mfg-demand-dashboard
