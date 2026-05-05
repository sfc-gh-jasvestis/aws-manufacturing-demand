# Demand Optimization & Planning — Demo Script

## Story

You're Maria Santos, Planning Manager at a global manufacturer. Your weekly review reveals something alarming: Electronics forecast accuracy has cratered. Within 3.5 minutes, you'll trace the accuracy drop to a seasonal shift, discover $51.6M in overstock exposure, identify 200 rush orders eating into margins, and watch the ML model retrain with corrected signals.

## Personas

| Persona | Title | Goal |
|---------|-------|------|
| **Maria Santos** | Planning Manager | Detect forecast drift early, rebalance inventory |
| **David Kim** | Chief Supply Chain Officer | Capital efficiency, service level compliance |

## What's Built

| Layer | Object | Purpose |
|-------|--------|---------|
| Data | 500 products, 100K demand records, 50K inventory snapshots | Complete demand signal |
| Dynamic Tables | FORECAST_ACCURACY, INVENTORY_HEALTH, DEMAND_SIGNALS | Real-time planning views |
| ML | Demand Forecast Model (14-day horizon, 50 series) | Predictive demand |
| Search | PLANNING_DOCS_SEARCH (80 docs) | Policy & procedure retrieval |
| Semantic View | DEMAND_PLANNING_SEMANTIC_VIEW | Natural language analytics |
| Agent | DEMAND_PLANNING_AGENT | Conversational planning assistant |
| Streamlit | DEMAND_OPTIMIZATION_APP | Planning dashboard |

## Narrative Arc

```
REVIEW → DETECT → QUANTIFY → ROOT CAUSE → RETRAIN → REBALANCE
  │         │         │           │           │          │
  ▼         ▼         ▼           ▼           ▼          ▼
Weekly   Electronics  $51.6M     Seasonal    ML model   Reduce
review   58% acc.    overstock   shift in    corrects   DOS to
         (target 85%)           demand      forecast   target 21
```

## Timed Script (3.5 minutes)

### Opening — Planning Dashboard (0:00–0:20)
- Open Streamlit app — DEMAND_OPTIMIZATION_APP
- "I'm Maria Santos, running demand planning across 5 product categories"
- KPI cards: 5 categories | 85% avg accuracy | $51.6M at risk | 200 rush orders
- **Key visual:** Electronics accuracy card in red (58%)

### Beat 1 — Detect Forecast Drift (0:20–0:50)
- Click Forecast Accuracy tab
- "Electronics accuracy dropped to 58% — every other category is above 90%"
- Show week-over-week decline chart
- "This started 3 weeks ago. Something fundamental changed in demand patterns"
- **Number:** 58% accuracy vs 91-94% for other categories

### Beat 2 — Quantify the Damage (0:50–1:20)
- Switch to Inventory Health view
- Filter: CATEGORY = 'Electronics', RISK_LEVEL = 'OVERSTOCK'
- "45 days of supply sitting in our warehouses — target is 21"
- "That's $51.6M in capital tied up in excess inventory"
- **Number:** 45 DOS, $51.6M overstock value

### Beat 3 — Rush Order Cascade (1:20–1:50)
- Show purchase orders tab
- Filter: ORDER_TYPE = 'RUSH'
- "200 rush orders in the last month — 82% are Electronics"
- "Each rush order costs 3x standard shipping. We're bleeding margin"
- **Number:** 200 rush orders, 82% Electronics, 3x cost multiplier

### Beat 4 — Ask AI for Root Cause (1:50–2:30)
- Open AI Assistant
- Type: "Why did Electronics forecast accuracy drop below 60%?"
- Agent analyzes: seasonal demand shift, new product launch cannibalization, supplier lead time changes
- "The model identified a seasonal shift that wasn't in our training window"
- **Key moment:** AI explains root cause with data evidence

### Beat 5 — ML Retraining & Recommendations (2:30–3:10)
- Type: "What should our rebalancing plan look like for Electronics?"
- Agent recommends: retrain with extended seasonality, redistribute 30% of overstock, adjust safety stock from 35 to 21 days
- Show forecast vs actual chart with correction
- **Number:** Retrain brings accuracy to projected 82% within 2 weeks

### Closing — Decision & Action (3:10–3:30)
- Return to dashboard
- "From a number on a screen to a complete rebalancing plan"
- "Retrain the model, redistribute overstock, tighten safety stock"
- "We just saved $51.6M in working capital exposure"
- **Tagline:** "Catch forecast drift before it becomes a warehouse problem"

## Pre-Recording Checklist

- [ ] Streamlit app loaded with all 5 tabs
- [ ] Electronics showing 58% accuracy (other categories 91-94%)
- [ ] Inventory Health showing 45 DOS for Electronics
- [ ] $51.6M value at risk visible
- [ ] 200 rush orders in PO tab
- [ ] Agent responding with root cause analysis
- [ ] Search returning planning procedures
- [ ] Warehouse CORTEX is STARTED

## Key Questions to Anticipate

1. **"How often does the forecast retrain?"** — Model can retrain on schedule (daily/weekly) or triggered by accuracy drift below threshold
2. **"What's the cost of being wrong?"** — $51.6M overstock + 200 rush orders × 3x premium = ~$12M excess logistics cost
3. **"Can this handle promotional demand?"** — Yes, external regressors (promotions, events) can be added to forecast model
4. **"How do you handle new products with no history?"** — Cold-start uses category-level forecast, transitions to product-level after 30 days
5. **"Integration with ERP?"** — S3 stage ingests from any ERP export; SAP/Oracle connectors available via Snowpipe
