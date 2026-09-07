-- =============================================================================
-- 03_create_feature_store.sql
-- Feature Store (offline only, no Online Feature Store)
-- =============================================================================

SET database_name = 'TSHO_SWT_TOKYO_26';
SET warehouse_name = 'TSHO_WH_XL';

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE IDENTIFIER($warehouse_name);

-- Training dataset snapshot
CREATE TABLE IF NOT EXISTS TSHO_SWT_TOKYO_26.FRAUD_ML.TRAINING_DATASET (
    transaction_id        STRING,
    customer_id           STRING,
    amount                FLOAT,
    txn_country           STRING,
    channel               STRING,
    customer_country      STRING,
    account_age_days      INT,
    customer_segment      STRING,
    merchant_country      STRING,
    merchant_category     STRING,
    merchant_risk_level   STRING,
    country_changed_flag  INT,
    high_risk_merchant_flag INT,
    txn_count_1h          INT,
    amount_sum_1h         FLOAT,
    amount_avg_1h         FLOAT,
    txn_count_24h         INT,
    amount_sum_24h        FLOAT,
    amount_avg_24h        FLOAT,
    txn_count_7d          INT,
    amount_sum_7d         FLOAT,
    amount_avg_7d         FLOAT,
    is_fraud              INT,
    training_ts           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'Snapshot of training data for reproducibility (demo2)';
