-- FACETS_SILVER_REFRESH: chains dbt Silver models after each Openflow CDC batch.
-- Target: dev (writes to FACETS_DEV.SILVER — demo database).
-- Requires: snow dbt deploy CALOPTIMA_DW run beforehand.
-- Run this SQL in Snowsight as ACCOUNTADMIN.
--
-- Task chain:
--   FACETS_INCREMENTAL_TASK          (Openflow CDC loads Bronze)
--       → FACETS_SILVER_REFRESH      (dbt builds Silver / DQ models)
--           → PROVIDER_SCD2_STREAM_TASK  (Stream/Task SCD2 for providers, if stream has data)

CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.FACETS_SILVER_REFRESH
    WAREHOUSE = WH_XS
    AFTER     FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK
    COMMENT   = 'Runs dbt Silver + DQ models against FACETS_DEV after each CDC batch'
AS
    EXECUTE DBT PROJECT ANALYTICS_ADMIN.PROJECTS.CALOPTIMA_DW
        ARGS = 'build --target dev --select provider_snapshot,provider,member,eligibility,rejected_providers,dup_metrics,dq_row_counts';

-- Gold models are views — they rebuild on query, no task execution needed.

-- Resume after creation (parent task FACETS_INCREMENTAL_TASK must also be resumed):
-- ALTER TASK FACETS_BRONZE.UTILS.FACETS_SILVER_REFRESH RESUME;

-- Check status:
-- SELECT * FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
--     SCHEDULED_TIME_RANGE_START => DATEADD('hour', -1, CURRENT_TIMESTAMP()),
--     TASK_NAME => 'FACETS_SILVER_REFRESH'
-- )) ORDER BY SCHEDULED_TIME DESC;
