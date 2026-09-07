-- =============================================================================
-- 03_semantic_view.sql
-- Semantic View: AI.SV_SALES
-- NET_REVENUE metric intentionally references DISCOUNT_AMT
-- so removing DISCOUNT_AMT from FCT_ORDERS breaks the Agent silently
-- =============================================================================

SET database_name = 'TSHO_SWT_TOKYO_26';
SET warehouse_name = 'TSHO_WH_XL';

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE IDENTIFIER($warehouse_name);
USE DATABASE IDENTIFIER($database_name);
USE SCHEMA AI;

CREATE OR REPLACE SEMANTIC VIEW SV_SALES
  TABLES (
    orders AS TSHO_SWT_TOKYO_26.MARTS.FCT_ORDERS
      PRIMARY KEY (order_id)
  )
  FACTS (
    orders.quantity AS quantity COMMENT = 'Units ordered',
    orders.unit_price AS unit_price COMMENT = 'Price per unit in USD',
    orders.gross_revenue AS gross_revenue COMMENT = 'quantity * unit_price',
    orders.discount_amt AS discount_amt COMMENT = 'Applied discount in USD',
    orders.net_revenue AS net_revenue COMMENT = 'gross_revenue - discount_amt'
  )
  DIMENSIONS (
    orders.order_id AS order_id COMMENT = 'Unique order identifier',
    orders.customer_id AS customer_id COMMENT = 'Customer FK',
    orders.customer_name AS customer_name COMMENT = 'Customer display name',
    orders.region AS region COMMENT = 'Sales region (APAC, EMEA, NA-EAST, NA-WEST, LATAM)',
    orders.segment AS segment COMMENT = 'Customer segment (Enterprise, Mid-Market, SMB)',
    orders.order_date AS order_date COMMENT = 'Date of the order',
    orders.product AS product COMMENT = 'Product name'
  )
  METRICS (
    orders.total_net_revenue AS SUM(orders.net_revenue) COMMENT = 'Sum of net revenue. Depends on DISCOUNT_AMT.',
    orders.total_gross_revenue AS SUM(orders.gross_revenue) COMMENT = 'Sum of gross revenue before discounts',
    orders.total_discount AS SUM(orders.discount_amt) COMMENT = 'Sum of all discounts applied',
    orders.order_count AS COUNT(orders.order_id) COMMENT = 'Number of orders',
    orders.avg_order_value AS AVG(orders.net_revenue) COMMENT = 'Average net revenue per order'
  )
  COMMENT = 'Sales semantic view for Impact Radar demo. NET_REVENUE uses DISCOUNT_AMT.';
