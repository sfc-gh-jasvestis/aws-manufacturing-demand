-- ============================================================================
-- 08_native_demand.sql - Snowflake-only build: live demand feed without AWS.
-- Creates RAW.LIVE_DEMAND (same columns as the Snowpipe target created by
-- aws/setup_aws.py) and APP.SIMULATE_DEMAND(N), which inserts synthetic
-- partner order-line events with the same value ranges and ~10% EXCEPTION rate as
-- aws/publish_demand.py. Rows are inserted directly; this simulates a partner demand
-- feed and is not Snowpipe Streaming.
-- Run before 06_intelligence.sql (the alert reads RAW.LIVE_DEMAND).
-- Idempotent: safe to run in the AWS build too.
-- ============================================================================
CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS APP;

CREATE TABLE IF NOT EXISTS RAW.LIVE_DEMAND (
  ITEM_ID VARCHAR, EVENT_TS TIMESTAMP_NTZ, ORDER_VALUE_SGD FLOAT, REQUESTED_LEAD_HRS FLOAT,
  STATUS VARCHAR, SENT_TS TIMESTAMP_NTZ, SOURCE_FILE VARCHAR,
  LOADED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP());

CREATE OR REPLACE PROCEDURE APP.SIMULATE_DEMAND(N NUMBER)
RETURNS NUMBER
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
BEGIN
  IF (N < 1 OR N > 1000) THEN
    RETURN 0;
  END IF;
  INSERT INTO RAW.LIVE_DEMAND (ITEM_ID, EVENT_TS, ORDER_VALUE_SGD, REQUESTED_LEAD_HRS, STATUS, SENT_TS, SOURCE_FILE)
    WITH g AS (
      SELECT 'PLN-' || LPAD(UNIFORM(0, 39, RANDOM())::VARCHAR, 4, '0') AS ITEM_ID,
             UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.1 AS IS_EXCEPTION,
             SYSDATE() AS TS, SEQ4() AS I
      FROM TABLE(GENERATOR(ROWCOUNT => 1000))
    )
    -- NORMAL() needs constant arguments, so the exception offset is applied outside it.
    SELECT ITEM_ID, TS,
           ROUND(IFF(IS_EXCEPTION, 5700, 1900) * EXP(NORMAL(0, 0.5, RANDOM())), 0),
           ROUND(IFF(IS_EXCEPTION, 14, 96) * EXP(NORMAL(0, 0.4, RANDOM())), 0),
           IFF(IS_EXCEPTION, 'EXCEPTION', 'OK'), TS, 'APP.SIMULATE_DEMAND'
    FROM g
    WHERE I < :N;
  RETURN SQLROWCOUNT;
END;
$$;

-- Optional continuous feed for longer demos (suspended; RESUME to start, SUSPEND after).
CREATE OR REPLACE TASK APP.TASK_SIMULATE_DEMAND
  WAREHOUSE = __DEMO_WH__
  SCHEDULE = '1 MINUTE'
AS
  CALL APP.SIMULATE_DEMAND(5);
