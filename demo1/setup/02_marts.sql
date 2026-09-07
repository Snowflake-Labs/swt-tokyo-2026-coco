-- =============================================================================
-- 02_marts.sql
-- Mart layer: FCT_ORDERS view + AGG_SALES_DAILY dynamic table
-- FCT_ORDERS intentionally includes DISCOUNT_AMT (HIGH risk downstream)
-- and LEGACY_STATUS_CD (no downstream = safe to remove)
-- =============================================================================

SET database_name = 'TSHO_SWT_TOKYO_26';
SET warehouse_name = 'TSHO_WH_XL';

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE IDENTIFIER($warehouse_name);
USE DATABASE IDENTIFIER($database_name);
USE SCHEMA MARTS;

-- ---------------------------------------------------------------------------
-- FCT_ORDERS: The view that will be edited on stage
-- DISCOUNT_AMT → downstream (DT + SV + Agent + external BI) → HIGH risk
-- LEGACY_STATUS_CD → no downstream → safe
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW FCT_ORDERS AS
SELECT
    o.order_id,
    o.customer_id,
    c.customer_name,
    c.region,
    c.segment,
    o.order_date,
    o.product,
    o.quantity,
    o.unit_price,
    o.quantity * o.unit_price                    AS gross_revenue,
    o.discount_amt,
    o.quantity * o.unit_price - o.discount_amt   AS net_revenue,
    o.legacy_status_cd,
    o.currency
FROM TSHO_SWT_TOKYO_26.STAGING.STG_ORDERS o
LEFT JOIN TSHO_SWT_TOKYO_26.STAGING.STG_CUSTOMERS c
    ON o.customer_id = c.customer_id;

-- ---------------------------------------------------------------------------
-- AGG_SALES_DAILY: Dynamic Table referencing DISCOUNT_AMT via net_revenue
-- ---------------------------------------------------------------------------
CREATE OR REPLACE DYNAMIC TABLE AGG_SALES_DAILY
    TARGET_LAG = '1 hour'
    WAREHOUSE = TSHO_WH_XL
    COMMENT = 'Daily sales aggregation for Impact Radar demo'
AS
SELECT
    order_date,
    region,
    segment,
    COUNT(*)            AS order_count,
    SUM(gross_revenue)  AS total_gross,
    SUM(discount_amt)   AS total_discount,
    SUM(net_revenue)    AS total_net
FROM FCT_ORDERS
GROUP BY order_date, region, segment;
