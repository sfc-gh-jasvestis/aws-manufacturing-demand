-- Demand Optimization: Semantic View
USE SCHEMA MANUFACTURING_DEMAND.AI;

CREATE OR REPLACE SEMANTIC VIEW DEMAND_PLANNING_SEMANTIC_VIEW
    COMMENT = 'Demand planning analytics: forecast accuracy, inventory health, demand signals'
AS
    TABLES (
        CURATED.FORECAST_ACCURACY AS forecast
            COLUMNS (
                CATEGORY AS category COMMENT 'Product category: Electronics, Automotive, Pharma, FMCG, Industrial',
                WEEK AS week COMMENT 'Week of forecast measurement',
                AVG_ACCURACY_PCT AS forecast_accuracy COMMENT 'Average forecast accuracy percentage',
                BIAS_PCT AS forecast_bias COMMENT 'Forecast bias - positive means over-forecasting'
            ),
        CURATED.INVENTORY_HEALTH AS inventory
            COLUMNS (
                CATEGORY AS category COMMENT 'Product category',
                WAREHOUSE_NAME AS warehouse COMMENT 'Distribution center name',
                DAYS_OF_SUPPLY AS days_of_supply COMMENT 'Current days of supply on hand',
                VALUE_AT_RISK AS value_at_risk COMMENT 'Dollar value at risk from overstock or stockout',
                RISK_LEVEL AS risk_level COMMENT 'OVERSTOCK, CRITICAL_LOW, LOW, HEALTHY'
            ),
        CURATED.DEMAND_SIGNALS AS signals
            COLUMNS (
                CATEGORY AS category COMMENT 'Product category',
                GROWTH_RATE_PCT AS growth_rate COMMENT '7-day vs 30-day demand growth rate percentage',
                VELOCITY_RANK AS velocity_rank COMMENT 'Demand velocity rank within category (1=highest)'
            )
    );
