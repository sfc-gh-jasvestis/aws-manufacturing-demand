# Demo Script: Open Forecast Data Lake
## ~70-second walkthrough — Snowflake + Apache Iceberg + AWS Glue + Athena + QuickSight

---

## The Story
Electronics forecast accuracy at 56% — target 85%. 156 SKUs at stockout risk. Snowflake runs the forecast; the result lands as Apache Iceberg on S3 and shows up in the customer's Glue catalog instantly — Athena and QuickSight read it without any copy job.

---

## Personas

| Persona | Tool | What they care about |
|---|---|---|
| Demand Planner | Streamlit on Snowflake | Per-SKU accuracy, stockout/overstock, demand signals |
| Operations COO | Amazon Athena + QuickSight + Amazon Q | Same forecast, AWS-native consumption |

---

## Script

### [0:00–0:10] HOOK
> "Electronics forecast at 56%, 156 SKUs at stockout risk. We run the forecast in Snowflake and publish it as Apache Iceberg — the customer's data lake, no copy."

### [0:10–0:30] STREAMLIT — Forecast Accuracy + Inventory Health
> Open `MANUFACTURING_DEMAND.APP.DEMAND_OPTIMIZATION_APP`.
> "Forecast Accuracy page — only Electronics drops below the 85% line. Inventory Health: 156 STOCKOUT, $46M Pharma value-at-risk. Three Dynamic Tables refresh every 5 min."

### [0:30–0:45] ICEBERG EXPORT (AWS Glue) — the AWS hero
> Open page **Iceberg Export (AWS Glue)**.
> "2,000 forecast rows written as Apache Iceberg under `s3://sg-retail-demos-2026/iceberg/manufacturing-demand/forecast/`. AWS Glue catalog `mfg_demand_iceberg` registers the table. Same schema, no copy job, no nightly sync."

### [0:45–1:00] ATHENA + QUICKSIGHT
> "Paste the Athena query into the AWS console — same 2,000 rows. QuickSight dashboard `mfg-demand-dashboard` over Athena and the Amazon Q topic `mfg-demand-q` answer 'Which category has the lowest forecast accuracy?' from any phone."

### [1:00–1:10] CLOSE
> "Snowflake runs the forecast; Apache Iceberg + Glue makes it native to the customer's AWS estate. Same data, two consumption surfaces, zero ETL."

---

## Pre-Recording Checklist
- [ ] `SELECT * FROM MANUFACTURING_DEMAND.LAKE.VW_FORECAST_ICEBERG_STATS` returns 2,000 rows
- [ ] Streamlit Iceberg page renders KPIs and sample
- [ ] Open https://app.snowflake.com/SFSEAPAC/sg_demo43/#/streamlit-apps/MANUFACTURING_DEMAND.APP.DEMAND_OPTIMIZATION_APP
- [ ] Open https://us-west-2.quicksight.aws.amazon.com/sn/dashboards/mfg-demand-dashboard
