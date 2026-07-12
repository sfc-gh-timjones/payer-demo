-- =============================================================================
-- FILE: silver_refresh_tasks.sql
-- PURPOSE: Sequential task chain that refreshes DEV → QA → PROD Silver models
--          after each Openflow CDC batch, then runs SCD2 stream refresh.
--
-- Full chain:
--   FACETS_INCREMENTAL_TASK          (Openflow CDC loads Bronze)
--       → DBT_REFRESH_TASK_DEV       (dbt build --target dev  → FACETS_DEV)
--           → DBT_REFRESH_TASK_QA    (dbt build --target qa   → FACETS_QA)
--               → DBT_REFRESH_TASK_PROD  (dbt build --target prod → FACETS_PROD)
--                   → PROVIDER_SCD2_STREAM_TASK  (Stream/Task SCD2, if stream has data)
--
-- All three dbt tasks share the same Bronze source (FACETS_BRONZE).
-- Sequential ordering ensures consistent data across environments and a clean
-- end-to-end pipeline with a single failure point.
--
-- Requires: snow dbt deploy CALOPTIMA_DW run beforehand.
-- Run this SQL in Snowsight as ACCOUNTADMIN.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WH_XS;

-- =============================================================================
-- STEP 1: DEV refresh — fires immediately after Openflow CDC batch completes
-- =============================================================================

CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_DEV
    WAREHOUSE = WH_XS
    AFTER     FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK
    COMMENT   = 'Runs dbt Silver + DQ models against FACETS_DEV after each CDC batch'
AS
    EXECUTE DBT PROJECT ANALYTICS_ADMIN.PROJECTS.CALOPTIMA_DW
        ARGS = 'build --target dev --select provider_snapshot,provider,member,eligibility,rejected_providers,dup_metrics,dq_row_counts';


-- =============================================================================
-- STEP 2: QA refresh — runs after DEV completes
-- =============================================================================

CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_QA
    WAREHOUSE = WH_XS
    AFTER     FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_DEV
    COMMENT   = 'Runs dbt Silver + DQ models against FACETS_QA after DEV refresh completes'
AS
    EXECUTE DBT PROJECT ANALYTICS_ADMIN.PROJECTS.CALOPTIMA_DW
        ARGS = 'build --target qa --select provider_snapshot,provider,member,eligibility,rejected_providers,dup_metrics,dq_row_counts';


-- =============================================================================
-- STEP 3: PROD refresh — runs after QA completes
-- =============================================================================

CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_PROD
    WAREHOUSE = WH_XS
    AFTER     FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_QA
    COMMENT   = 'Runs dbt Silver + DQ models against FACETS_PROD after QA refresh completes'
AS
    EXECUTE DBT PROJECT ANALYTICS_ADMIN.PROJECTS.CALOPTIMA_DW
        ARGS = 'build --target prod --select provider_snapshot,provider,member,eligibility,rejected_providers,dup_metrics,dq_row_counts';

-- Gold models are views — they rebuild on query, no task execution needed.


-- =============================================================================
-- Resume all tasks (parent FACETS_INCREMENTAL_TASK must also be resumed)
-- =============================================================================

-- ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_DEV  RESUME;
-- ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_QA   RESUME;
-- ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_PROD RESUME;


-- =============================================================================
-- Check task history
-- =============================================================================

-- SELECT * FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
--     SCHEDULED_TIME_RANGE_START => DATEADD('hour', -1, CURRENT_TIMESTAMP()),
--     TASK_NAME => 'DBT_REFRESH_TASK_DEV'
-- )) ORDER BY SCHEDULED_TIME DESC;
