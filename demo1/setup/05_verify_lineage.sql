-- =============================================================================
-- 05_verify_lineage.sql
-- Verification queries for lineage
-- Run AFTER 01-04 are complete and Agent version is committed
-- =============================================================================

SET database_name = 'TSHO_SWT_TOKYO_26';
SET warehouse_name = 'TSHO_WH_XL';

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE IDENTIFIER($warehouse_name);

-- ---------------------------------------------------------------------------
-- #1: Does Semantic View appear as downstream of FCT_ORDERS?
-- FCT_ORDERS is a VIEW, not a TABLE
-- Expected: SV_SALES (SEMANTIC_VIEW) + SALES_AGENT (CORTEX_AGENT)
-- ---------------------------------------------------------------------------
SELECT
    TARGET_OBJECT_DATABASE, TARGET_OBJECT_SCHEMA, TARGET_OBJECT_NAME,
    TARGET_OBJECT_DOMAIN, DISTANCE
FROM TABLE(SNOWFLAKE.CORE.GET_LINEAGE(
    'TSHO_SWT_TOKYO_26.MARTS.FCT_ORDERS', 'VIEW', 'DOWNSTREAM', 5
))
ORDER BY DISTANCE;

-- ---------------------------------------------------------------------------
-- #2: Does Cortex Agent appear as downstream of SV_SALES?
-- SV_SALES is a SEMANTIC_VIEW
-- Expected: SALES_AGENT (CORTEX_AGENT) at distance 1
-- ---------------------------------------------------------------------------
SELECT
    TARGET_OBJECT_DATABASE, TARGET_OBJECT_SCHEMA, TARGET_OBJECT_NAME,
    TARGET_OBJECT_DOMAIN, DISTANCE
FROM TABLE(SNOWFLAKE.CORE.GET_LINEAGE(
    'TSHO_SWT_TOKYO_26.AI.SV_SALES', 'SEMANTIC_VIEW', 'DOWNSTREAM', 5
))
ORDER BY DISTANCE;
