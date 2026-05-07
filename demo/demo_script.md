# Demo Script: Demand Forecast Optimization
## ~3-Minute Recorded Walkthrough
**Format**: Screen recording with voiceover
**Target**: Customer meeting / booth loop / social share
**Pre-requisites**: Data loaded, Streamlit deployed, QuickSight dashboard published, Iceberg table populated, Glue catalog `mfg_demand_iceberg` registered

---

## Two Personas

| Persona | Role | Tool | What they care about |
|---|---|---|---|
| **Demand Planner** | Day-to-day SKU control | Streamlit in Snowflake | Per-SKU accuracy, stockout/overstock list, demand spikes, value-at-risk |
| **Operations COO** | Executive / financial owner | Amazon Athena + QuickSight + Amazon Q | Same forecast in AWS-native tools, no copy job, no separate SLA |

---

## What's Built

| Layer | Component | Detail |
|---|---|---|
| **Ingest (AWS)** | Amazon S3 | `s3://sg-manufacturing-demos-2026/demand/` — partner POS, supplier POs, demand feeds |
| **RAW** | 4 tables | PRODUCTS (500), WAREHOUSES (15), SALES_HISTORY (50K), PURCHASE_ORDERS (10K) |
| **CURATED** | 3 Dynamic Tables | FORECAST_ACCURACY, INVENTORY_HEALTH (2K), DEMAND_SIGNALS |
| **AI** | Semantic View + Agent | DEMAND_PLANNING_SEMANTIC_VIEW |
| **ML** | FORECAST + ANOMALY | 14-period demand forecast across 500 SKUs, anomaly flags on stockout/overstock |
| **AWS Hero** | Apache Iceberg + AWS Glue + Athena | `LAKE.FORECAST_ICEBERG` (2,000 rows) on S3, registered in Glue catalog `mfg_demand_iceberg`, queryable from Athena |
| **Consumption** | Streamlit | 7-page Demand Optimization App |
| | QuickSight | `mfg-demand-dashboard` (Snowflake direct + Athena variant) + Amazon Q topic `mfg-demand-q` |

---

## Pre-Recording Checklist

- [ ] `SELECT * FROM MANUFACTURING_DEMAND.LAKE.VW_FORECAST_ICEBERG_STATS` returns 2,000 rows, 5 categories, ~85% avg accuracy
- [ ] Electronics avg accuracy ~56% in `FORECAST_ACCURACY`
- [ ] 156 STOCKOUT rows in `INVENTORY_HEALTH`
- [ ] Pharma value-at-risk = $46M in `INVENTORY_HEALTH`
- [ ] Open Streamlit: https://app.snowflake.com/SFSEAPAC/sg_demo43/#/streamlit-apps/MANUFACTURING_DEMAND.APP.DEMAND_OPTIMIZATION_APP
- [ ] Open QuickSight: https://us-west-2.quicksight.aws.amazon.com/sn/dashboards/mfg-demand-dashboard
- [ ] Pre-open AWS tabs:
  - S3: `https://s3.console.aws.amazon.com/s3/buckets/sg-retail-demos-2026?prefix=iceberg/manufacturing-demand/forecast/`
  - Glue: `https://us-west-2.console.aws.amazon.com/glue/home?region=us-west-2#/v2/data-catalog/tables` (filter `mfg_demand_iceberg`)
  - Athena: `https://us-west-2.console.aws.amazon.com/athena/home?region=us-west-2` — paste-ready: `SELECT category, AVG(accuracy_pct) avg_acc, COUNT(*) rows FROM mfg_demand_iceberg.forecast_iceberg GROUP BY category ORDER BY avg_acc;`
- [ ] Audio: quiet room, external mic
- [ ] Resolution: 1920x1080

---

## Script

### [0:00–0:20] THE PROBLEM & ARCHITECTURE

**Show**: Streamlit Overview page

> "Electronics forecast accuracy at 56% — your target is 85%. 156 SKUs at stockout risk. Eighty-five million dollars of inventory tied up. Most demand-planning tools give you the dashboard. None of them give you the *forecast itself* in your AWS data lake without a nightly copy job. That's what we're going to fix in three minutes. Partner sales feeds and supplier POs land in **Amazon S3**. Snowflake builds curated demand tables with **Dynamic Tables**, runs **ML.FORECAST** natively — no Python, no infra — and writes the result back to your data lake as **Apache Iceberg**, registered in **AWS Glue**, queryable from **Athena**. One forecast, two consumption surfaces, zero copy."

### [0:20–0:45] PAGE 1: OVERVIEW + FORECAST ACCURACY

