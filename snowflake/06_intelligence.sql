-- ============================================================================
-- 06_INTELLIGENCE.SQL - search, anomaly detection, semantic view, agent,
-- live-demand alert and on-demand refresh DAG.
-- Run with snowflake/run_intelligence.py (substitutes checked __DEMO_DB__ /
-- __DEMO_WH__ / __ALERT_EMAIL__). Requires 00-05, plus 08 (Snowflake only) or
-- aws/setup_aws.py (AWS build) for RAW.LIVE_DEMAND.
-- Alerts and tasks are created SUSPENDED; run them with EXECUTE ALERT / EXECUTE TASK.
-- ============================================================================
USE DATABASE __DEMO_DB__;
CREATE SCHEMA IF NOT EXISTS SEARCH;
CREATE SCHEMA IF NOT EXISTS APP;

-- ---------- Synthetic plan-exception knowledge base (clearly synthetic SOPs) ----------
CREATE OR REPLACE TABLE SEARCH.EXCEPTION_DOCS AS
WITH types AS (
  SELECT DISTINCT r.EXCEPTION_TYPE, a.CATEGORY
  FROM RAW.ITEM_DAILY r JOIN RAW.PLANNING_ITEMS a ON a.ID = r.ENTITY_ID
  WHERE r.STOCKOUT_COUNT > 0
)
SELECT
  'SOP-' || LPAD(ROW_NUMBER() OVER (ORDER BY CATEGORY, EXCEPTION_TYPE)::VARCHAR, 3, '0') AS DOC_ID,
  'SOP' AS DOC_TYPE,
  CATEGORY,
  EXCEPTION_TYPE,
  CATEGORY || ' - ' || EXCEPTION_TYPE || ' plan exception handling' AS TITLE,
  'Synthetic demo SOP. Product category: ' || CATEGORY || '. Plan exception type: ' || EXCEPTION_TYPE || '. '
  || 'Step 1: open a planning case, link the planning item and freeze the next replenishment order for the item until the case is triaged. '
  || 'Step 2: ' || CASE
       WHEN EXCEPTION_TYPE = 'Demand spike' THEN 'confirm the spike against open customer orders, release safety stock from the nearest DC, and raise the next planned order by the confirmed excess.'
       WHEN EXCEPTION_TYPE = 'Supplier delay' THEN 'get a revised ship date from the supplier, check alternate approved suppliers, and re-sequence open orders by customer priority.'
       WHEN EXCEPTION_TYPE = 'Forecast bias' THEN 'compare the last 4 weeks of forecast with actual demand, correct the baseline in the next plan review, and record the bias for the S&OP meeting.'
       WHEN EXCEPTION_TYPE = 'Allocation shortfall' THEN 'rebalance stock between DCs using the allocation rules, and ask the supplier to confirm capacity for the next two order cycles.'
       WHEN EXCEPTION_TYPE = 'Late purchase order' THEN 'expedite approval of the purchase order, confirm the supplier lead time, and check the reorder point for the item.'
       WHEN EXCEPTION_TYPE = 'Promotion uplift missed' THEN 'add the promotion calendar uplift to the forecast, and confirm the extra volume with sales before the next order cycle.'
       ELSE 'review the exception against the item history and escalate if unexplained.'
     END
  || ' Step 3: if the forecast error for the item exceeds 25% or the replenishment lead time exceeds 72 hours after triage, keep the case open and request a planning review. '
  || 'Step 4: record the resolution; if the item stocked out or needed an expedited shipment, notify the customer service team and log it for the S&OP report.' AS CONTENT
FROM types;

CREATE OR REPLACE CORTEX SEARCH SERVICE SEARCH.EXCEPTION_SOP_SEARCH
  ON CONTENT
  ATTRIBUTES CATEGORY, EXCEPTION_TYPE
  WAREHOUSE = __DEMO_WH__
  TARGET_LAG = '7 days'
AS (SELECT DOC_ID, TITLE, CATEGORY, EXCEPTION_TYPE, CONTENT FROM SEARCH.EXCEPTION_DOCS);

-- ---------- Forecast error anomaly detection (train first 75 days, detect last 15) ----------
CREATE OR REPLACE VIEW ML.FORECAST_ERROR_SERIES AS
SELECT ENTITY_ID, EVENT_DATE::TIMESTAMP_NTZ AS TS, FORECAST_ERROR_PCT::FLOAT AS FORECAST_ERROR
FROM RAW.ITEM_DAILY;
CREATE OR REPLACE VIEW ML.FORECAST_ERROR_TRAIN AS
SELECT * FROM ML.FORECAST_ERROR_SERIES WHERE TS < (SELECT DATEADD(day, -15, MAX(TS)) FROM ML.FORECAST_ERROR_SERIES);
CREATE OR REPLACE VIEW ML.FORECAST_ERROR_DETECT AS
SELECT * FROM ML.FORECAST_ERROR_SERIES WHERE TS >= (SELECT DATEADD(day, -15, MAX(TS)) FROM ML.FORECAST_ERROR_SERIES);

