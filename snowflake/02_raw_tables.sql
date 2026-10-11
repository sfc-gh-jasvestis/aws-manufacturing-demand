-- Synthetic item-day demand planning observations for a fictional Singapore manufacturer.
-- A planning item is one fictional product family stocked at one Singapore distribution centre.
-- Nothing is seeded as a prediction. Randomness is HASH-seeded, so every rebuild
-- is reproducible: per-item stockout propensity, forecast drift between
-- S&OP plan reviews, missed plan reviews, category-weighted plan exception types,
-- exceptions resolved without a stockout, and two port congestion events at the Pasir Panjang and Tuas terminals.
USE DATABASE IDENTIFIER($DEMO_DB);
USE SCHEMA RAW;
USE WAREHOUSE IDENTIFIER($DEMO_WH);

CREATE TABLE RAW.PLANNING_ITEMS AS
WITH items AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS ITEM_INDEX
  FROM TABLE(GENERATOR(ROWCOUNT => 40))
), draws AS (
  SELECT ITEM_INDEX,
         MOD(ABS(HASH(ITEM_INDEX, 'sg-mfd-launch')), 1000000) / 1e6 AS U_AGE,
         MOD(ABS(HASH(ITEM_INDEX, 'sg-mfd-stockout')), 1000000) / 1e6 AS U_RATE,
         MOD(ABS(HASH(ITEM_INDEX, 'sg-mfd-cadence')), 1000000) / 1e6 AS U_REVIEW,
         MOD(ABS(HASH(ITEM_INDEX, 'sg-mfd-adherence')), 1000000) / 1e6 AS U_DISCIPLINE,
         MOD(ABS(HASH(ITEM_INDEX, 'sg-mfd-tier')), 1000000) / 1e6 AS U_TIER
  FROM items
)
SELECT 'PLN-' || LPAD(ITEM_INDEX::VARCHAR, 4, '0') AS ID,
       'Synthetic planning item ' || LPAD(ITEM_INDEX::VARCHAR, 4, '0') AS NAME,
       -- Deterministic spread (5 and 8 are coprime): every DC and category is present.
       CASE MOD(ITEM_INDEX, 5) WHEN 0 THEN 'Tuas' WHEN 1 THEN 'Woodlands'
            WHEN 2 THEN 'Pasir Panjang' WHEN 3 THEN 'Changi' ELSE 'Tampines' END AS REGION,
       CASE MOD(ITEM_INDEX, 8) WHEN 0 THEN 'Electronic components' WHEN 1 THEN 'Electronic components'
            WHEN 2 THEN 'Automotive parts' WHEN 3 THEN 'Automotive parts' WHEN 4 THEN 'Industrial supplies'
            WHEN 5 THEN 'Industrial supplies' WHEN 6 THEN 'Packaging materials' ELSE 'Consumer appliances' END AS CATEGORY,
       ITEM_INDEX,
       1 + FLOOR(U_TIER * 3) AS RISK_TIER,
       ROUND(0.2 + U_AGE * 5.8, 1) AS ITEM_AGE_YEARS,
       -- Base daily stockout probability 0.4%-3%; ~15% of items are
       -- chronically volatile (x3).
       (0.004 + U_RATE * 0.026) * IFF(U_RATE > 0.85, 3, 1) AS BASE_STOCKOUT_RATE,
       7 * (1 + FLOOR(U_REVIEW * 3)) AS PLAN_REVIEW_INTERVAL_DAYS,
       0.55 + U_DISCIPLINE * 0.45 AS PLAN_REVIEW_COMPLETION_PROB,
       'Active' AS STATUS
FROM draws;

