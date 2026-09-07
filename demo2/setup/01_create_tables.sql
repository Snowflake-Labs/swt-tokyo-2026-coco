-- =============================================================================
-- 01_create_tables.sql
-- Staging tables + Iceberg tables in TSHO_SWT_TOKYO_26.FRAUD
-- Does NOT touch FRAUD_DEMO or any other database
-- =============================================================================

SET database_name = 'TSHO_SWT_TOKYO_26';
SET warehouse_name = 'TSHO_WH_XL';

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE IDENTIFIER($warehouse_name);
USE DATABASE IDENTIFIER($database_name);
USE SCHEMA FRAUD;

-- ---------------------------------------------------------------------------
-- Raw tables (Iceberg-managed where possible, standard table fallback)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS RAW_TRANSACTIONS (
    transaction_id STRING,
    customer_id    STRING,
    merchant_id    STRING,
    transaction_ts TIMESTAMP_NTZ,
    amount         FLOAT,
    currency       STRING,
    country        STRING,
    channel        STRING,
    device_id      STRING,
    is_fraud       INT
) COMMENT = 'Raw transaction data for fraud demo2';

CREATE TABLE IF NOT EXISTS RAW_CUSTOMER_PROFILES (
    customer_id      STRING,
    country          STRING,
    account_age_days INT,
    customer_segment STRING
) COMMENT = 'Customer profiles for fraud demo2';

CREATE TABLE IF NOT EXISTS RAW_MERCHANT_PROFILES (
    merchant_id       STRING,
    merchant_country  STRING,
    merchant_category STRING,
    risk_level        STRING
) COMMENT = 'Merchant profiles for fraud demo2';

-- ---------------------------------------------------------------------------
-- Staging stage for data upload
-- ---------------------------------------------------------------------------

CREATE STAGE IF NOT EXISTS DATA_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for synthetic data upload (fraud demo2)';

CREATE STAGE IF NOT EXISTS AGENT_DOCS_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for agent policy documents (fraud demo2)';
