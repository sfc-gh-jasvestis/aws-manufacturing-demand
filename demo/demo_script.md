# Demo Script: Demand Forecast Optimization
## ~4-Minute Recorded Walkthrough (4:00 target)
**Format**: Screen recording with voiceover
**Target**: Customer meeting / booth loop / social share
**Narrative**: "Snowflake does everything natively — forecast, detect, classify, alert, orchestrate — then the result is open, living in your AWS data lake as Iceberg"

---

## What's Built

| Layer | Component | Detail |
|---|---|---|
| **Ingest (AWS)** | Amazon S3 + Snowpipe | Real-time partner demand via auto-ingest |
| **RAW** | 7 tables | PRODUCTS (500), WAREHOUSES (10), DEMAND_HISTORY (100K), INVENTORY (50K), POs (10K), PLANNING_DOCS (80), DEMAND_REALTIME (500) |
| **CURATED** | 3 Dynamic Tables | FORECAST_ACCURACY, INVENTORY_HEALTH, DEMAND_SIGNALS |
| **ML** | ML.FORECAST + ML.ANOMALY_DETECTION | 14-day forecast + anomaly detection (5/8 days anomalous for Electronics) |
| **AI** | Cortex Classify (Claude Sonnet) + Semantic View + Agent | 80 docs classified (17 CRITICAL), NL analytics |
| **Orchestration** | Task DAG (3 tasks) | Retrain → rescan anomalies → refresh Iceberg |
| **Alert** | Snowflake Alert → AWS SNS | Fires when Electronics accuracy < 75% |
| **AWS Hero** | Iceberg + Glue + Athena | 2,000 rows queryable from Athena — no copy, no sync |
| **Consumption** | Streamlit (9 pages) + QuickSight + Amazon Q | Full analytics surface |

---

## Pre-Recording Checklist

- [ ] `SELECT CATEGORY, ROUND(AVG(AVG_ACCURACY_PCT),1) FROM MANUFACTURING_DEMAND.CURATED.FORECAST_ACCURACY GROUP BY CATEGORY ORDER BY 2` → Electronics 71.6%, Pharma 95.5%
- [ ] `SELECT RISK_LEVEL, COUNT(*) FROM MANUFACTURING_DEMAND.CURATED.INVENTORY_HEALTH GROUP BY RISK_LEVEL` → 324 STOCKOUT, 530 LOW, 946 HEALTHY, 199 OVERSTOCK
- [ ] `SELECT SERIES, SUM(CASE WHEN IS_ANOMALY THEN 1 ELSE 0 END) FROM MANUFACTURING_DEMAND.ML.DEMAND_ANOMALY_RESULTS GROUP BY SERIES` → Electronics 5, Pharma 2, FMCG 1, Industrial 1, Automotive 0
- [ ] `SELECT RISK_LEVEL, COUNT(*) FROM MANUFACTURING_DEMAND.AI.DOC_RISK_CLASSIFICATION GROUP BY RISK_LEVEL` → 17 CRITICAL, 20 HIGH_RISK, 29 MEDIUM_RISK, 14 LOW_RISK
- [ ] Snowpipe: `SELECT SYSTEM$PIPE_STATUS('MANUFACTURING_DEMAND.RAW.DEMAND_REALTIME_PIPE')` → RUNNING
- [ ] Open Streamlit, QuickSight, Athena tabs

---

## Script

### [0:00–0:25] THE PROBLEM & ARCHITECTURE

**Show**: Streamlit Overview page

> "One hundred and nineteen million dollars of exposed inventory. That's what's on screen right now. Electronics forecast accuracy sitting at seventy-two percent — thirteen points below target. Five of the last eight days flagged anomalous by Snowflake's ML.ANOMALY_DETECTION. Three hundred and twenty-four SKUs at stockout risk. Most demand-planning tools give you a dashboard. None of them give you the *forecast, anomaly detection, classification, alerting, and orchestration* built-in — with the result landing as Apache Iceberg in your AWS data lake. That's what we fix in four minutes."

### [0:25–0:50] REAL-TIME INGEST — the data flow

**Show**: Real-Time Ingest page

**Tech**: Amazon S3 → SQS → Snowpipe auto-ingest

> "Partner demand signals — POS feeds, EDI, e-commerce — land in Amazon S3. Snowpipe picks them up within seconds. Five hundred rows across five channels. No Lambda function, no Kinesis stream — just a PIPE object with AUTO_INGEST equals true. The data is in Snowflake before the partner's API call returns."

### [0:50–1:15] FORECAST ACCURACY — the signal

**Show**: Forecast Accuracy page — weekly trend by category

**Tech**: Dynamic Tables + ML.FORECAST

> "Five categories, fourteen forecast periods. Pharma tracks at ninety-six percent — nearly perfect. Electronics at seventy-two. That twenty-four-point spread isn't noise — it's a systematic forecast failure. The whole accuracy table refreshes every five minutes through Dynamic Tables."

### [1:15–1:45] DEMAND ANOMALIES — the validation

**Show**: Demand Anomalies page — Electronics selected

**Tech**: ML.ANOMALY_DETECTION