CREATE TABLE RAW.ITEM_DAILY AS
WITH days AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS DAY_INDEX
  FROM TABLE(GENERATOR(ROWCOUNT => 90))
), dc_events AS (
  -- Two port congestion events; every item at the DC raises a plan exception
  -- that is resolved once inbound containers clear.
  SELECT * FROM VALUES (31, 'Pasir Panjang'), (58, 'Tuas') AS o(DAY_INDEX, REGION)
), base AS (
  SELECT s.ID AS ENTITY_ID, s.ITEM_INDEX, s.CATEGORY, s.REGION, s.ITEM_AGE_YEARS,
         s.BASE_STOCKOUT_RATE, s.PLAN_REVIEW_INTERVAL_DAYS, s.PLAN_REVIEW_COMPLETION_PROB,
         d.DAY_INDEX,
         DATEADD('day', d.DAY_INDEX - 89, CURRENT_DATE()) AS EVENT_DATE,
         MOD(d.DAY_INDEX + s.ITEM_INDEX * 3, s.PLAN_REVIEW_INTERVAL_DAYS) AS DAYS_SINCE_REVIEW,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'sg-mfd-short')), 1000000) / 1e6 AS U_STOCKOUT,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'sg-mfd-flag')), 1000000) / 1e6 AS U_DETECT,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'sg-mfd-cover')), 1000000) / 1e6 AS U_RESOLVE,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'sg-mfd-kind')), 1000000) / 1e6 AS U_TYPE,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'sg-mfd-held')), 1000000) / 1e6 AS U_DONE,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'sg-mfd-units')), 1000000) / 1e6 AS U_VOLUME,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'sg-mfd-jitter')), 1000000) / 1e6 AS U_NOISE,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'sg-mfd-airfreight')), 1000000) / 1e6 AS U_EXPEDITE,
         e.REGION IS NOT NULL AS DC_EVENT
  FROM RAW.PLANNING_ITEMS s CROSS JOIN days d
  LEFT JOIN dc_events e ON e.DAY_INDEX = d.DAY_INDEX AND e.REGION = s.REGION
), review AS (
  SELECT *,
         IFF(DAYS_SINCE_REVIEW = 0, 1, 0) AS PLAN_REVIEW_DUE,
         IFF(DAYS_SINCE_REVIEW = 0 AND U_DONE < PLAN_REVIEW_COMPLETION_PROB, 1, 0) AS PLAN_REVIEW_DONE,
         -- Forecast drift rises between plan reviews; weak review adherence
         -- carries it over.
         DAYS_SINCE_REVIEW / PLAN_REVIEW_INTERVAL_DAYS + (1 - PLAN_REVIEW_COMPLETION_PROB) AS DRIFT
  FROM base
), shortfalls AS (
  SELECT *,
         CASE WHEN U_STOCKOUT < LEAST(0.5, BASE_STOCKOUT_RATE * (0.4 + 1.6 * DRIFT) * (1 + 1 / (1 + ITEM_AGE_YEARS))) / 4 THEN 2
              WHEN U_STOCKOUT < LEAST(0.5, BASE_STOCKOUT_RATE * (0.4 + 1.6 * DRIFT) * (1 + 1 / (1 + ITEM_AGE_YEARS))) THEN 1
              ELSE 0 END AS STOCKOUT_RISK_COUNT
  FROM review
), exceptions AS (
  SELECT *,
         -- About 85% of shortfalls raise a plan exception and end in a stockout;
         -- the rest are covered by an expedited shipment without an exception.
         IFF(DC_EVENT, 0, IFF(U_DETECT < 0.85, STOCKOUT_RISK_COUNT, 0)) AS STOCKOUT_COUNT,
         -- Exceptions resolved without a stockout: higher where safety stock is deeper.
         IFF(DC_EVENT, 1, IFF(U_RESOLVE < CASE CATEGORY WHEN 'Packaging materials' THEN 0.20
                                                         WHEN 'Industrial supplies' THEN 0.12
                                                         WHEN 'Automotive parts' THEN 0.14 ELSE 0.08 END, 1, 0)) AS RESOLVED_COUNT
  FROM shortfalls
), measured AS (
  SELECT *,
         STOCKOUT_COUNT + RESOLVED_COUNT AS EXCEPTION_COUNT,
         ROUND(CASE CATEGORY WHEN 'Packaging materials' THEN 1800 WHEN 'Industrial supplies' THEN 650
                             WHEN 'Automotive parts' THEN 420 WHEN 'Consumer appliances' THEN 140 ELSE 2600 END
               * (0.7 + 0.6 * U_VOLUME) * (1 + 0.8 * STOCKOUT_RISK_COUNT)) AS DEMAND_UNITS,
         CASE CATEGORY WHEN 'Packaging materials' THEN 2.4 WHEN 'Industrial supplies' THEN 32
                       WHEN 'Automotive parts' THEN 51 WHEN 'Consumer appliances' THEN 285 ELSE 8.8 END
           * (0.8 + 0.4 * U_NOISE) AS AVG_UNIT_SGD
  FROM exceptions
)
SELECT ENTITY_ID || '-' || TO_CHAR(EVENT_DATE, 'YYYYMMDD') AS EVENT_ID,
       ENTITY_ID, EVENT_DATE,
       DEMAND_UNITS,
       ROUND(DEMAND_UNITS * AVG_UNIT_SGD, 0) AS DEMAND_VALUE_SGD,
       EXCEPTION_COUNT, STOCKOUT_COUNT,
       IFF(STOCKOUT_COUNT > 0 AND U_EXPEDITE < 0.6, 1, 0) AS EXPEDITED_SHIPMENT,
       CASE WHEN EXCEPTION_COUNT = 0 THEN 'None'
            WHEN DC_EVENT THEN 'Port congestion'
            WHEN CATEGORY = 'Electronic components' THEN IFF(U_TYPE < 0.5, 'Demand spike', IFF(U_TYPE < 0.8, 'Supplier delay', 'Forecast bias'))
            WHEN CATEGORY = 'Automotive parts' THEN IFF(U_TYPE < 0.45, 'Supplier delay', IFF(U_TYPE < 0.8, 'Allocation shortfall', 'Forecast bias'))
            WHEN CATEGORY = 'Industrial supplies' THEN IFF(U_TYPE < 0.55, 'Allocation shortfall', 'Late purchase order')
            WHEN CATEGORY = 'Consumer appliances' THEN IFF(U_TYPE < 0.45, 'Promotion uplift missed', IFF(U_TYPE < 0.8, 'Late purchase order', 'Forecast bias'))
            ELSE IFF(U_TYPE < 0.5, 'Late purchase order', IFF(U_TYPE < 0.75, 'Allocation shortfall', 'Supplier delay')) END AS EXCEPTION_TYPE,
       PLAN_REVIEW_DUE, PLAN_REVIEW_DONE,
       ROUND(4.0 + 9.0 * DRIFT + 11.0 * STOCKOUT_RISK_COUNT + U_NOISE * 3.0, 2) AS FORECAST_ERROR_PCT,
       ROUND(30 + 20 * DRIFT + 26 * STOCKOUT_RISK_COUNT + U_NOISE * 10, 1) AS REPLENISH_LEAD_HRS,
       CURRENT_TIMESTAMP() AS LOADED_AT
