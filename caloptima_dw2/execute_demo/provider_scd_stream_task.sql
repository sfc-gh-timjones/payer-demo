-- =============================================================================
-- FILE: provider_scd_stream_task.sql
-- PURPOSE: SCD2 for CMC_PRPR_PROV using Snowflake-native Stream + Task + MERGE.
--          Creates FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM.
--          Equivalent to SILVER.PROVIDER_SNAPSHOT but uses non-dbt column naming:
--            EFFECTIVE_FROM / EFFECTIVE_TO / IS_CURRENT  (vs dbt_valid_from / dbt_valid_to)
--
-- Task chain position:
--   DBT_REFRESH_TASK_PROD → PROVIDER_SCD2_STREAM_TASK (this task)
--
-- PAUSE / RESUME CONTROLS:
-- ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK SUSPEND;
-- ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK RESUME;
--
-- Check task history:
-- SELECT * FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
--     SCHEDULED_TIME_RANGE_START => DATEADD('hour', -1, CURRENT_TIMESTAMP()),
--     TASK_NAME => 'PROVIDER_SCD2_STREAM_TASK'
-- )) ORDER BY SCHEDULED_TIME DESC;
--
-- Check stream lag:
-- SELECT SYSTEM$STREAM_HAS_DATA('FACETS_BRONZE.UTILS.PRPR_PROV_CHANGE_STREAM');
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WH_XS;

-- =============================================================================
-- STEP 1: Enable change tracking on Bronze source table
--         Required for stream creation on non-standard tables
-- =============================================================================

ALTER TABLE FACETS_BRONZE.RAW.CMC_PRPR_PROV SET CHANGE_TRACKING = TRUE;


-- =============================================================================
-- STEP 2: Create stream on Bronze CMC_PRPR_PROV
--         APPEND_ONLY = FALSE  → captures INSERT, UPDATE (as DELETE+INSERT pair), DELETE
--         SHOW_INITIAL_ROWS = FALSE → only changes AFTER stream creation
-- =============================================================================

CREATE OR REPLACE STREAM FACETS_BRONZE.UTILS.PRPR_PROV_CHANGE_STREAM
    ON TABLE FACETS_BRONZE.RAW.CMC_PRPR_PROV
    APPEND_ONLY       = FALSE
    SHOW_INITIAL_ROWS = FALSE
    COMMENT           = 'CDC stream on CMC_PRPR_PROV for SCD2 pipeline into SILVER.PROVIDER_SCD2_VIA_STREAM';


-- =============================================================================
-- STEP 3: Create SCD2 target table
-- =============================================================================

CREATE OR REPLACE TABLE FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM (
    PROVIDER_SK         VARCHAR        NOT NULL,    -- MD5(PRPR_ID || EFFECTIVE_FROM)
    PRPR_ID             NUMBER         NOT NULL,    -- business key
    PRPR_NPI            VARCHAR,
    PRPR_NAME           VARCHAR,
    PROVIDER_TYPE       VARCHAR,                    -- decoded: 'Individual (Type 1)' / 'Organization (Type 2)'
    PRPR_ENTITY         VARCHAR,
    STATUS_DESC         VARCHAR,                    -- decoded: 'Active' / 'Inactive' / 'Suspended'
    PRPR_STS            VARCHAR,
    CONTRACT_TYPE       VARCHAR,                    -- decoded: 'Fee for Service' / 'Capitation' / 'Per Diem'
    PRPR_MCTR_TYPE      VARCHAR,
    PRPR_TAXONOMY_CD    VARCHAR,
    TERM_DT             DATE,
    IS_DELETED          BOOLEAN        DEFAULT FALSE,
    EFFECTIVE_FROM      TIMESTAMP_NTZ  NOT NULL,    -- when this version became active
    EFFECTIVE_TO        TIMESTAMP_NTZ,              -- NULL = current (open) record
    IS_CURRENT          BOOLEAN        NOT NULL,
    BRONZE_UPDATED_AT   TIMESTAMP_NTZ,
    SILVER_LOADED_AT    TIMESTAMP_NTZ
);


-- =============================================================================
-- STEP 4: Initial load — seed all current providers as first SCD2 version
--         Run once after table creation. Stream captures deltas going forward.
-- =============================================================================

