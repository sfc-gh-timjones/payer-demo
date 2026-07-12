-- =============================================================
-- CalOptima Agent Demo - Step 4: Cortex Agent
-- FACETS_PROD.AGENTS.CALOPTIMA_AGENT
-- Tools: Cortex Analyst (CalOptimaAnalyst) + data_to_chart
-- =============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WH_XS;
USE SCHEMA FACETS_PROD.AGENTS;

CREATE OR REPLACE AGENT FACETS_PROD.AGENTS.CALOPTIMA_AGENT
  COMMENT = 'CalOptima Enrollment Intelligence Agent'
  PROFILE = '{"display_name": "CalOptima Enrollment Intelligence", "color": "blue"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: claude-sonnet-4-6

  orchestration:
    budget:
      seconds: 360
      tokens: 32000

  instructions:
    system: >
      You are the CalOptima Enrollment Intelligence assistant. You help healthcare operations
      teams answer questions about member enrollment, plan assignment, PCP
      attribution, and Medicaid eligibility for CalOptima Health's Orange
      County, CA membership. Always cite specific numbers from the data
      and offer to visualize results when presenting counts or distributions.
    orchestration: >
      For all quantitative questions about member counts, plan enrollment,
      PCP assignment rates, Medicaid aid categories, geographic distribution,
      and demographic breakdowns — use CalOptimaAnalyst.
      Do not fabricate statistics; always query the data.
      When presenting tabular results with 3+ rows, offer to generate a chart.
    sample_questions:
      - question: "How many active members are enrolled in each plan type?"
        answer: "Uses CalOptimaAnalyst to query active enrollment grouped by plan type."
      - question: "What is our PCP assignment rate for active members?"
        answer: "Uses CalOptimaAnalyst to compute the percentage of active members with an assigned PCP."
      - question: "Which cities have the most members assigned to PCPs?"
        answer: "Uses CalOptimaAnalyst to count members by PCP practice city in Orange County."

  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "CalOptimaAnalyst"
        description: "Text-to-SQL over the CalOptima member enrollment semantic view. Use for member counts, plan enrollment, PCP assignment, demographics, and Medicaid eligibility questions."

    - tool_spec:
        type: "data_to_chart"
        name: "data_to_chart"
        description: "Generates a chart visualization from tabular query results."

  tool_resources:
    CalOptimaAnalyst:
      semantic_view: "FACETS_PROD.AGENTS.CALOPTIMA_MEMBER_SV"
      execution_environment:
        type: "warehouse"
        warehouse: "WH_XS"
  $$;

-- Register with Snowflake Intelligence so it appears in the SI UI
ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT
  ADD AGENT FACETS_PROD.AGENTS.CALOPTIMA_AGENT;
