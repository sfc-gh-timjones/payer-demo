-- Silver refresh task: chains dbt Silver models to run after each CDC batch.
-- Requires a deployed dbt project object (snow dbt deploy) named CALOPTIMA_DW_PROD.
-- Run this SQL in Snowsight as ACCOUNTADMIN after deploying the dbt project.

CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.SILVER_REFRESH_PROD
    WAREHOUSE = WH_XS
    AFTER    FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK
    COMMENT  = 'Runs dbt Silver models after each Facets CDC batch in FACETS_BRONZE.RAW'
AS
    EXECUTE DBT PROJECT CALOPTIMA_DW_PROD
        USING (
            VARS     => '{"target_database":"FACETS_PROD","silver_schema":"SILVER"}',
            SELECT   => 'silver_provider,silver_member,silver_eligibility,dup_metrics,dq_row_counts'
        );

-- Resume after creation:
-- ALTER TASK FACETS_BRONZE.UTILS.SILVER_REFRESH_PROD RESUME;

-- Check status:
-- SELECT * FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
-- WHERE NAME = 'SILVER_REFRESH_PROD' ORDER BY SCHEDULED_TIME DESC LIMIT 10;