INSERT INTO FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM
SELECT
    MD5(PRPR_ID::VARCHAR || '|' || _SNOWFLAKE_UPDATED_AT::VARCHAR)  AS PROVIDER_SK,
    PRPR_ID,
    PRPR_NPI,
    PRPR_NAME,
    CASE PRPR_ENTITY
        WHEN 'I' THEN 'Individual (Type 1)'
        WHEN 'O' THEN 'Organization (Type 2)'
        ELSE 'Unknown'
    END                                                              AS PROVIDER_TYPE,
    PRPR_ENTITY,
    CASE PRPR_STS
        WHEN 'AC' THEN 'Active'
        WHEN 'IN' THEN 'Inactive'
        WHEN 'SU' THEN 'Suspended'
        ELSE PRPR_STS
    END                                                              AS STATUS_DESC,
    PRPR_STS,
    CASE PRPR_MCTR_TYPE
        WHEN 'FFS'      THEN 'Fee for Service'
        WHEN 'CAP'      THEN 'Capitation'
        WHEN 'PER_DIEM' THEN 'Per Diem'
        ELSE PRPR_MCTR_TYPE
    END                                                              AS CONTRACT_TYPE,
    PRPR_MCTR_TYPE,
    PRPR_TAXONOMY_CD,
    PRPR_TERM_DT                                                     AS TERM_DT,
    _SNOWFLAKE_DELETED                                               AS IS_DELETED,
    _SNOWFLAKE_UPDATED_AT                                            AS EFFECTIVE_FROM,
    NULL::TIMESTAMP_NTZ                                              AS EFFECTIVE_TO,
    TRUE                                                             AS IS_CURRENT,
    _SNOWFLAKE_UPDATED_AT                                            AS BRONZE_UPDATED_AT,
    CURRENT_TIMESTAMP()                                              AS SILVER_LOADED_AT
FROM FACETS_BRONZE.RAW.CMC_PRPR_PROV;


-- =============================================================================
-- STEP 5: Stored procedure for incremental SCD2 refresh
--
--         KEY PATTERN: Read stream into a temp table first (single read).
--         Snowflake advances the stream offset after each DML statement that
--         references the stream, so multiple DML against the same stream would
--         see empty data on the 2nd statement. Staging to a temp table avoids this.
--
--         Snowflake streams represent UPDATEs as two rows:
--           DELETE row  → before image  (METADATA$ACTION = 'DELETE')
--           INSERT row  → after image   (METADATA$ACTION = 'INSERT')
--         So we:
--           a) Use DELETE rows to identify providers that changed → close current version
--           b) Use INSERT rows to open new version (skip if _SNOWFLAKE_DELETED=TRUE)
-- =============================================================================

CREATE OR REPLACE PROCEDURE FACETS_DEV.SILVER.SP_PROVIDER_SCD2_STREAM_REFRESH()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    rows_closed   INT DEFAULT 0;
    rows_inserted INT DEFAULT 0;
