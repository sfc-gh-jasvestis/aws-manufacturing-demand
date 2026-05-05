-- Demand Optimization: Cortex Agent
USE SCHEMA MANUFACTURING_DEMAND.AI;

CREATE OR REPLACE CORTEX AGENT DEMAND_PLANNING_AGENT
    COMMENT = 'AI assistant for demand forecasting and inventory optimization'
    MODEL = 'claude-3-5-sonnet'
    TOOLS = (
        'MANUFACTURING_DEMAND.AI.DEMAND_PLANNING_SEMANTIC_VIEW' AS DemandAnalyst,
        'MANUFACTURING_DEMAND.SEARCH.PLANNING_DOCS_SEARCH' AS PlanningSearch,
        'snowflake.cortex.data_to_chart' AS ChartGenerator
    )
    SYSTEM_PROMPT = 'You are a demand planning intelligence assistant. Help planners identify forecast accuracy issues, inventory risks, and optimization opportunities. Always provide specific category-level numbers and actionable recommendations for rebalancing.';
