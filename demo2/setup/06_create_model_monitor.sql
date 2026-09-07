-- =============================================================================
-- 06_create_model_monitor.sql
-- Model Monitor for drift detection
-- Requires: Model registered in TSHO_SWT_TOKYO_26.FRAUD_ML
--           PREDICTION_LOG table populated with backdated data
-- =============================================================================

SET database_name = 'TSHO_SWT_TOKYO_26';
SET warehouse_name = 'TSHO_WH_XL';

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE IDENTIFIER($warehouse_name);

-- Model Monitor is created via Python (snowflake.ml.monitoring)
-- This SQL creates the supporting views

-- View: prediction log with baseline flag
CREATE OR REPLACE VIEW TSHO_SWT_TOKYO_26.FRAUD.PREDICTION_LOG_WITH_BASELINE AS
SELECT
    *,
    CASE
        WHEN scored_at < DATEADD(DAY, -30, CURRENT_TIMESTAMP())
        THEN 'baseline'
        ELSE 'current'
    END AS period
FROM TSHO_SWT_TOKYO_26.FRAUD.PREDICTION_LOG;

-- View: drift summary by day
CREATE OR REPLACE VIEW TSHO_SWT_TOKYO_26.FRAUD.DRIFT_DAILY_SUMMARY AS
SELECT
    DATE(scored_at) AS score_date,
    COUNT(*) AS prediction_count,
    AVG(fraud_score) AS avg_score,
    SUM(prediction) AS flagged_count,
    AVG(is_fraud::FLOAT) AS actual_fraud_rate,
    AVG(prediction::FLOAT) AS predicted_fraud_rate
FROM TSHO_SWT_TOKYO_26.FRAUD.PREDICTION_LOG
GROUP BY score_date
ORDER BY score_date;
