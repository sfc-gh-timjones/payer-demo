-- Silver refresh task: chains dbt Silver models to run after each CDC batch.
-- Requires a deployed dbt project object (snow dbt deploy) named CALOPTIMA_DW_PROD.
-- Run this SQL in Snowsight as ACCOUNTADMIN after deploying the dbt project.

CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.SILVER_REFRESH_PROD
    WAREHOUSE = WH_XS
    AFTER    FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK
    COMMENT  = 'Runs dbt Silver + DQ ops models after each Facets CDC batch in FACETS_BRONZE.RAW'
AS
    EXECUTE DBT PROJECT ANALYTICS_ADMIN.PROJECTS.CALOPTIMA_DW
        ARGS = 'build --select provider_snapshot,provider,member,eligibility,rejected_providers,dup_metrics,dq_row_counts';

-- Gold models are views — they rebuild on query, no task execution needed.
-- To include gold scaffolds explicitly: add gold_member_enrollment,gold_provider_directory,gold_eligibility_snapshot

-- Resume after creation:
-- ALTER TASK FACETS_BRONZE.UTILS.SILVER_REFRESH_PROD RESUME;

-- Check status:
-- SELECT * FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
-- WHERE NAME = 'SILVER_REFRESH_PROD' ORDER BY SCHEDULED_TIME DESC LIMIT 10;
