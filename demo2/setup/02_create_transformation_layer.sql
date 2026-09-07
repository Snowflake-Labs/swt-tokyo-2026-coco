-- =============================================================================
-- 02_create_transformation_layer.sql
-- Dynamic Table: FRAUD_FEATURES
-- =============================================================================

SET database_name = 'TSHO_SWT_TOKYO_26';
SET warehouse_name = 'TSHO_WH_XL';

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE IDENTIFIER($warehouse_name);
USE SCHEMA TSHO_SWT_TOKYO_26.FRAUD;

CREATE OR REPLACE DYNAMIC TABLE FRAUD_FEATURES
    TARGET_LAG = '60 minutes'
    WAREHOUSE = TSHO_WH_XL
    COMMENT = 'Transaction features for fraud detection (demo2)'
AS
SELECT
    t.transaction_id,
    t.customer_id,
    t.merchant_id,
    t.transaction_ts,
    t.amount,
    t.currency,
    t.country        AS txn_country,
    t.channel,
    t.is_fraud,
    c.country          AS customer_country,
    c.account_age_days,
    c.customer_segment,
    m.merchant_country,
    m.merchant_category,
    m.risk_level       AS merchant_risk_level,
    CASE WHEN t.country != c.country THEN 1 ELSE 0 END AS country_changed_flag,
    CASE WHEN m.risk_level = 'high' THEN 1 ELSE 0 END  AS high_risk_merchant_flag,
    COUNT(*) OVER (
        PARTITION BY t.customer_id ORDER BY t.transaction_ts
        RANGE BETWEEN INTERVAL '1 HOUR' PRECEDING AND CURRENT ROW
    ) AS txn_count_1h,
    SUM(t.amount) OVER (
        PARTITION BY t.customer_id ORDER BY t.transaction_ts
        RANGE BETWEEN INTERVAL '1 HOUR' PRECEDING AND CURRENT ROW
    ) AS amount_sum_1h,
    AVG(t.amount) OVER (
        PARTITION BY t.customer_id ORDER BY t.transaction_ts
        RANGE BETWEEN INTERVAL '1 HOUR' PRECEDING AND CURRENT ROW
    ) AS amount_avg_1h,
    COUNT(*) OVER (
        PARTITION BY t.customer_id ORDER BY t.transaction_ts
        RANGE BETWEEN INTERVAL '24 HOURS' PRECEDING AND CURRENT ROW
    ) AS txn_count_24h,
    SUM(t.amount) OVER (
        PARTITION BY t.customer_id ORDER BY t.transaction_ts
        RANGE BETWEEN INTERVAL '24 HOURS' PRECEDING AND CURRENT ROW
    ) AS amount_sum_24h,
    AVG(t.amount) OVER (
        PARTITION BY t.customer_id ORDER BY t.transaction_ts
        RANGE BETWEEN INTERVAL '24 HOURS' PRECEDING AND CURRENT ROW
    ) AS amount_avg_24h,
    COUNT(*) OVER (
        PARTITION BY t.customer_id ORDER BY t.transaction_ts
        RANGE BETWEEN INTERVAL '7 DAYS' PRECEDING AND CURRENT ROW
    ) AS txn_count_7d,
    SUM(t.amount) OVER (
        PARTITION BY t.customer_id ORDER BY t.transaction_ts
        RANGE BETWEEN INTERVAL '7 DAYS' PRECEDING AND CURRENT ROW
    ) AS amount_sum_7d,
    AVG(t.amount) OVER (
        PARTITION BY t.customer_id ORDER BY t.transaction_ts
        RANGE BETWEEN INTERVAL '7 DAYS' PRECEDING AND CURRENT ROW
    ) AS amount_avg_7d
FROM TSHO_SWT_TOKYO_26.FRAUD.RAW_TRANSACTIONS t
LEFT JOIN TSHO_SWT_TOKYO_26.FRAUD.RAW_CUSTOMER_PROFILES c ON t.customer_id = c.customer_id
LEFT JOIN TSHO_SWT_TOKYO_26.FRAUD.RAW_MERCHANT_PROFILES m ON t.merchant_id = m.merchant_id;
