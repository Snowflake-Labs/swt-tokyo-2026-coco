-- =============================================================================
-- 04_create_model_objects.sql
-- Fraud scores table + enriched view + prediction log for Model Monitor
-- Inference uses mv.run() (native SQL, warehouse execution)
-- NOT mv.run_batch() (requires SPCS compute pool)
-- =============================================================================

SET database_name = 'TSHO_SWT_TOKYO_26';
SET warehouse_name = 'TSHO_WH_XL';

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE IDENTIFIER($warehouse_name);

-- Fraud score results table
CREATE TABLE IF NOT EXISTS TSHO_SWT_TOKYO_26.FRAUD.FRAUD_SCORES (
    transaction_id  STRING      NOT NULL,
    customer_id     STRING,
    fraud_score     FLOAT       COMMENT 'Predicted fraud probability (0-1)',
    prediction      INT         COMMENT '0=legitimate, 1=fraud',
    model_version   STRING      COMMENT 'Model Registry version identifier',
    threshold       FLOAT       DEFAULT 0.5 COMMENT 'Classification threshold used',
    scored_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'Batch inference results from fraud detection model (demo2)';

-- Prediction log for Model Monitor (with backdated timestamps for drift demo)
CREATE TABLE IF NOT EXISTS TSHO_SWT_TOKYO_26.FRAUD.PREDICTION_LOG (
    transaction_id  STRING      NOT NULL,
    customer_id     STRING,
    fraud_score     FLOAT,
    prediction      INT,
    is_fraud        INT         COMMENT 'Actual label (for accuracy monitoring)',
    model_version   STRING,
    scored_at       TIMESTAMP_NTZ COMMENT 'Backdated timestamp for drift demo'
) COMMENT = 'Prediction log with backdated timestamps for Model Monitor (demo2)';

-- Enriched view for Agent / app
CREATE OR REPLACE VIEW TSHO_SWT_TOKYO_26.FRAUD.FRAUD_SCORES_ENRICHED AS
SELECT
    fs.transaction_id,
    fs.customer_id,
    fs.fraud_score,
    fs.prediction,
    fs.model_version,
    fs.threshold,
    fs.scored_at,
    ff.amount,
    ff.txn_country,
    ff.channel,
    ff.customer_country,
    ff.account_age_days,
    ff.customer_segment,
    ff.merchant_category,
    ff.merchant_risk_level,
    ff.country_changed_flag,
    ff.high_risk_merchant_flag,
    ff.txn_count_1h,
    ff.amount_sum_1h,
    ff.txn_count_24h,
    ff.amount_sum_24h,
    ff.txn_count_7d,
    ff.amount_sum_7d
FROM TSHO_SWT_TOKYO_26.FRAUD.FRAUD_SCORES fs
LEFT JOIN TSHO_SWT_TOKYO_26.FRAUD.FRAUD_FEATURES ff
    ON fs.transaction_id = ff.transaction_id;