CREATE OR REPLACE SNOWFLAKE.ML.ANOMALY_DETECTION ML.FORECAST_ERROR_ANOMALY_MODEL(
  INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ML.FORECAST_ERROR_TRAIN'),
  SERIES_COLNAME => 'ENTITY_ID', TIMESTAMP_COLNAME => 'TS', TARGET_COLNAME => 'FORECAST_ERROR',
  LABEL_COLNAME => '');

CREATE OR REPLACE TABLE ML.FORECAST_ERROR_ANOMALIES AS
SELECT SERIES::VARCHAR AS ENTITY_ID, TS::DATE AS EVENT_DATE, Y AS FORECAST_ERROR, FORECAST AS EXPECTED,
       LOWER_BOUND, UPPER_BOUND, IS_ANOMALY, PERCENTILE
FROM TABLE(ML.FORECAST_ERROR_ANOMALY_MODEL!DETECT_ANOMALIES(
  INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ML.FORECAST_ERROR_DETECT'),
  SERIES_COLNAME => 'ENTITY_ID', TIMESTAMP_COLNAME => 'TS', TARGET_COLNAME => 'FORECAST_ERROR'));

-- ---------- Semantic view ----------
CREATE OR REPLACE SEMANTIC VIEW APP.DEMAND_ANALYTICS
  TABLES (
    items AS CURATED.PERFORMANCE_SUMMARY PRIMARY KEY (ENTITY_ID)
      WITH SYNONYMS = ('entities', 'planning items', 'SKUs')
      COMMENT = 'One row per planning item (distribution centre and product category), 90-day totals',
    risk AS ML.STOCKOUT_RISK_SCORES PRIMARY KEY (ENTITY_ID)
      COMMENT = 'Latest next-7-day stockout probability per planning item',
    exceptions AS CURATED.EXCEPTION_SUMMARY PRIMARY KEY (EXCEPTION_TYPE)
      COMMENT = 'Plan exceptions, stockouts and expedited shipments by exception type, 90 days',
    daily AS CURATED.TREND_ANALYSIS PRIMARY KEY (METRIC_DATE)
      COMMENT = 'Network-wide totals per day'
  )
  RELATIONSHIPS (risk_item AS risk (ENTITY_ID) REFERENCES items)
  FACTS (
    items.exceptions_f AS EXCEPTION_COUNT,
    items.stockouts_f AS STOCKOUT_COUNT,
    items.expedited_f AS EXPEDITED_COUNT,
    items.units_f AS DEMAND_UNITS,
    items.free_day_pct_f AS EXCEPTION_FREE_DAY_PCT,
    items.value_f AS DEMAND_VALUE_SGD,
    items.review_due_f AS PLAN_REVIEW_DUE,
    items.review_done_f AS PLAN_REVIEW_DONE,
    risk.stockout_prob_f AS STOCKOUT_PROB_7D,
    exceptions.type_exceptions_f AS EXCEPTION_COUNT,
    exceptions.type_stockouts_f AS STOCKOUT_COUNT,
    exceptions.type_expedited_f AS EXPEDITED_COUNT,
    exceptions.type_value_f AS EXPOSED_VALUE_SGD,
    daily.day_exceptions_f AS EXCEPTION_COUNT,
    daily.day_stockouts_f AS STOCKOUT_COUNT,
    daily.day_value_f AS DEMAND_VALUE_SGD
  )
  DIMENSIONS (
    items.item_id AS ENTITY_ID WITH SYNONYMS = ('planning item', 'item', 'entity', 'SKU'),
    items.item_name AS ENTITY_NAME,
    items.dc AS REGION WITH SYNONYMS = ('distribution centre', 'DC', 'region', 'market')
      COMMENT = 'Singapore distribution centre (planning area) that stocks the item',
    items.category AS CATEGORY WITH SYNONYMS = ('product category', 'vertical'),
    items.risk_tier AS RISK_TIER COMMENT = 'Item supply risk tier 1 (low) to 3 (high)',
    risk.risk_band AS RISK_BAND COMMENT = 'High >= 0.5, Medium >= 0.25, else Low',
    risk.scored_as_of AS SCORED_AS_OF,
    exceptions.exception_type AS EXCEPTION_TYPE WITH SYNONYMS = ('exception', 'exception reason', 'root cause'),
    daily.metric_date AS METRIC_DATE
  )
  METRICS (
    items.item_count AS COUNT(items.item_id) WITH SYNONYMS = ('number of planning items', 'number of entities', 'how many items'),
    items.exception_free_day_rate AS AVG(items.free_day_pct_f)
      WITH SYNONYMS = ('exception-free rate', 'clean day rate')
      COMMENT = 'Item-days without a plan exception / item-days (every item has 90 days, so the average is exact)',
    items.exception_stockout_pct AS 100 * SUM(items.stockouts_f) / NULLIF(SUM(items.exceptions_f), 0)
      COMMENT = 'Stockouts / plan exceptions raised',
    items.exceptions_raised AS SUM(items.exceptions_f) WITH SYNONYMS = ('plan exceptions', 'exceptions'),
    items.total_stockouts AS SUM(items.stockouts_f) WITH SYNONYMS = ('stockouts', 'out of stock events'),
    items.expedited_shipments AS SUM(items.expedited_f) WITH SYNONYMS = ('expedites', 'air freight'),
    items.units_demanded AS SUM(items.units_f) WITH SYNONYMS = ('demand', 'units', 'demand volume'),
    items.total_demand_value_sgd AS SUM(items.value_f) WITH SYNONYMS = ('demand value', 'value in SGD'),
    items.plan_review_adherence_pct AS 100 * SUM(items.review_done_f) / NULLIF(SUM(items.review_due_f), 0)
      COMMENT = 'Plan reviews completed / plan reviews due',
    risk.avg_stockout_prob AS AVG(risk.stockout_prob_f),
    exceptions.type_exceptions AS SUM(exceptions.type_exceptions_f),
    exceptions.type_stockouts AS SUM(exceptions.type_stockouts_f),
    exceptions.type_expedited AS SUM(exceptions.type_expedited_f),
    exceptions.type_stockout_share_pct AS 100 * SUM(exceptions.type_stockouts_f) / NULLIF(SUM(exceptions.type_exceptions_f), 0),
    daily.daily_exceptions AS SUM(daily.day_exceptions_f),
    daily.daily_stockouts AS SUM(daily.day_stockouts_f),
    daily.daily_value_sgd AS SUM(daily.day_value_f)
  )
  COMMENT = 'Synthetic Singapore manufacturing demand planning analytics (demo)';