FROM measured;

-- Supplier capacity confirmation coverage per planning item (snapshot).
CREATE TABLE RAW.SUPPLIER_CONFIRMATIONS AS
SELECT ID AS ENTITY_ID,
       CASE CATEGORY WHEN 'Electronic components' THEN 'Chip allocation confirmation'
                     WHEN 'Automotive parts' THEN 'Tier-2 supplier capacity confirmation'
                     WHEN 'Industrial supplies' THEN 'Blanket order release confirmation'
                     WHEN 'Packaging materials' THEN 'Resin supply confirmation'
                     ELSE 'Contract manufacturer slot confirmation' END AS DOC_TYPE,
       1 + MOD(ABS(HASH(ID, 'sg-mfd-needed')), 4) AS REQUIRED_QTY,
       MOD(ABS(HASH(ID, 'sg-mfd-received')), 5) AS ON_FILE_QTY,
       IFF(MOD(ABS(HASH(ID, 'sg-mfd-received')), 5) < 1 + MOD(ABS(HASH(ID, 'sg-mfd-needed')), 4),
           MOD(ABS(HASH(ID, 'sg-mfd-awaiting')), 3), 0) AS PENDING_QTY,
       CURRENT_DATE() AS SNAPSHOT_DATE
FROM RAW.PLANNING_ITEMS;
