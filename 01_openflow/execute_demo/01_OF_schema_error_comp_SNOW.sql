-- =============================================================================
-- FILE: 02_OF_schema_change_SNOW.sql
-- PURPOSE: Run before and after the schema change in 01_OF_schema_change_mssql.sql
--          to show Snowflake automatically picked up:
--            1. New PRTP_EFFECTIVE_DT column (schema drift / column add)
--            2. Updated description on PRTP_ID 7 (UPDATE captured via CDC)
--            3. Soft-deleted PRTP_ID 2 (DELETE captured via CDC)
--
-- RUN ONCE before making the SQL Server changes, then run again after Openflow
-- ingests to see all three change types reflected in Bronze.
-- =============================================================================

-- =============================================================================
-- SECTION A: Schema inspection
-- PRTP_EFFECTIVE_DT absent before, present after schema change
-- =============================================================================

SELECT *
FROM FACETS_BRONZE.RAW.CMC_PRTP_PROV_TYPE
WHERE _SNOWFLAKE_DELETED = FALSE;


DESCRIBE TABLE FACETS_BRONZE.RAW.CMC_PRTP_PROV_TYPE;

































-- =============================================================================
-- IMPLEMENT SCHEMA CHANGE 
-- =============================================================================

SELECT
    PRTP_ID,
    PRTP_CODE,
    PRTP_DESC,
    PRTP_CATEGORY,
    PRTP_ACTIVE_FLAG,
    _SNOWFLAKE_UPDATED_AT,
    _SNOWFLAKE_DELETED
FROM FACETS_BRONZE.RAW.CMC_PRTP_PROV_TYPE
WHERE 
    _SNOWFLAKE_DELETED = FALSE 
    AND PRTP_ID = 7;

-- =============================================================================
-- SECTION C: Spotlight — Deleted row (PRTP_ID 2)
-- _SNOWFLAKE_DELETED = TRUE shows Openflow captured the DELETE via CDC
-- =============================================================================

SELECT
    PRTP_ID,
    PRTP_CODE,
    PRTP_DESC,
    _SNOWFLAKE_INSERTED_AT,
    _SNOWFLAKE_UPDATED_AT,
    _SNOWFLAKE_DELETED
FROM FACETS_BRONZE.RAW.CMC_PRTP_PROV_TYPE
WHERE 
    _SNOWFLAKE_DELETED = FALSE 
    AND PRTP_ID = 2;

-- =============================================================================
-- SECTION D: Full table — all rows including new schema column
-- 19 active rows + 1 soft-deleted + 5 new inserts with PRTP_EFFECTIVE_DT
-- =============================================================================

SELECT *
FROM FACETS_BRONZE.RAW.CMC_PRTP_PROV_TYPE
WHERE _SNOWFLAKE_DELETED = FALSE 
ORDER BY PRTP_ID;
