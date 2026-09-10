-- =============================================================================
-- 00_account_prerequisites.sql
-- ACCOUNTADMIN で1回だけ実行する初期設定
-- 作成: ロール、Adaptive Warehouse、権限付与
-- Compute Pool は不要 (App Runtime を使用)
-- =============================================================================

SET database_name = 'TSHO_SWT_TOKYO_26';
SET warehouse_name = 'TSHO_WH_XL';
SET role_name = 'FRAUD_DEMO_ROLE';

USE ROLE ACCOUNTADMIN;

-- Demo role
CREATE ROLE IF NOT EXISTS IDENTIFIER($role_name);
GRANT ROLE IDENTIFIER($role_name) TO ROLE SYSADMIN;

-- Adaptive Warehouse (推論・クエリ用)
-- SIZE / MIN_CLUSTER_COUNT / MAX_CLUSTER_COUNT / SCALING_POLICY は設定不可
-- 課金はクエリ単位。
-- 学習用には Adaptive を使わない (Snowpark-optimized が推奨)
CREATE ADAPTIVE WAREHOUSE IF NOT EXISTS FRAUD_DEMO_ADAPTIVE_WH
    COMMENT = 'Fraud demo adaptive warehouse for inference and queries';

GRANT USAGE ON WAREHOUSE FRAUD_DEMO_ADAPTIVE_WH TO ROLE IDENTIFIER($role_name);
GRANT OPERATE ON WAREHOUSE FRAUD_DEMO_ADAPTIVE_WH TO ROLE IDENTIFIER($role_name);

-- TSHO_WH_XL は学習・重い処理用に引き続き利用 (既存)
GRANT USAGE ON WAREHOUSE IDENTIFIER($warehouse_name) TO ROLE IDENTIFIER($role_name);

-- Database / schema privileges
GRANT USAGE ON DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($role_name);

-- Schemas shared with demo1 (may already exist)
CREATE SCHEMA IF NOT EXISTS TSHO_SWT_TOKYO_26.STAGING
    COMMENT = 'Staging layer (shared with demo1)';
CREATE SCHEMA IF NOT EXISTS TSHO_SWT_TOKYO_26.MARTS
    COMMENT = 'Mart layer (shared with demo1)';
GRANT ALL ON SCHEMA TSHO_SWT_TOKYO_26.STAGING TO ROLE IDENTIFIER($role_name);
GRANT ALL ON SCHEMA TSHO_SWT_TOKYO_26.MARTS TO ROLE IDENTIFIER($role_name);

-- Create AI schema (shared with demo1, may already exist)
CREATE SCHEMA IF NOT EXISTS TSHO_SWT_TOKYO_26.AI
    COMMENT = 'Cortex Agent and Semantic View objects';
GRANT ALL ON SCHEMA TSHO_SWT_TOKYO_26.AI TO ROLE IDENTIFIER($role_name);

-- Create demo-specific schemas
CREATE SCHEMA IF NOT EXISTS TSHO_SWT_TOKYO_26.FRAUD
    COMMENT = 'Fraud detection demo2 objects';
GRANT ALL ON SCHEMA TSHO_SWT_TOKYO_26.FRAUD TO ROLE IDENTIFIER($role_name);

CREATE SCHEMA IF NOT EXISTS TSHO_SWT_TOKYO_26.FRAUD_ML
    COMMENT = 'Fraud detection ML objects (Feature Store, Model Registry)';
GRANT ALL ON SCHEMA TSHO_SWT_TOKYO_26.FRAUD_ML TO ROLE IDENTIFIER($role_name);

-- Cortex / ML privileges
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE IDENTIFIER($role_name);
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE IDENTIFIER($role_name);

-- Grant role to current user (CURRENT_USER() not allowed in GRANT TO USER)
SET current_user_name = (SELECT CURRENT_USER());
GRANT ROLE IDENTIFIER($role_name) TO USER IDENTIFIER($current_user_name);