-- ---------- Cortex Agent ----------
CREATE OR REPLACE AGENT APP.DEMAND_AGENT
  COMMENT = 'Demand planning assistant over a synthetic Singapore manufacturing network'
  FROM SPECIFICATION
$$
models:
  orchestration: claude-sonnet-4-5
instructions:
  response: "Answer only from tool results. State that data is synthetic. Give planning item IDs and numbers with units (units, SGD, %)."
  orchestration: "Use demand_analyst for units demanded, demand value, plan exceptions, stockouts, expedited shipments, exception-free day rate, plan review adherence, planning items, distribution centres, categories, exception types and stockout risk. Use sop_search for plan exception handling procedures."
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: demand_analyst
      description: "Units demanded, demand value in SGD, plan exceptions, stockouts, expedited shipments, exception-free day rate, plan review adherence, exception types and stockout risk scores by planning item, distribution centre and category"
  - tool_spec:
      type: cortex_search
      name: sop_search
      description: "Synthetic plan exception handling SOPs by product category and exception type"
tool_resources:
  demand_analyst:
    semantic_view: __DEMO_DB__.APP.DEMAND_ANALYTICS
    execution_environment:
      type: warehouse
      warehouse: __DEMO_WH__
  sop_search:
    name: __DEMO_DB__.SEARCH.EXCEPTION_SOP_SEARCH
    max_results: 3
    id_column: DOC_ID
    title_column: TITLE
$$;

-- ---------- Live-demand alert ----------
CREATE TABLE IF NOT EXISTS APP.ALERT_LOG (
  ALERTED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(), ITEM_ID VARCHAR,
  EVENT_TS TIMESTAMP_NTZ, ORDER_VALUE_SGD FLOAT, REQUESTED_LEAD_HRS FLOAT, SOP_HINT VARCHAR);

CREATE OR REPLACE NOTIFICATION INTEGRATION SG_MANUFACTURING_DEMAND_EMAIL_INT
  TYPE = EMAIL ENABLED = TRUE ALLOWED_RECIPIENTS = ('__ALERT_EMAIL__');

CREATE OR REPLACE PROCEDURE APP.LOG_LIVE_ALERTS()
RETURNS NUMBER
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
  n NUMBER;
