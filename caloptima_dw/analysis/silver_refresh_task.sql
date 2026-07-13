-- =============================================================================
-- Two-project dbt architecture:
--
--   CALOPTIMA_DW_DEV  (dev branch)  → DBT_REFRESH_TASK_DEV → FACETS_DEV
--   CALOPTIMA_DW      (main branch) → DBT_REFRESH_TASK_QA  → FACETS_QA
--                                   → DBT_REFRESH_TASK_PROD → FACETS_PROD
--
-- CI deploys automatically:
--   push → dev   → deploys CALOPTIMA_DW_DEV
--   PR   → main  → deploys CALOPTIMA_DW (stable)
--
-- Run this SQL in Snowsight as ACCOUNTADMIN to recreate or update the tasks.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Suspend full chain before any CREATE OR ALTER (root to child)
ALTER TASK IF EXISTS FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK   SUSPEND;
ALTER TASK IF EXISTS FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_DEV      SUSPEND;
ALTER TASK IF EXISTS FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_QA       SUSPEND;
ALTER TASK IF EXISTS FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_PROD     SUSPEND;
ALTER TASK IF EXISTS FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK SUSPEND;

-- =============================================================================
-- DBT_REFRESH_TASK_DEV — uses CALOPTIMA_DW_DEV (dev branch code)
-- =============================================================================
CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_DEV
    WAREHOUSE = WH_XS
    AFTER     FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK
    COMMENT   = 'Runs dbt Silver + DQ models against FACETS_DEV using dev branch code (CALOPTIMA_DW_DEV)'
AS
    EXECUTE DBT PROJECT ANALYTICS_ADMIN.PROJECTS.CALOPTIMA_DW_DEV
        ARGS = 'build --target dev --select provider_snapshot provider member eligibility rejected_providers dup_metrics dq_row_counts';

-- =============================================================================
-- DBT_REFRESH_TASK_QA — uses CALOPTIMA_DW (stable/main branch code)
-- =============================================================================
CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_QA
    WAREHOUSE = WH_XS
    AFTER     FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_DEV
    COMMENT   = 'Runs dbt Silver + DQ models against FACETS_QA using stable main branch code (CALOPTIMA_DW)'
AS
    EXECUTE DBT PROJECT ANALYTICS_ADMIN.PROJECTS.CALOPTIMA_DW
        ARGS = 'build --target qa --select provider_snapshot provider member eligibility rejected_providers dup_metrics dq_row_counts';

-- =============================================================================
-- DBT_REFRESH_TASK_PROD — uses CALOPTIMA_DW (stable/main branch code)
-- =============================================================================
CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_PROD
    WAREHOUSE = WH_XS
    AFTER     FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_QA
    COMMENT   = 'Runs dbt Silver + DQ models against FACETS_PROD using stable main branch code (CALOPTIMA_DW)'
AS
    EXECUTE DBT PROJECT ANALYTICS_ADMIN.PROJECTS.CALOPTIMA_DW
        ARGS = 'build --target prod --select provider_snapshot provider member eligibility rejected_providers dup_metrics dq_row_counts';

-- Gold models are views — they rebuild on query, no task execution needed.

-- Resume in reverse order (child to root)
ALTER TASK IF EXISTS FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK RESUME;
ALTER TASK IF EXISTS FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_PROD     RESUME;
ALTER TASK IF EXISTS FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_QA       RESUME;
ALTER TASK IF EXISTS FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_DEV      RESUME;
ALTER TASK IF EXISTS FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK   RESUME;

-- Verify all tasks are STARTED
SHOW TASKS IN SCHEMA FACETS_BRONZE.UTILS;
