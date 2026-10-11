# Singapore Manufacturing Demand Planning

**Singapore - Manufacturing**
Use case: Plan exceptions, stockouts, planning controls and stockout risk

> Demand planning for 40 fictional planning items of Straitsline Components, a fictional Singapore manufacturer, stocked at distribution centres in Tuas, Woodlands, Pasir Panjang, Changi and Tampines: dynamic tables, a holdout-evaluated stockout classifier, a network demand forecast and forecast error anomaly detection, a Cortex Agent with SOP citations, a live partner demand feed with an alert, and an SPCS app.

## Why Snowflake

- **Dynamic tables** reconcile units demanded, plan exceptions, stockouts, expedited shipments and plan review adherence from RAW item data, with checks in `run_core.py`
- **Stockout classification** gives a holdout-evaluated next-7-day probability per planning item
- **Demand forecast** projects 14 days of network-wide demand in units with prediction intervals, for supply planning
- **Grounded AI**: the Cortex Agent (Analyst over a semantic view, plus Search over SOPs) shows its SQL and SOP citations
- **Live demand**: a native simulator (Snowflake only) or Firehose, S3 and Snowpipe (AWS build), then an alert and email

## What is built

| | |
|---|---|
| Dimension table | `RAW.PLANNING_ITEMS` (40 rows) |
| Fact table | `RAW.ITEM_DAILY` (3,600 item-days, 90 days) |
| Curated layer | `CURATED.KPI_SUMMARY`, `PERFORMANCE_SUMMARY`, `EXCEPTION_SUMMARY`, `TREND_ANALYSIS` |
| ML | `ML.STOCKOUT_RISK_SCORES`, `ML.STOCKOUT_RISK_HOLDOUT_METRICS`, `ML.DEMAND_FORECAST`, `ML.FORECAST_ERROR_ANOMALIES` |

Currency: SGD. Distribution centres: Tuas, Woodlands, Pasir Panjang, Changi, Tampines.
Categories: Electronic components, Automotive parts, Industrial supplies, Packaging materials, Consumer appliances.

## KPI cards (live from `CURATED.KPI_SUMMARY`; no fallback values)

| Card | Value from the seeded data |
|---|---|
| Exception-Free Day Rate | 85.28% |
| Plan Exceptions Raised | 579 |
| Stockouts | 156 |
| Exception Stockout Rate | 26.9% |
| Expedited Shipments | 85 |
| Demand Value (SGD M) | 82 |
| Units Demanded | 4,341,282 |
| Plan Review Adherence | 78.1% |
| Planning Items Monitored | 40 |
| Supplier Confirmation Coverage | 58.7% |
| Supplier Confirmations Pending | 20 |

Values are synthetic. A rebuild reproduces them because the data is HASH-seeded; dates are relative to the build day.

## Demo flow

1. Executive Cockpit: KPIs, daily plan exceptions against stockouts, exceptions and stockouts by exception type, planning item table
2. Predictive: holdout metrics, risk bands, 14-day network demand forecast, forecast error anomalies
3. Controls: plan review adherence, supplier confirmation coverage and pending confirmations, plan review adherence against stockouts, then generate the action memo
4. Live Demand: run `CALL APP.SIMULATE_DEMAND(20)` (Snowflake only) or `python aws/publish_demand.py --count 20` (AWS build). Then run `EXECUTE ALERT APP.LIVE_DEMAND_ALERT` and show the alert log and email
5. Ask AI: the Cortex Agent answers metric questions through the semantic view and cites SOPs from Cortex Search. The SQL is shown.
6. QuickSight (AWS build): the same Snowflake tables through DIRECT_QUERY
7. Architecture: both builds side by side

## Talking points

- 85.28% of item-days run without a plan exception; the 579 plan exceptions are where planner time goes, and about 1 in 4 of them (26.9%) end in a stockout.
- Allocation shortfalls produce the most stockouts: 48 stockouts from 175 allocation shortfall exceptions. Port congestion hits every item at a DC at once (Pasir Panjang and Tuas, the two DCs next to the container terminals) and is always resolved without a stockout.
- The risk model is evaluated on a time-based holdout: precision 0.39 and recall 0.26 at 0.5, against a 0.20 base rate. Present it as triage, not a verdict.
- Port congestion events are excluded from model training, because they are DC-wide rather than item-driven.

## Business impact

Use only the sourced references in `README.md` (Business Impact).
