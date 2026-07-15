-- =============================================================================
-- FILE: 04_rebuild_dbt_tasks.sql
-- PURPOSE: Creates the three DBT_REFRESH_TASK_* tasks as standalone tasks
--          that can be manually triggered via EXECUTE TASK.
--
-- These tasks run dbt build against each environment:
--   DBT_REFRESH_TASK_DEV  → CALOPTIMA_DW_DEV (dev branch) → FACETS_DEV
--   DBT_REFRESH_TASK_QA   → CALOPTIMA_DW     (main branch) → FACETS_QA
--   DBT_REFRESH_TASK_PROD → CALOPTIMA_DW     (main branch) → FACETS_PROD
--
-- NOTE: No AFTER clause — tasks are standalone here. Once the stream pipeline
--       is in place, silver_refresh_tasks.sql wires them into the DAG with
--       AFTER PROVIDER_SCD2_STREAM_TASK_*.
-- =============================================================================

USE ROLE      ACCOUNTADMIN;
USE WAREHOUSE WH_XS;

-- =============================================================================
-- Create tasks
-- =============================================================================

-- DEV → FACETS_DEV (uses CALOPTIMA_DW_DEV — dev branch code)
CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_DEV
    WAREHOUSE = WH_XS
    COMMENT   = 'Runs dbt build against FACETS_DEV using CALOPTIMA_DW_DEV project'
AS
    EXECUTE DBT PROJECT ANALYTICS_ADMIN.PROJECTS.CALOPTIMA_DW_DEV
        ARGS = 'build --target dev --select provider_snapshot provider member eligibility rejected_providers dup_metrics dq_row_counts';

-- QA → FACETS_QA (uses CALOPTIMA_DW — stable/main code)
CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_QA
    WAREHOUSE = WH_XS
    COMMENT   = 'Runs dbt build against FACETS_QA using CALOPTIMA_DW project'
AS
    EXECUTE DBT PROJECT ANALYTICS_ADMIN.PROJECTS.CALOPTIMA_DW
        ARGS = 'build --target qa --select provider_snapshot provider member eligibility rejected_providers dup_metrics dq_row_counts';

-- PROD → FACETS_PROD (uses CALOPTIMA_DW — stable/main code)
CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_PROD
    WAREHOUSE = WH_XS
    COMMENT   = 'Runs dbt build against FACETS_PROD using CALOPTIMA_DW project'
AS
    EXECUTE DBT PROJECT ANALYTICS_ADMIN.PROJECTS.CALOPTIMA_DW
        ARGS = 'build --target prod --select provider_snapshot provider member eligibility rejected_providers dup_metrics dq_row_counts';

-- =============================================================================
-- Verify
-- =============================================================================

SHOW TASKS LIKE 'DBT_REFRESH_TASK%' IN SCHEMA FACETS_BRONZE.UTILS;

-- =============================================================================
-- Manual trigger (tasks are suspended by default after CREATE OR REPLACE)
-- Run each individually as needed:
-- =============================================================================

-- EXECUTE TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_DEV;
-- EXECUTE TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_QA;
-- EXECUTE TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_PROD;