BEGIN
    -- Stage stream data in one read (consuming the stream offset atomically)
    CREATE OR REPLACE TEMPORARY TABLE TMP_PROVIDER_CHANGES AS
    SELECT
        PRPR_ID,
        PRPR_NPI,
        PRPR_NAME,
        PRPR_ENTITY,
        PRPR_STS,
        PRPR_MCTR_TYPE,
        PRPR_TAXONOMY_CD,
        PRPR_TERM_DT,
        _SNOWFLAKE_UPDATED_AT,
        _SNOWFLAKE_DELETED,
        METADATA$ACTION,
        METADATA$ISUPDATE
    FROM FACETS_BRONZE.UTILS.PRPR_PROV_CHANGE_STREAM;

    -- Step A: Close the current (IS_CURRENT=TRUE) row for every changed/deleted provider
    UPDATE FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM t
    SET
        EFFECTIVE_TO     = c._SNOWFLAKE_UPDATED_AT,
        IS_CURRENT       = FALSE
    FROM (
        SELECT DISTINCT PRPR_ID, _SNOWFLAKE_UPDATED_AT
        FROM TMP_PROVIDER_CHANGES
        WHERE METADATA$ACTION = 'DELETE'
    ) c
    WHERE t.PRPR_ID     = c.PRPR_ID
      AND t.IS_CURRENT  = TRUE;

    rows_closed := SQLROWCOUNT;

    -- Step B: Insert new version for each non-deleted provider
    INSERT INTO FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM
    SELECT
        MD5(PRPR_ID::VARCHAR || '|' || _SNOWFLAKE_UPDATED_AT::VARCHAR) AS PROVIDER_SK,
        PRPR_ID,
        PRPR_NPI,
        PRPR_NAME,
        CASE PRPR_ENTITY
            WHEN 'I' THEN 'Individual (Type 1)'
            WHEN 'O' THEN 'Organization (Type 2)'
            ELSE 'Unknown'
        END                                                              AS PROVIDER_TYPE,
        PRPR_ENTITY,
        CASE PRPR_STS
            WHEN 'AC' THEN 'Active'
            WHEN 'IN' THEN 'Inactive'
            WHEN 'SU' THEN 'Suspended'
            ELSE PRPR_STS
        END                                                              AS STATUS_DESC,
        PRPR_STS,
        CASE PRPR_MCTR_TYPE
            WHEN 'FFS'      THEN 'Fee for Service'
            WHEN 'CAP'      THEN 'Capitation'
            WHEN 'PER_DIEM' THEN 'Per Diem'
            ELSE PRPR_MCTR_TYPE
        END                                                              AS CONTRACT_TYPE,
        PRPR_MCTR_TYPE,
        PRPR_TAXONOMY_CD,
        PRPR_TERM_DT                                                     AS TERM_DT,
        _SNOWFLAKE_DELETED                                               AS IS_DELETED,
        _SNOWFLAKE_UPDATED_AT                                            AS EFFECTIVE_FROM,
        NULL::TIMESTAMP_NTZ                                              AS EFFECTIVE_TO,
        TRUE                                                             AS IS_CURRENT,
        _SNOWFLAKE_UPDATED_AT                                            AS BRONZE_UPDATED_AT,
        CURRENT_TIMESTAMP()                                              AS SILVER_LOADED_AT
    FROM TMP_PROVIDER_CHANGES
    WHERE METADATA$ACTION    = 'INSERT'
      AND _SNOWFLAKE_DELETED = FALSE;

    rows_inserted := SQLROWCOUNT;

    DROP TABLE IF EXISTS TMP_PROVIDER_CHANGES;

    RETURN 'Closed: ' || rows_closed || ' | Inserted: ' || rows_inserted;
END;
$$;


-- =============================================================================
-- STEP 6: Create task
--         Fires every 5 minutes ONLY when the stream has new data (no idle compute)
-- =============================================================================

CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK
    WAREHOUSE = WH_XS
    AFTER     FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_PROD
    WHEN      SYSTEM$STREAM_HAS_DATA('FACETS_BRONZE.UTILS.PRPR_PROV_CHANGE_STREAM')
    COMMENT   = 'SCD2 refresh for SILVER.PROVIDER_SCD2_VIA_STREAM when Bronze CMC_PRPR_PROV changes'
AS
    CALL FACETS_DEV.SILVER.SP_PROVIDER_SCD2_STREAM_REFRESH();

ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK RESUME;


-- =============================================================================
-- STEP 7: Verification
-- =============================================================================

-- Row count + current record count
SELECT
    COUNT(*)                                            AS total_rows,
    SUM(CASE WHEN IS_CURRENT THEN 1 ELSE 0 END)         AS current_rows,
    COUNT(DISTINCT PRPR_ID)                             AS distinct_providers
FROM FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM;

-- Cross-check all three SCD2 implementations
-- Note: PROVIDER_SNAPSHOT won't exist until dbt build runs with snapshot support;
--       replace with SILVER.PROVIDER (legacy) until then.
SELECT 'dbt snapshot (PROVIDER_SNAPSHOT)' AS approach, COUNT(*) AS current_providers FROM FACETS_DEV.SILVER.PROVIDER_SNAPSHOT      WHERE dbt_valid_to IS NULL
UNION ALL
SELECT 'Stream/Task/MERGE'                AS approach, COUNT(*) AS current_providers FROM FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM WHERE IS_CURRENT = TRUE
UNION ALL
SELECT 'Legacy incremental dbt'           AS approach, COUNT(*) AS current_providers FROM FACETS_DEV.SILVER.PROVIDER              WHERE IS_CURRENT = TRUE
ORDER BY approach;
