-- =============================================================================
-- 05_create_agent_objects.sql
-- Cortex Search Service + Cortex Agent
-- Uses CREATE AGENT ... FROM SPECIFICATION (verified syntax)
-- =============================================================================

SET database_name = 'TSHO_SWT_TOKYO_26';
SET warehouse_name = 'TSHO_WH_XL';

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE IDENTIFIER($warehouse_name);
USE SCHEMA TSHO_SWT_TOKYO_26.FRAUD;

-- Policy documents table for Cortex Search
CREATE TABLE IF NOT EXISTS POLICY_DOCUMENTS (
    doc_id     STRING,
    title      STRING,
    content    STRING,
    doc_type   STRING,
    updated_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'Fraud policy and investigation documents (demo2)';

-- Cortex Search Service (CREATE OR REPLACE: no IF NOT EXISTS for search services)
CREATE OR REPLACE CORTEX SEARCH SERVICE FRAUD_POLICY_SEARCH
    ON content
    ATTRIBUTES doc_type, title
    WAREHOUSE = TSHO_WH_XL
    TARGET_LAG = '1 hour'
    COMMENT = 'Search service for fraud policies (demo2)'
AS (
    SELECT doc_id, title, content, doc_type
    FROM POLICY_DOCUMENTS
);

-- Semantic View (CREATE OR REPLACE: no IF NOT EXISTS for semantic views)
CREATE OR REPLACE SEMANTIC VIEW TSHO_SWT_TOKYO_26.AI.SV_FRAUD_SCORES
  TABLES (
    scores AS TSHO_SWT_TOKYO_26.FRAUD.FRAUD_SCORES_ENRICHED
      PRIMARY KEY (transaction_id)
  )
  FACTS (
    scores.amount AS amount COMMENT = 'Transaction amount',
    scores.fraud_score AS fraud_score COMMENT = 'Predicted fraud probability (0-1)',
    scores.txn_count_1h AS txn_count_1h COMMENT = 'Transaction count in past 1h',
    scores.amount_sum_24h AS amount_sum_24h COMMENT = 'Amount sum in past 24h',
    scores.txn_count_7d AS txn_count_7d COMMENT = 'Transaction count in past 7d'
  )
  DIMENSIONS (
    scores.transaction_id AS transaction_id COMMENT = 'Unique transaction ID',
    scores.customer_id AS customer_id COMMENT = 'Customer UUID',
    scores.prediction AS prediction COMMENT = '0=legitimate, 1=fraud',
    scores.model_version AS model_version COMMENT = 'Model version',
    scores.txn_country AS txn_country COMMENT = 'Transaction country',
    scores.channel AS channel COMMENT = 'Channel (web, mobile, pos, atm)',
    scores.customer_segment AS customer_segment COMMENT = 'Customer segment',
    scores.merchant_category AS merchant_category COMMENT = 'Merchant category',
    scores.merchant_risk_level AS merchant_risk_level COMMENT = 'Merchant risk (low/medium/high)',
    scores.country_changed_flag AS country_changed_flag COMMENT = 'Cross-border flag',
    scores.high_risk_merchant_flag AS high_risk_merchant_flag COMMENT = 'High-risk merchant flag'
  )
  METRICS (
    scores.total_fraud_count AS SUM(scores.fraud_score) COMMENT = 'Sum of fraud scores',
    scores.avg_fraud_score AS AVG(scores.fraud_score) COMMENT = 'Average fraud score',
    scores.order_count AS COUNT(scores.transaction_id) COMMENT = 'Total transactions'
  )
  COMMENT = 'Fraud scores semantic view for Cortex Agent (demo2)';

-- Cortex Agent (CREATE OR REPLACE: no IF NOT EXISTS for agents)
CREATE OR REPLACE AGENT TSHO_SWT_TOKYO_26.AI.FRAUD_INVESTIGATOR
  COMMENT = 'Fraud investigation agent (demo2)'
  FROM SPECIFICATION
  $$
  instructions:
    response: |
      You are a Fraud Investigation Assistant. Answer questions about
      fraud scores, transaction patterns, and investigation procedures.
      Always cite the data source. Never present a fraud score as a
      definitive criminal judgment. If data is insufficient, say so.

  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "FraudAnalyst"
        description: "Analyzes fraud scores and transaction data"
    - tool_spec:
        type: "cortex_search"
        name: "PolicySearch"
        description: "Searches fraud investigation policies and procedures"
    - tool_spec:
        type: "data_to_chart"
        name: "data_to_chart"
        description: "Generates visualizations from data"

  tool_resources:
    FraudAnalyst:
      semantic_view: "TSHO_SWT_TOKYO_26.AI.SV_FRAUD_SCORES"
    PolicySearch:
      search_service: "TSHO_SWT_TOKYO_26.FRAUD.FRAUD_POLICY_SEARCH"
  $$;

-- Commit version for lineage registration
ALTER AGENT TSHO_SWT_TOKYO_26.AI.FRAUD_INVESTIGATOR COMMIT;

-- Recreate LIVE version so Snowsight Preview tab works
ALTER AGENT TSHO_SWT_TOKYO_26.AI.FRAUD_INVESTIGATOR ADD LIVE VERSION FROM LAST;
