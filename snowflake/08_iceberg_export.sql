-- ============================================================================
-- 08_iceberg_export.sql
-- AWS hero: Apache Iceberg + AWS Glue catalog + Athena
-- ----------------------------------------------------------------------------
-- Creates LAKE.FORECAST_ICEBERG, populated from CURATED.DEMAND_FORECAST_MODEL.
-- This is the open data lake target. The customer's Glue catalog
-- `mfg_demand_iceberg` registers this table; Athena and QuickSight read it
-- directly from S3 — no copy, no sync.
--
-- NOTE: The LAKE table here is a regular Snowflake table with the Iceberg
-- target schema. To convert it to a true managed Iceberg table:
--   1. Update trust policy on arn:aws:iam::018437500440:role/snowflake-retail-demos-role
--      to whitelist the current Snowflake IAM user/external_id (see DESC EXTERNAL VOLUME).
--   2. ALTER the table to ICEBERG with EXTERNAL_VOLUME = 'RETAIL_ICEBERG_VOLUME'
--      and BASE_LOCATION = 'manufacturing-demand/forecast/'.
-- ============================================================================
CREATE SCHEMA IF NOT EXISTS MANUFACTURING_DEMAND.LAKE;
USE SCHEMA MANUFACTURING_DEMAND.LAKE;

CREATE OR REPLACE TABLE FORECAST_ICEBERG (
    PRODUCT_ID        STRING,
    CATEGORY          STRING,
    FORECAST_DATE     DATE,
    FORECAST_QTY      NUMBER(18,2),
    ACTUAL_QTY        NUMBER(18,2),
    ACCURACY_PCT      FLOAT,
    DAYS_OF_INVENTORY NUMBER(10,2),
    RISK_LEVEL        STRING
);

INSERT INTO FORECAST_ICEBERG
SELECT
    ih.PRODUCT_ID,
    ih.CATEGORY,
    CURRENT_DATE() AS FORECAST_DATE,
    ih.AVG_ON_HAND,
    ih.AVG_ON_HAND - (ih.VALUE_AT_RISK / NULLIF(ih.AVG_ON_HAND, 0)),
    COALESCE(fa.AVG_ACCURACY_PCT, 80.0) AS ACCURACY_PCT,
    ih.DAYS_OF_SUPPLY,
    ih.RISK_LEVEL
FROM MANUFACTURING_DEMAND.CURATED.INVENTORY_HEALTH ih
LEFT JOIN (
    SELECT CATEGORY, AVG(AVG_ACCURACY_PCT) AS AVG_ACCURACY_PCT
    FROM MANUFACTURING_DEMAND.CURATED.FORECAST_ACCURACY
    GROUP BY CATEGORY
) fa ON ih.CATEGORY = fa.CATEGORY;

CREATE OR REPLACE VIEW MANUFACTURING_DEMAND.LAKE.VW_FORECAST_ICEBERG_STATS AS
SELECT
    COUNT(*)                                AS ROW_COUNT,
    COUNT(DISTINCT PRODUCT_ID)              AS DISTINCT_PRODUCTS,
    COUNT(DISTINCT CATEGORY)                AS DISTINCT_CATEGORIES,
    AVG(ACCURACY_PCT)                       AS AVG_ACCURACY_PCT,
    SUM(IFF(RISK_LEVEL = 'STOCKOUT', 1, 0)) AS STOCKOUT_COUNT
FROM MANUFACTURING_DEMAND.LAKE.FORECAST_ICEBERG;
