-- =============================================================================
-- 01_staging_tables.sql
-- Staging tables with synthetic data for Impact Radar demo
-- =============================================================================

-- Variables (override with SET before running, or via run_setup.py)
SET database_name = 'TSHO_SWT_TOKYO_26';
SET warehouse_name = 'TSHO_WH_XL';

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE IDENTIFIER($warehouse_name);
USE DATABASE IDENTIFIER($database_name);
USE SCHEMA STAGING;

-- ---------------------------------------------------------------------------
-- STG_CUSTOMERS: 500 synthetic customers
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS STG_CUSTOMERS (
    customer_id   INT,
    customer_name STRING,
    region        STRING,
    segment       STRING,
    created_at    DATE
)
COMMENT = 'Synthetic customer staging data for Impact Radar demo';

-- Seed data (idempotent: truncate + insert)
TRUNCATE TABLE IF EXISTS STG_CUSTOMERS;

INSERT INTO STG_CUSTOMERS
SELECT
    SEQ4()                                        AS customer_id,
    'CUST-' || LPAD(SEQ4()::STRING, 5, '0')      AS customer_name,
    CASE MOD(SEQ4(), 5)
        WHEN 0 THEN 'APAC'
        WHEN 1 THEN 'EMEA'
        WHEN 2 THEN 'NA-EAST'
        WHEN 3 THEN 'NA-WEST'
        ELSE 'LATAM'
    END                                           AS region,
    CASE MOD(SEQ4(), 3)
        WHEN 0 THEN 'Enterprise'
        WHEN 1 THEN 'Mid-Market'
        ELSE 'SMB'
    END                                           AS segment,
    DATEADD(DAY, -MOD(SEQ4() * 7, 1000), '2025-06-01')  AS created_at
FROM TABLE(GENERATOR(ROWCOUNT => 500));

-- ---------------------------------------------------------------------------
-- STG_ORDERS: 5,000 synthetic orders
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS STG_ORDERS (
    order_id        INT,
    customer_id     INT,
    order_date      DATE,
    product         STRING,
    quantity        INT,
    unit_price      FLOAT,
    discount_amt    FLOAT,
    legacy_status_cd STRING,
    currency        STRING
)
COMMENT = 'Synthetic order staging data for Impact Radar demo';

TRUNCATE TABLE IF EXISTS STG_ORDERS;

INSERT INTO STG_ORDERS
SELECT
    SEQ4()                                        AS order_id,
    MOD(SEQ4() * 37, 500)                         AS customer_id,
    DATEADD(DAY, -MOD(SEQ4(), 180), '2025-06-30') AS order_date,
    CASE MOD(SEQ4(), 6)
        WHEN 0 THEN 'Widget-A'
        WHEN 1 THEN 'Widget-B'
        WHEN 2 THEN 'Gadget-X'
        WHEN 3 THEN 'Gadget-Y'
        WHEN 4 THEN 'Service-Pro'
        ELSE 'Service-Basic'
    END                                           AS product,
    MOD(SEQ4(), 20) + 1                           AS quantity,
    ROUND(50 + MOD(SEQ4() * 13, 450)::FLOAT, 2)  AS unit_price,
    ROUND(MOD(SEQ4() * 3, 50)::FLOAT, 2)         AS discount_amt,
    CASE MOD(SEQ4(), 4)
        WHEN 0 THEN 'A'
        WHEN 1 THEN 'B'
        WHEN 2 THEN 'C'
        ELSE 'D'
    END                                           AS legacy_status_cd,
    'USD'                                         AS currency
FROM TABLE(GENERATOR(ROWCOUNT => 5000));
