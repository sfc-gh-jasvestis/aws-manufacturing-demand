-- ============================================================================
-- 09_snowpipe_realtime.sql
-- AWS hero: Amazon S3 + SQS + Snowpipe auto-ingest
-- ----------------------------------------------------------------------------
-- Real-time partner demand signals (B2B EDI, POS feeds, e-commerce, distributor,
-- partner API) land in s3://<YOUR_S3_BUCKET>/demand/realtime/ and
-- flow into Snowflake within seconds via Snowpipe auto-ingest.
-- ============================================================================
USE SCHEMA MANUFACTURING_DEMAND.RAW;

CREATE OR REPLACE TABLE DEMAND_REALTIME (
    PRODUCT_ID   VARCHAR(10),
    WAREHOUSE_ID VARCHAR(10),
    DEMAND_DATE  DATE,
    UNITS_SOLD   NUMBER,
    CHANNEL      VARCHAR(50),
    INGESTED_AT  TIMESTAMP
);

CREATE OR REPLACE STAGE REALTIME_DEMAND_STAGE
    STORAGE_INTEGRATION = MANUFACTURING_DEMOS_S3_INTEGRATION
    URL = 's3://<YOUR_S3_BUCKET>/demand/realtime/'
    FILE_FORMAT = (TYPE = 'CSV' SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '"');

CREATE OR REPLACE PIPE DEMAND_REALTIME_PIPE
    AUTO_INGEST = TRUE
AS
COPY INTO DEMAND_REALTIME
FROM @REALTIME_DEMAND_STAGE
FILE_FORMAT = (TYPE = 'CSV' SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '"');

-- First load: refresh pipe to pick up existing files
ALTER PIPE DEMAND_REALTIME_PIPE REFRESH;