BEGIN
  INSERT INTO APP.ALERT_LOG (ITEM_ID, EVENT_TS, ORDER_VALUE_SGD, REQUESTED_LEAD_HRS, SOP_HINT)
    SELECT p.ITEM_ID, p.EVENT_TS, p.ORDER_VALUE_SGD, p.REQUESTED_LEAD_HRS,
           'Check ' || r.CATEGORY || ' plan exception SOPs; current risk band ' || COALESCE(s.RISK_BAND, 'n/a')
    FROM RAW.LIVE_DEMAND p
    JOIN RAW.PLANNING_ITEMS r ON r.ID = p.ITEM_ID
    LEFT JOIN ML.STOCKOUT_RISK_SCORES s ON s.ENTITY_ID = p.ITEM_ID
    WHERE p.STATUS = 'EXCEPTION'
      AND NOT EXISTS (SELECT 1 FROM APP.ALERT_LOG l WHERE l.ITEM_ID = p.ITEM_ID AND l.EVENT_TS = p.EVENT_TS);
  n := SQLROWCOUNT;
  IF (n > 0) THEN
    CALL SYSTEM$SEND_EMAIL('SG_MANUFACTURING_DEMAND_EMAIL_INT', '__ALERT_EMAIL__',
      '[Demo] Demand exception alert',
      'New live demand exceptions logged in APP.ALERT_LOG: ' || :n || '. Data is synthetic.');
  END IF;
  RETURN n;
END;
$$;

CREATE OR REPLACE ALERT APP.LIVE_DEMAND_ALERT
  WAREHOUSE = __DEMO_WH__
  SCHEDULE = '5 MINUTE'
  IF (EXISTS (
    SELECT 1 FROM RAW.LIVE_DEMAND p
    WHERE p.STATUS = 'EXCEPTION'
      AND NOT EXISTS (SELECT 1 FROM APP.ALERT_LOG l WHERE l.ITEM_ID = p.ITEM_ID AND l.EVENT_TS = p.EVENT_TS)))
  THEN CALL APP.LOG_LIVE_ALERTS();

-- ---------- On-demand refresh DAG (suspended; run with EXECUTE TASK APP.TASK_REFRESH_CURATED) ----------
CREATE OR REPLACE PROCEDURE APP.REFRESH_CURATED()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
BEGIN
  ALTER DYNAMIC TABLE CURATED.PERFORMANCE_SUMMARY REFRESH;
  ALTER DYNAMIC TABLE CURATED.TREND_ANALYSIS REFRESH;
  ALTER DYNAMIC TABLE CURATED.EXCEPTION_SUMMARY REFRESH;
  ALTER DYNAMIC TABLE CURATED.KPI_SUMMARY REFRESH;
  RETURN 'refreshed';
END;
$$;

CREATE OR REPLACE TASK APP.TASK_REFRESH_CURATED
  WAREHOUSE = __DEMO_WH__
AS
  CALL APP.REFRESH_CURATED();

CREATE OR REPLACE TASK APP.TASK_RESCORE_RISK
  WAREHOUSE = __DEMO_WH__
  AFTER APP.TASK_REFRESH_CURATED
AS
  CREATE OR REPLACE TABLE ML.STOCKOUT_RISK_SCORES COPY GRANTS AS
  WITH latest AS (
    SELECT * FROM ML.STOCKOUT_FEATURES QUALIFY ROW_NUMBER() OVER (PARTITION BY ENTITY_ID ORDER BY EVENT_DATE DESC) = 1
  ), p AS (
    SELECT ENTITY_ID, EVENT_DATE,
           ML.STOCKOUT_RISK_MODEL!PREDICT(INPUT_DATA => OBJECT_CONSTRUCT(
             'CATEGORY', CATEGORY, 'RISK_TIER', RISK_TIER, 'ITEM_AGE_YEARS', ITEM_AGE_YEARS,
             'FORECAST_ERROR_PCT', FORECAST_ERROR_PCT, 'REPLENISH_LEAD_HRS', REPLENISH_LEAD_HRS,
             'FORECAST_ERROR_7D', FORECAST_ERROR_7D, 'STOCKOUT_30D', STOCKOUT_30D)) AS PRED
    FROM latest
  )
  SELECT ENTITY_ID, EVENT_DATE AS SCORED_AS_OF, ROUND(PRED:probability:STOCKOUT::FLOAT, 4) AS STOCKOUT_PROB_7D,
         CASE WHEN PRED:probability:STOCKOUT::FLOAT >= 0.5 THEN 'High'
              WHEN PRED:probability:STOCKOUT::FLOAT >= 0.25 THEN 'Medium' ELSE 'Low' END AS RISK_BAND,
         CURRENT_TIMESTAMP() AS SCORED_AT
  FROM p;
