-- ============================================================================
-- 12_alerts_notifications.sql
-- Snowflake hero: Alerts + Notification Integration (Snowflake → AWS SNS)
-- ----------------------------------------------------------------------------
-- Creates a Snowflake Alert that fires when Electronics forecast accuracy
-- drops below 75%. Sends notification to AWS SNS topic for operational response.
-- ============================================================================

CREATE OR REPLACE NOTIFICATION INTEGRATION DEMAND_SNS_INT
    ENABLED = TRUE
    TYPE = QUEUE
    NOTIFICATION_PROVIDER = AWS_SNS
    DIRECTION = OUTBOUND
    AWS_SNS_TOPIC_ARN = 'arn:aws:sns:us-west-2:<YOUR_AWS_ACCOUNT_ID>:mfg-demand-forecast-alerts'
    AWS_SNS_ROLE_ARN = 'arn:aws:iam::<YOUR_AWS_ACCOUNT_ID>:role/snowflake-demand-sns-role';

USE SCHEMA MANUFACTURING_DEMAND.APP;

CREATE OR REPLACE ALERT FORECAST_DEGRADATION_ALERT
    WAREHOUSE = CORTEX
    SCHEDULE = '5 MINUTE'
    IF (EXISTS (
        SELECT 1 FROM MANUFACTURING_DEMAND.CURATED.FORECAST_ACCURACY
        WHERE CATEGORY = 'Electronics'
        AND AVG_ACCURACY_PCT < 75
        AND WEEK_START >= DATEADD('day', -14, CURRENT_DATE())
    ))
    THEN
        CALL SYSTEM$SEND_SNOW_API_REQUEST(
            'POST',
            '/api/v2/notifications/send',
            '{}', '{}',
            '{
                "notification_integration": "DEMAND_SNS_INT",
                "message": "DEMAND ALERT: Electronics forecast accuracy below 75% in the last 14 days. Review MANUFACTURING_DEMAND.CURATED.FORECAST_ACCURACY for details."
            }',
            NULL, 30000
        );

ALTER ALERT FORECAST_DEGRADATION_ALERT RESUME;