**Show**: Overview KPI strip + Forecast Accuracy weekly trend by category

**Tech**: Dynamic Tables + ML.FORECAST

> "Five categories, ten weeks. Apparel, Pharma, Food are tracking the 85% line. Electronics drops to 56% in week 8 — that's a forecast model breakdown, not a stocking error. The whole accuracy table refreshes every five minutes through one **Dynamic Table** SQL statement."

### [0:45–1:10] PAGE 2: INVENTORY HEALTH

**Show**: Risk pie + value-at-risk bar by category

**Tech**: ML.ANOMALY_DETECTION on `INVENTORY_HEALTH`

> "Four risk levels: STOCKOUT, LOW, HEALTHY, OVERSTOCK. 156 SKUs in stockout — that's the lost-revenue story. Pharma value-at-risk is $46M — that's the working-capital story. Same Dynamic Table; two different conversations with two different audiences."

### [1:10–1:50] PAGE 3: ICEBERG EXPORT — the AWS payoff

**Show**: Click `Iceberg Export (AWS Glue)` page

**Tech**: Apache Iceberg on S3 + AWS Glue catalog

> "Here's the part that's *different* from every other demand demo you've seen. Two thousand forecast rows — written by Snowflake — landing as **Apache Iceberg** files on `s3://sg-retail-demos-2026/iceberg/manufacturing-demand/forecast/`. Schema, partitions, statistics — all native Iceberg metadata. **AWS Glue catalog** `mfg_demand_iceberg` registers the table. No copy job, no nightly sync, no ETL pipeline drift. The forecast is *born in the lake*."

**Action**: Switch to **AWS S3 console** → show the Iceberg files (data + metadata folders).

> "There's the data files. There's the metadata. That's a real Iceberg snapshot — not a CSV, not a Parquet dump."

**Action**: Switch to **AWS Glue console** → filter `mfg_demand_iceberg` → click `forecast_iceberg`.

> "Glue picks up the schema instantly — eight columns, partitioned by category."

**Action**: Switch to **AWS Athena** → run the pre-loaded query.

> "And from Athena: same 2,000 rows, same accuracy by category. **Snowflake writes; AWS reads** — one open table format, zero copy, no SLA drift."

### [1:50–2:15] PAGE 4: ASK DEMAND

**Show**: Type "How many SKUs are at stockout risk?" — confirm answer = 156

**Tech**: Cortex Analyst + Semantic View

> "Natural language. **Cortex Analyst** over `DEMAND_PLANNING_SEMANTIC_VIEW` answers in plain English — 156 SKUs at stockout risk, broken down by category. The planner doesn't need SQL. The COO doesn't need a dashboard request ticket."

### [2:15–2:45] QUICKSIGHT + AMAZON Q — the executive lens

**Show**: Switch to QuickSight dashboard `mfg-demand-dashboard`

**Tech**: QuickSight on Athena/Iceberg + Amazon Q topic

> "Two surfaces, one forecast. The Snowflake-direct view in QuickSight gives the COO live KPIs — accuracy, stockout, overstock, value-at-risk. The Athena variant queries the *Iceberg* version of the same data — same numbers, AWS-native consumption. **Amazon Q topic** `mfg-demand-q`: 'Which category has the lowest forecast accuracy?' — Electronics, 56%. From any phone, no SQL."

### [2:45–3:10] CLOSE

> "Recap. Sales and supplier feeds land in **Amazon S3**. Snowflake builds the curated demand model with **Dynamic Tables**, runs **ML.FORECAST** for 500 SKUs across 14 periods — no Python, no GPU pool — and writes the result back to your lake as **Apache Iceberg**, registered in **AWS Glue**, queryable from **Athena**. **QuickSight** consumes both surfaces; **Amazon Q** lets the COO ask plain-English questions. Same data, two consumption surfaces, zero copy. That's how you stop the 'Snowflake versus the data lake' debate — and start an *open forecast pipeline* on Snowflake and AWS."

---

## Key Demo Differentiators (vs other AWS demos)

1. **Bidirectional data flow** — most demos pull *into* Snowflake; this one writes Iceberg *back out* to AWS Glue.
2. **No copy job** — Athena queries the same physical files Snowflake wrote. One source of truth.
3. **Dual QuickSight datasets** — one Snowflake-direct, one Athena/Iceberg, prove you can pick the consumption pattern per dashboard.
4. **Cortex ML.FORECAST** — 7,000 predictions, no Python, no SageMaker job to babysit.
5. **Q topic answers** to try: "Which category has the lowest accuracy?" / "What's the value-at-risk by region?" / "How many SKUs are overstocked?"
