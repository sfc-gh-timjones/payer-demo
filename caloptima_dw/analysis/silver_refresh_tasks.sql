-- =============================================================================
-- FILE: silver_refresh_tasks.sql
-- PURPOSE: Event-driven task DAGs that process Bronze changes the moment Openflow
--          commits. Three independent DAGs, one per environment.
--
-- Architecture (4 independent DAGs):
--
--   DAG 1 — Openflow CDC (scheduled, standalone)
--   FACETS_INCREMENTAL_TASK  (45 min schedule)
--
--   DAG 2 — DEV pipeline (triggered when Bronze changes land)
--   PROVIDER_SCD2_STREAM_TASK_DEV  (triggered root: fires when DEV stream has data)
--     └─ DBT_REFRESH_TASK_DEV      (dbt build --target dev → FACETS_DEV)
--
--   DAG 3 — QA pipeline (triggered when Bronze changes land)
--   PROVIDER_SCD2_STREAM_TASK_QA   (triggered root: fires when QA stream has data)
--     └─ DBT_REFRESH_TASK_QA       (dbt build --target qa  → FACETS_QA)
--
--   DAG 4 — PROD pipeline (triggered when Bronze changes land)
--   PROVIDER_SCD2_STREAM_TASK_PROD (triggered root: fires when PROD stream has data)
--     └─ DBT_REFRESH_TASK_PROD     (dbt build --target prod → FACETS_PROD)
--
-- Why triggered (not scheduled after Openflow):
--   Openflow's Snowflake task reports success before its runtime commits Bronze.
--   Chaining dbt AFTER the Openflow task caused dbt to run before data landed.
--   Triggered stream tasks fire the moment Snowflake detects the Bronze commit,
--   guaranteeing dbt snapshot sees the same data the stream task just processed.
--
-- Requires: streams on Bronze CMC_PRPR_PROV (DEV/QA/PROD variants), dbt project
--           objects CALOPTIMA_DW + CALOPTIMA_DW_DEV deployed via CI.
-- Run this SQL in Snowsight as ACCOUNTADMIN.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WH_XS;

-- =============================================================================
-- STEP 1: Suspend all tasks before altering
-- =============================================================================

ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK          SUSPEND;
ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_DEV    SUSPEND;
ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_QA     SUSPEND;
ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_PROD   SUSPEND;
ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_DEV             SUSPEND;
ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_QA              SUSPEND;
ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_PROD            SUSPEND;


-- =============================================================================
-- STEP 2: DEV pipeline — stream task (triggered root) + dbt child
-- =============================================================================

CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_DEV
    WAREHOUSE = WH_XS
    COMMENT   = 'SCD2 refresh for FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM — triggered when Bronze CMC_PRPR_PROV changes'
    WHEN      SYSTEM$STREAM_HAS_DATA('FACETS_BRONZE.UTILS.PRPR_PROV_CHANGE_STREAM')
AS
    CALL FACETS_DEV.SILVER.SP_PROVIDER_SCD2_STREAM_REFRESH();

CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_DEV
    WAREHOUSE = WH_XS
    COMMENT   = 'Runs dbt build against FACETS_DEV after Bronze changes confirmed in DEV stream'
    AFTER     FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_DEV
AS
    EXECUTE DBT PROJECT ANALYTICS_ADMIN.PROJECTS.CALOPTIMA_DW_DEV
        ARGS = 'build --target dev --select provider_snapshot provider member eligibility rejected_providers dup_metrics dq_row_counts';


-- =============================================================================
-- STEP 3: QA pipeline — stream task (triggered root) + dbt child
-- =============================================================================

CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_QA
    WAREHOUSE = WH_XS
    COMMENT   = 'SCD2 refresh for FACETS_QA.SILVER.PROVIDER_SCD2_VIA_STREAM — triggered when Bronze CMC_PRPR_PROV changes'
    WHEN      SYSTEM$STREAM_HAS_DATA('FACETS_BRONZE.UTILS.PRPR_PROV_CHANGE_STREAM_QA')
AS
    CALL FACETS_QA.SILVER.SP_PROVIDER_SCD2_STREAM_REFRESH();

CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_QA
    WAREHOUSE = WH_XS
    COMMENT   = 'Runs dbt build against FACETS_QA after Bronze changes confirmed in QA stream'
    AFTER     FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_QA
AS
    EXECUTE DBT PROJECT ANALYTICS_ADMIN.PROJECTS.CALOPTIMA_DW
        ARGS = 'build --target qa --select provider_snapshot provider member eligibility rejected_providers dup_metrics dq_row_counts';


-- =============================================================================
-- STEP 4: PROD pipeline — stream task (triggered root) + dbt child
-- =============================================================================

CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_PROD
    WAREHOUSE = WH_XS
    COMMENT   = 'SCD2 refresh for FACETS_PROD.SILVER.PROVIDER_SCD2_VIA_STREAM — triggered when Bronze CMC_PRPR_PROV changes'
    WHEN      SYSTEM$STREAM_HAS_DATA('FACETS_BRONZE.UTILS.PRPR_PROV_CHANGE_STREAM_PROD')
AS
    CALL FACETS_PROD.SILVER.SP_PROVIDER_SCD2_STREAM_REFRESH();

CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_PROD
    WAREHOUSE = WH_XS
    COMMENT   = 'Runs dbt build against FACETS_PROD after Bronze changes confirmed in PROD stream'
    AFTER     FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_PROD
AS
    EXECUTE DBT PROJECT ANALYTICS_ADMIN.PROJECTS.CALOPTIMA_DW
        ARGS = 'build --target prod --select provider_snapshot provider member eligibility rejected_providers dup_metrics dq_row_counts';


-- =============================================================================
-- STEP 5: Resume — leaf to root for each DAG, then Openflow
-- =============================================================================

-- DAG 2 (DEV)
ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_DEV             RESUME;
ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_DEV    RESUME;

-- DAG 3 (QA)
ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_QA              RESUME;
ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_QA     RESUME;

-- DAG 4 (PROD)
ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_PROD            RESUME;
ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_PROD   RESUME;

-- DAG 1 (Openflow, standalone)
ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK          RESUME;


-- =============================================================================
-- Verify
-- =============================================================================

SHOW TASKS IN SCHEMA FACETS_BRONZE.UTILS;

-- Check recent task history across all DAGs
-- SELECT NAME, STATE, SCHEDULED_FROM, SCHEDULED_TIME, COMPLETED_TIME, RETURN_VALUE
-- FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
--     SCHEDULED_TIME_RANGE_START => DATEADD('hour', -2, CURRENT_TIMESTAMP())
-- ))
-- WHERE NAME LIKE 'PROVIDER_SCD2%' OR NAME LIKE 'DBT_REFRESH%'
-- ORDER BY SCHEDULED_TIME DESC LIMIT 20;