> "Here's what no other platform does natively. ML.ANOMALY_DETECTION — one SQL statement — trains on eighty-two days of history and tests the last eight. The gray band is the ninety-five percent prediction interval. Red dots are anomalies — actual demand falling outside what the model expects. Electronics: five out of eight days anomalous. The forecast model isn't just inaccurate — it's *structurally broken* for this category. Automotive: zero anomalies. The ML validates what the accuracy metric hints at."

### [1:45–2:10] PLANNING INTELLIGENCE — the AI

**Show**: Planning Intelligence page — KPI cards, red alert banner, CRITICAL filter active

**Tech**: Cortex COMPLETE (Claude Sonnet) + Cortex SUMMARIZE

> "The forecast says Electronics is broken. The anomaly model confirms it. But what do the planning documents say? Eighty documents — strategy memos, vendor guides, promotion calendars — classified by Claude Sonnet in a single SQL statement. Seventeen flagged CRITICAL. Every single one is a Demand Strategy document — the same category driving the Electronics forecast failure. Read the summaries: 'electronics demand accuracy below target at fifty-eight percent,' 'demand sensing pilot shows twenty-one-point improvement,' 'accelerate ML model deployment.' The AI didn't just classify the documents — it surfaced the root cause. Filter to HIGH RISK — eleven Category Plans, five more Demand Strategy docs. No external API, no vector database — classification, summarization, and risk triage, all native SQL."

### [2:10–2:55] ICEBERG EXPORT — the AWS payoff

**Show**: Iceberg Export page — KPI cards, S3 metadata path, sample rows, then flip to Athena tab

**Tech**: Apache Iceberg + S3 External Volume + AWS Glue + Athena

> "We've built the forecast, detected anomalies, classified the documents — but demand planning doesn't stop at Snowflake. The supply chain team runs Spark jobs. Finance queries Athena. Contract manufacturers need raw Parquet files on S3. This page is the handoff."

> *(gesture at KPI cards)* "Two thousand forecast rows, five categories, average accuracy eighty-five percent — written by Snowflake as open Apache Iceberg v2 on S3. No export job. No nightly CSV. No sync pipeline. Snowflake manages the table; the data lives as Parquet on S3 with Iceberg metadata."

> *(point at S3 metadata path)* "That S3 path is real — it's the Iceberg metadata JSON that any engine can discover. And this isn't a one-time snapshot. The Task DAG we built earlier refreshes this Iceberg table on every retrain cycle. New forecast, new Parquet files, same table — automatically."

> *(flip to Athena tab)* "Now watch. Same query, different engine. Athena reads the Glue catalog, points at the same S3 path. Electronics at seventy-two percent — same number we saw in the Forecast Accuracy page. Industrial seventy-nine. Automotive eighty-five. FMCG ninety-three. Pharma ninety-five. Five categories, same answers, zero copies. The finance team doesn't need Snowflake access. The supply chain Spark job doesn't need an API key. The data is just *there* — open, governed, and current. That's interoperability — not a slide, a live table."

### [2:55–3:30] ASK DEMAND + QUICKSIGHT — the consumption layer

**Show**: Ask Demand page (type question live) → flip to QuickSight tab (Amazon Q)

**Tech**: Cortex Analyst + Semantic View + QuickSight + Amazon Q

> *(type the question live)* "So we've built the pipeline, surfaced the anomalies, classified the documents, and exported to Iceberg. Now — who consumes this? The demand planner. And they don't write SQL."

> "Plain English: 'Which category has the lowest forecast accuracy?' Cortex Analyst interprets the question, writes the SQL, returns the answer — Electronics, seventy-two percent. Same number we saw in the Forecast Accuracy page. Same number Athena returned from Iceberg on S3. Three different engines, one truth."

> *(flip to QuickSight tab)* "Now the same question in Amazon Q on QuickSight. Q takes a different angle — it answers with Value at Risk by category. Pharma shows seventy-seven million dollars exposed, driven by stockout risk. Electronics nine point eight million. Different lens, same underlying data. The planner asks about accuracy; the CFO asks about dollars. Both get governed answers from the same pipeline."

> "That's the point. It's not about picking one tool. The demand planner lives in Streamlit. The finance director lives in QuickSight. The supply chain engineer lives in Athena. They all read from the same forecast — because the data is open and the answers are consistent."

### [3:30–3:55] CLOSE

> "Every capability you just saw — forecasting, anomaly detection, document intelligence, open lake export — that's five separate vendor contracts at most organizations. Here, it's one platform, native SQL, and the result is open Iceberg that every team can read. That's Snowflake and AWS — not choosing between them, building with both."

---

## Key Demo Differentiators (vs other MFG demos)

1. **ML.ANOMALY_DETECTION on demand data** — no other MFG demo uses this for demand signals
2. **Cortex AI classification** (COMPLETE + SUMMARIZE) — only demo with document risk triage
3. **Snowflake Task DAG** — only demo showing native orchestration (no Airflow)
4. **7 Snowflake features + 6 AWS services** — most balanced demo in the portfolio
6. **$119M value-at-risk** — the headline is real, auditable, and drives urgency
