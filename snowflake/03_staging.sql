-- Validate the producer contract before building downstream objects.
USE DATABASE IDENTIFIER($DEMO_DB);
USE SCHEMA RAW;
USE WAREHOUSE IDENTIFIER($DEMO_WH);

EXECUTE IMMEDIATE $$
DECLARE
  violations INTEGER;
  invalid_source EXCEPTION (-20001, 'Synthetic source failed grain or measure validation');
BEGIN
  SELECT COUNT(*) INTO :violations FROM (
    SELECT ENTITY_ID, EVENT_DATE
    FROM RAW.ITEM_DAILY
    GROUP BY ENTITY_ID, EVENT_DATE HAVING COUNT(*) <> 1
    UNION ALL
    SELECT observation.ENTITY_ID, observation.EVENT_DATE
    FROM RAW.ITEM_DAILY observation
    LEFT JOIN RAW.PLANNING_ITEMS item ON item.ID = observation.ENTITY_ID
    WHERE item.ID IS NULL OR observation.DEMAND_UNITS < 0
       OR observation.DEMAND_VALUE_SGD < 0
       OR observation.STOCKOUT_COUNT < 0 OR observation.STOCKOUT_COUNT > observation.EXCEPTION_COUNT
       OR observation.EXCEPTION_COUNT > observation.DEMAND_UNITS
       OR observation.EXPEDITED_SHIPMENT > observation.STOCKOUT_COUNT
       OR observation.PLAN_REVIEW_DONE > observation.PLAN_REVIEW_DUE
  );
  IF (violations > 0) THEN
    RAISE invalid_source;
  END IF;
END;
$$;
