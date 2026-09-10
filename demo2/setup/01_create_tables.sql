-- =============================================================================
-- 01_create_tables.sql
-- Managed Iceberg tables in TSHO_SWT_TOKYO_26.FRAUD (Snowflake storage)
-- EXTERNAL_VOLUME = SNOWFLAKE_MANAGED → External Volume 設定不要
-- =============================================================================

SET database_name = 'TSHO_SWT_TOKYO_26';
SET warehouse_name = 'TSHO_WH_XL';

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE IDENTIFIER($warehouse_name);
USE DATABASE IDENTIFIER($database_name);
USE SCHEMA FRAUD;

-- ---------------------------------------------------------------------------
-- Raw tables (Managed Iceberg — Snowflake storage)
-- ---------------------------------------------------------------------------

CREATE ICEBERG TABLE IF NOT EXISTS RAW_TRANSACTIONS (
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
)
    CATALOG = 'SNOWFLAKE'
    EXTERNAL_VOLUME = 'SNOWFLAKE_MANAGED'
    COMMENT = 'Raw transaction data for fraud demo2 (Managed Iceberg)';

CREATE ICEBERG TABLE IF NOT EXISTS RAW_CUSTOMER_PROFILES (
    customer_id      STRING,
    country          STRING,
    account_age_days INT,
    customer_segment STRING
)
    CATALOG = 'SNOWFLAKE'
    EXTERNAL_VOLUME = 'SNOWFLAKE_MANAGED'
    COMMENT = 'Customer profiles for fraud demo2 (Managed Iceberg)';

CREATE ICEBERG TABLE IF NOT EXISTS RAW_MERCHANT_PROFILES (
    merchant_id       STRING,
    merchant_country  STRING,
    merchant_category STRING,
    risk_level        STRING
)
    CATALOG = 'SNOWFLAKE'
    EXTERNAL_VOLUME = 'SNOWFLAKE_MANAGED'
    COMMENT = 'Merchant profiles for fraud demo2 (Managed Iceberg)';

-- ---------------------------------------------------------------------------
-- Staging stage for data upload
-- ---------------------------------------------------------------------------

CREATE STAGE IF NOT EXISTS DATA_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for synthetic data upload (fraud demo2)';

CREATE STAGE IF NOT EXISTS AGENT_DOCS_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for agent policy documents (fraud demo2)';
