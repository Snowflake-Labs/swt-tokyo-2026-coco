-- =============================================================================
-- 04_agent.sql
-- Cortex Agent: AI.SALES_AGENT
-- Uses SV_SALES via Cortex Analyst tool
-- IMPORTANT: A new version must be committed for the Agent to appear
--            in GET_LINEAGE output
-- =============================================================================

SET database_name = 'TSHO_SWT_TOKYO_26';
SET warehouse_name = 'TSHO_WH_XL';

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE IDENTIFIER($warehouse_name);
USE DATABASE IDENTIFIER($database_name);
USE SCHEMA AI;

CREATE OR REPLACE AGENT SALES_AGENT
  COMMENT = 'Sales analysis agent for Impact Radar demo. References SV_SALES.'
  FROM SPECIFICATION
  $$
  instructions:
    response: |
      You are a Sales Analyst assistant. Answer questions about orders,
      revenue, discounts, and customer segments using the SV_SALES semantic view.

      Rules:
      - Always cite the data source in your answer.
      - Do not fabricate numbers. If the data does not contain the answer, say so.
      - When asked about net revenue, note that it is calculated as gross_revenue - discount_amt.

  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "SalesAnalyst"
        description: "Analyzes sales data from SV_SALES semantic view"
    - tool_spec:
        type: "data_to_chart"
        name: "data_to_chart"
        description: "Generates visualizations from data"

  tool_resources:
    SalesAnalyst:
      semantic_view: "TSHO_SWT_TOKYO_26.AI.SV_SALES"
  $$;

ALTER AGENT SALES_AGENT COMMIT;
