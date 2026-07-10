-- =============================================================================
-- FILE: 06.2_schema_change_snow.sql
-- PURPOSE: Run before and after the schema change in 06_schema_change_mssql.sql
--          to show Snowflake automatically picked up the new PRTP_EFFECTIVE_DT
--          column via Openflow schema evolution.
--
-- RUN ONCE before making the SQL Server change, then run again after Openflow
-- ingests the new records to see the column appear automatically.
-- =============================================================================

-- Show all columns on the Bronze table (PRTP_EFFECTIVE_DT absent before, present after)
DESCRIBE TABLE FACETS_BRONZE.RAW.CMC_PRTP_PROV_TYPE;

-- Show all rows (15 rows pre-change; 20 rows with PRTP_EFFECTIVE_DT post-change)
-- PRTP_EFFECTIVE_DT placed before _SNOWFLAKE metadata columns for readability
SELECT
    PRTP_ID,
    PRTP_CODE,
    PRTP_DESC,
    PRTP_CATEGORY,
    PRTP_ACTIVE_FLAG,
    PRTP_SORT_ORDER,
    ETL_PROCESS_EXECUTION_ID,
    ROW_HASH_VALUE,
    PRTP_EFFECTIVE_DT,
    _SNOWFLAKE_INSERTED_AT,
    _SNOWFLAKE_UPDATED_AT,
    _SNOWFLAKE_DELETED
FROM FACETS_BRONZE.RAW.CMC_PRTP_PROV_TYPE
ORDER BY PRTP_ID;
