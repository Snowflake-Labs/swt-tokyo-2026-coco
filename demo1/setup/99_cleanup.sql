-- =============================================================================
-- 99_cleanup.sql
-- Remove all Impact Radar demo objects
-- =============================================================================

SET database_name = 'TSHO_SWT_TOKYO_26';

USE ROLE ACCOUNTADMIN;
USE DATABASE IDENTIFIER($database_name);

-- Agent
DROP AGENT IF EXISTS AI.SALES_AGENT;

-- Semantic View
DROP SEMANTIC VIEW IF EXISTS AI.SV_SALES;

-- Dynamic Table
DROP DYNAMIC TABLE IF EXISTS MARTS.AGG_SALES_DAILY;

-- View
DROP VIEW IF EXISTS MARTS.FCT_ORDERS;

-- Tables
DROP TABLE IF EXISTS STAGING.STG_ORDERS;
DROP TABLE IF EXISTS STAGING.STG_CUSTOMERS;
