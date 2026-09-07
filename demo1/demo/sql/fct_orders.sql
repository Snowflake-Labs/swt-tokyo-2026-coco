-- =============================================================================
-- fct_orders.sql
-- This is the file edited ON STAGE during the demo.
-- The presenter removes DISCOUNT_AMT and LEGACY_STATUS_CD, then runs
-- /impact-check to show that DISCOUNT_AMT is HIGH risk while
-- LEGACY_STATUS_CD is safe to remove.
-- =============================================================================

CREATE OR REPLACE VIEW TSHO_SWT_TOKYO_26.MARTS.FCT_ORDERS AS
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
    o.discount_amt,                              -- ← DELETE THIS LINE ON STAGE
    o.quantity * o.unit_price - o.discount_amt   AS net_revenue,  -- ← breaks without discount_amt
    o.legacy_status_cd,                          -- ← DELETE THIS LINE ON STAGE (safe)
    o.currency
FROM TSHO_SWT_TOKYO_26.STAGING.STG_ORDERS o
LEFT JOIN TSHO_SWT_TOKYO_26.STAGING.STG_CUSTOMERS c
    ON o.customer_id = c.customer_id;
