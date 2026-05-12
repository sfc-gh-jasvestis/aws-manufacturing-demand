-- ============================================================================
-- 11_cortex_classify.sql
-- Snowflake hero: Cortex AI functions (COMPLETE + SUMMARIZE)
-- ----------------------------------------------------------------------------
-- Classifies 80 planning docs into risk tiers using Cortex COMPLETE and
-- generates summaries with Cortex SUMMARIZE. Shows Cortex AI doing real
-- classification work — not just search, but understanding risk context.
-- ============================================================================
USE SCHEMA MANUFACTURING_DEMAND.AI;

CREATE OR REPLACE TABLE DOC_RISK_CLASSIFICATION AS
SELECT
    d.DOC_ID,
    d.TITLE,
    d.CATEGORY AS DOC_CATEGORY,
    TRIM(SNOWFLAKE.CORTEX.COMPLETE('claude-sonnet-4-6',
        'Classify this supply chain planning document into exactly one risk level. Return ONLY the label, nothing else.\n\nLabels:\n- CRITICAL: Mentions stockouts, emergency procurement, accuracy below 70%, production line stoppage, missed SLA\n- HIGH_RISK: Mentions declining accuracy, rising lead times, supplier issues, overstock >$10M\n- MEDIUM_RISK: Mentions seasonal shifts, moderate variance, process improvements needed\n- LOW_RISK: Standard operations, informational updates, policy documentation\n\nDocument:\n' || LEFT(d.CONTENT, 1500)
    )) AS RISK_LEVEL,
    SNOWFLAKE.CORTEX.SUMMARIZE(d.CONTENT) AS SUMMARY
FROM MANUFACTURING_DEMAND.RAW.PLANNING_DOCS d;
