-- =============================================================================
-- FILE:    rebuild_provider_scd2_pipeline.sql
-- PURPOSE: Creates a stored procedure that rebuilds the full Stream+Task SCD2
--          pipeline for PROVIDER_SCD2_VIA_STREAM across DEV / QA / PROD from
--          scratch. Use this after a full reset, when re-deploying to a new
--          account, or when the stream/task objects need to be recreated.
--
-- WHAT IT REBUILDS PER ENVIRONMENT:
--   1. PRPR_PROV_CHANGE_STREAM        (stream on Bronze CMC_PRPR_PROV, fresh offset)
--   2. SILVER.PROVIDER_SCD2_VIA_STREAM (table, dropped + recreated)
--   3. Initial load INSERT             (seeds table from Bronze current state)
--   4. SILVER.SP_PROVIDER_SCD2_STREAM_REFRESH (stored procedure)
--   5. PROVIDER_SCD2_STREAM_TASK_DEV   (task, triggered when Bronze changes)
--
-- WHAT IT DOES NOT REBUILD:
--   - dbt project objects (CALOPTIMA_DW / CALOPTIMA_DW_DEV)
--   - dbt snapshot tables (PROVIDER_SNAPSHOT) — see reset_scd2_tables.md
--   - DBT_REFRESH_TASK_* chain (managed by CI / silver_refresh_tasks.sql)
--   - FACETS_INCREMENTAL_TASK (managed by Openflow setup)
--
-- TASK CHAIN AFTER REBUILD:
--   FACETS_INCREMENTAL_TASK
--     └─ DBT_REFRESH_TASK_DEV
--          └─ DBT_REFRESH_TASK_QA
--               └─ DBT_REFRESH_TASK_PROD
--   PROVIDER_SCD2_STREAM_TASK_DEV  (triggered → FACETS_DEV)
--                         └─ PROVIDER_SCD2_STREAM_TASK_QA   (QA  → FACETS_QA)
--                              └─ PROVIDER_SCD2_STREAM_TASK_PROD (PROD → FACETS_PROD)
-- =============================================================================

USE ROLE      ACCOUNTADMIN;
USE WAREHOUSE WH_XS;
USE DATABASE  FACETS_BRONZE;
USE SCHEMA    UTILS;


-- =============================================================================
-- STEP 1: Create the procedure
-- =============================================================================

CREATE OR REPLACE PROCEDURE FACETS_BRONZE.UTILS.SP_REBUILD_PROVIDER_SCD2_PIPELINE(
    P_REBUILD_DEV   BOOLEAN DEFAULT TRUE,
    P_REBUILD_QA    BOOLEAN DEFAULT TRUE,
    P_REBUILD_PROD  BOOLEAN DEFAULT TRUE,
    P_DRY_RUN       BOOLEAN DEFAULT FALSE
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    log_out      VARCHAR DEFAULT '';
    dev_count    INT     DEFAULT 0;
    qa_count     INT     DEFAULT 0;
    prod_count   INT     DEFAULT 0;
BEGIN

    log_out := '=== SP_REBUILD_PROVIDER_SCD2_PIPELINE ===\n'
            || 'DRY_RUN='    || :P_DRY_RUN::VARCHAR
            || '  DEV='      || :P_REBUILD_DEV::VARCHAR
            || '  QA='       || :P_REBUILD_QA::VARCHAR
            || '  PROD='     || :P_REBUILD_PROD::VARCHAR || '\n\n';

    -- =========================================================================
    -- STEP A: Suspend the full task chain (root → leaf)
    -- =========================================================================
    IF (NOT :P_DRY_RUN) THEN
        ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK          SUSPEND;
        ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_DEV             SUSPEND;
        ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_QA              SUSPEND;
        ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_PROD            SUSPEND;
        ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_DEV     SUSPEND;
        ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_QA     SUSPEND;
        ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_PROD   SUSPEND;
    END IF;
    log_out := log_out || '[A] Task chain suspended\n';

    -- =========================================================================
    -- STEP B: Rebuild DEV
    -- =========================================================================
    IF (:P_REBUILD_DEV) THEN
        log_out := log_out || '\n--- DEV ---\n';

        IF (NOT :P_DRY_RUN) THEN

            -- Stream (resets CDC offset to NOW)
            EXECUTE IMMEDIATE '
                CREATE OR REPLACE STREAM FACETS_BRONZE.UTILS.PRPR_PROV_CHANGE_STREAM
                    ON TABLE FACETS_BRONZE.RAW.CMC_PRPR_PROV
                    APPEND_ONLY = FALSE SHOW_INITIAL_ROWS = FALSE
                    COMMENT = ''CDC stream on CMC_PRPR_PROV for FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM''
            ';

            -- Target table
            EXECUTE IMMEDIATE '
                CREATE OR REPLACE TABLE FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM (
                    PROVIDER_SK      VARCHAR       NOT NULL,
                    PRPR_ID          NUMBER        NOT NULL,
                    PRPR_NPI         VARCHAR,
                    PRPR_NAME        VARCHAR,
                    PROVIDER_TYPE    VARCHAR,
                    PRPR_ENTITY      VARCHAR,
                    STATUS_DESC      VARCHAR,
                    PRPR_STS         VARCHAR,
                    CONTRACT_TYPE    VARCHAR,
                    PRPR_MCTR_TYPE   VARCHAR,
                    PRPR_TAXONOMY_CD VARCHAR,
                    TERM_DT          DATE,
                    IS_DELETED       BOOLEAN       DEFAULT FALSE,
                    EFFECTIVE_FROM   TIMESTAMP_NTZ NOT NULL,
                    EFFECTIVE_TO     TIMESTAMP_NTZ,
                    IS_CURRENT       BOOLEAN       NOT NULL,
                    BRONZE_UPDATED_AT  TIMESTAMP_NTZ,
                    SILVER_LOADED_AT   TIMESTAMP_NTZ
                )
            ';

            -- Initial load from Bronze current state
            EXECUTE IMMEDIATE '
                INSERT INTO FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM
                SELECT
                    MD5(PRPR_ID::VARCHAR || ''|'' || _SNOWFLAKE_UPDATED_AT::VARCHAR),
                    PRPR_ID, PRPR_NPI, PRPR_NAME,
                    CASE PRPR_ENTITY WHEN ''I'' THEN ''Individual (Type 1)'' WHEN ''O'' THEN ''Organization (Type 2)'' ELSE ''Unknown'' END,
                    PRPR_ENTITY,
                    CASE PRPR_STS WHEN ''AC'' THEN ''Active'' WHEN ''IN'' THEN ''Inactive'' WHEN ''SU'' THEN ''Suspended'' ELSE PRPR_STS END,
                    PRPR_STS,
                    CASE PRPR_MCTR_TYPE WHEN ''FFS'' THEN ''Fee for Service'' WHEN ''CAP'' THEN ''Capitation'' WHEN ''PER_DIEM'' THEN ''Per Diem'' ELSE PRPR_MCTR_TYPE END,
                    PRPR_MCTR_TYPE, PRPR_TAXONOMY_CD, PRPR_TERM_DT,
                    _SNOWFLAKE_DELETED, _SNOWFLAKE_UPDATED_AT, NULL::TIMESTAMP_NTZ, TRUE,
                    _SNOWFLAKE_UPDATED_AT, CURRENT_TIMESTAMP()
                FROM FACETS_BRONZE.RAW.CMC_PRPR_PROV
            ';

            SELECT COUNT(*) INTO :dev_count FROM FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM;

            -- Inner stored procedure
            EXECUTE IMMEDIATE '
                CREATE OR REPLACE PROCEDURE FACETS_DEV.SILVER.SP_PROVIDER_SCD2_STREAM_REFRESH()
                RETURNS VARCHAR LANGUAGE SQL AS
                $$
                DECLARE
                    rows_closed   INT DEFAULT 0;
                    rows_inserted INT DEFAULT 0;
                BEGIN
                    CREATE OR REPLACE TEMPORARY TABLE TMP_PROVIDER_CHANGES AS
                    SELECT PRPR_ID, PRPR_NPI, PRPR_NAME, PRPR_ENTITY, PRPR_STS,
                           PRPR_MCTR_TYPE, PRPR_TAXONOMY_CD, PRPR_TERM_DT,
                           _SNOWFLAKE_UPDATED_AT, _SNOWFLAKE_DELETED,
                           METADATA$ACTION, METADATA$ISUPDATE
                    FROM FACETS_BRONZE.UTILS.PRPR_PROV_CHANGE_STREAM;

                    UPDATE FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM t
                    SET EFFECTIVE_TO = c._SNOWFLAKE_UPDATED_AT, IS_CURRENT = FALSE
                    FROM (SELECT DISTINCT PRPR_ID, _SNOWFLAKE_UPDATED_AT
                          FROM TMP_PROVIDER_CHANGES WHERE METADATA$ACTION = ''INSERT'') c
                    WHERE t.PRPR_ID = c.PRPR_ID AND t.IS_CURRENT = TRUE;
                    rows_closed := SQLROWCOUNT;

                    INSERT INTO FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM
                    SELECT
                        MD5(PRPR_ID::VARCHAR || ''|'' || _SNOWFLAKE_UPDATED_AT::VARCHAR),
                        PRPR_ID, PRPR_NPI, PRPR_NAME,
                        CASE PRPR_ENTITY WHEN ''I'' THEN ''Individual (Type 1)'' WHEN ''O'' THEN ''Organization (Type 2)'' ELSE ''Unknown'' END,
                        PRPR_ENTITY,
                        CASE PRPR_STS WHEN ''AC'' THEN ''Active'' WHEN ''IN'' THEN ''Inactive'' WHEN ''SU'' THEN ''Suspended'' ELSE PRPR_STS END,
                        PRPR_STS,
                        CASE PRPR_MCTR_TYPE WHEN ''FFS'' THEN ''Fee for Service'' WHEN ''CAP'' THEN ''Capitation'' WHEN ''PER_DIEM'' THEN ''Per Diem'' ELSE PRPR_MCTR_TYPE END,
                        PRPR_MCTR_TYPE, PRPR_TAXONOMY_CD, PRPR_TERM_DT,
                        _SNOWFLAKE_DELETED, _SNOWFLAKE_UPDATED_AT, NULL::TIMESTAMP_NTZ, TRUE,
                        _SNOWFLAKE_UPDATED_AT, CURRENT_TIMESTAMP()
                    FROM TMP_PROVIDER_CHANGES
                    WHERE METADATA$ACTION = ''INSERT'' AND _SNOWFLAKE_DELETED = FALSE;
                    rows_inserted := SQLROWCOUNT;

                    DROP TABLE IF EXISTS TMP_PROVIDER_CHANGES;
                    RETURN ''Closed: '' || rows_closed || '' | Inserted: '' || rows_inserted;
                END;
                $$
            ';

            -- Task (fires after DBT_REFRESH_TASK_PROD)
            EXECUTE IMMEDIATE '
                CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_DEV
                    WAREHOUSE = WH_XS
                    COMMENT   = ''SCD2 refresh for FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM''
                    WHEN      SYSTEM$STREAM_HAS_DATA(''FACETS_BRONZE.UTILS.PRPR_PROV_CHANGE_STREAM'')
                AS
                    CALL FACETS_DEV.SILVER.SP_PROVIDER_SCD2_STREAM_REFRESH()
            ';

        END IF;
        log_out := log_out || '[DEV] Done. Rows loaded: ' || :dev_count::VARCHAR || '\n';
    END IF;

    -- =========================================================================
    -- STEP C: Rebuild QA
    -- =========================================================================
    IF (:P_REBUILD_QA) THEN
        log_out := log_out || '\n--- QA ---\n';

        IF (NOT :P_DRY_RUN) THEN

            EXECUTE IMMEDIATE '
                CREATE OR REPLACE STREAM FACETS_BRONZE.UTILS.PRPR_PROV_CHANGE_STREAM_QA
                    ON TABLE FACETS_BRONZE.RAW.CMC_PRPR_PROV
                    APPEND_ONLY = FALSE SHOW_INITIAL_ROWS = FALSE
                    COMMENT = ''CDC stream on CMC_PRPR_PROV for FACETS_QA.SILVER.PROVIDER_SCD2_VIA_STREAM''
            ';

            EXECUTE IMMEDIATE '
                CREATE OR REPLACE TABLE FACETS_QA.SILVER.PROVIDER_SCD2_VIA_STREAM (
                    PROVIDER_SK      VARCHAR       NOT NULL,
                    PRPR_ID          NUMBER        NOT NULL,
                    PRPR_NPI         VARCHAR,
                    PRPR_NAME        VARCHAR,
                    PROVIDER_TYPE    VARCHAR,
                    PRPR_ENTITY      VARCHAR,
                    STATUS_DESC      VARCHAR,
                    PRPR_STS         VARCHAR,
                    CONTRACT_TYPE    VARCHAR,
                    PRPR_MCTR_TYPE   VARCHAR,
                    PRPR_TAXONOMY_CD VARCHAR,
                    TERM_DT          DATE,
                    IS_DELETED       BOOLEAN       DEFAULT FALSE,
                    EFFECTIVE_FROM   TIMESTAMP_NTZ NOT NULL,
                    EFFECTIVE_TO     TIMESTAMP_NTZ,
                    IS_CURRENT       BOOLEAN       NOT NULL,
                    BRONZE_UPDATED_AT  TIMESTAMP_NTZ,
                    SILVER_LOADED_AT   TIMESTAMP_NTZ
                )
            ';

            EXECUTE IMMEDIATE '
                INSERT INTO FACETS_QA.SILVER.PROVIDER_SCD2_VIA_STREAM
                SELECT
                    MD5(PRPR_ID::VARCHAR || ''|'' || _SNOWFLAKE_UPDATED_AT::VARCHAR),
                    PRPR_ID, PRPR_NPI, PRPR_NAME,
                    CASE PRPR_ENTITY WHEN ''I'' THEN ''Individual (Type 1)'' WHEN ''O'' THEN ''Organization (Type 2)'' ELSE ''Unknown'' END,
                    PRPR_ENTITY,
                    CASE PRPR_STS WHEN ''AC'' THEN ''Active'' WHEN ''IN'' THEN ''Inactive'' WHEN ''SU'' THEN ''Suspended'' ELSE PRPR_STS END,
                    PRPR_STS,
                    CASE PRPR_MCTR_TYPE WHEN ''FFS'' THEN ''Fee for Service'' WHEN ''CAP'' THEN ''Capitation'' WHEN ''PER_DIEM'' THEN ''Per Diem'' ELSE PRPR_MCTR_TYPE END,
                    PRPR_MCTR_TYPE, PRPR_TAXONOMY_CD, PRPR_TERM_DT,
                    _SNOWFLAKE_DELETED, _SNOWFLAKE_UPDATED_AT, NULL::TIMESTAMP_NTZ, TRUE,
                    _SNOWFLAKE_UPDATED_AT, CURRENT_TIMESTAMP()
                FROM FACETS_BRONZE.RAW.CMC_PRPR_PROV
            ';

            SELECT COUNT(*) INTO :qa_count FROM FACETS_QA.SILVER.PROVIDER_SCD2_VIA_STREAM;

            EXECUTE IMMEDIATE '
                CREATE OR REPLACE PROCEDURE FACETS_QA.SILVER.SP_PROVIDER_SCD2_STREAM_REFRESH()
                RETURNS VARCHAR LANGUAGE SQL AS
                $$
                DECLARE
                    rows_closed   INT DEFAULT 0;
                    rows_inserted INT DEFAULT 0;
                BEGIN
                    CREATE OR REPLACE TEMPORARY TABLE TMP_PROVIDER_CHANGES AS
                    SELECT PRPR_ID, PRPR_NPI, PRPR_NAME, PRPR_ENTITY, PRPR_STS,
                           PRPR_MCTR_TYPE, PRPR_TAXONOMY_CD, PRPR_TERM_DT,
                           _SNOWFLAKE_UPDATED_AT, _SNOWFLAKE_DELETED,
                           METADATA$ACTION, METADATA$ISUPDATE
                    FROM FACETS_BRONZE.UTILS.PRPR_PROV_CHANGE_STREAM_QA;

                    UPDATE FACETS_QA.SILVER.PROVIDER_SCD2_VIA_STREAM t
                    SET EFFECTIVE_TO = c._SNOWFLAKE_UPDATED_AT, IS_CURRENT = FALSE
                    FROM (SELECT DISTINCT PRPR_ID, _SNOWFLAKE_UPDATED_AT
                          FROM TMP_PROVIDER_CHANGES WHERE METADATA$ACTION = ''INSERT'') c
                    WHERE t.PRPR_ID = c.PRPR_ID AND t.IS_CURRENT = TRUE;
                    rows_closed := SQLROWCOUNT;

                    INSERT INTO FACETS_QA.SILVER.PROVIDER_SCD2_VIA_STREAM
                    SELECT
                        MD5(PRPR_ID::VARCHAR || ''|'' || _SNOWFLAKE_UPDATED_AT::VARCHAR),
                        PRPR_ID, PRPR_NPI, PRPR_NAME,
                        CASE PRPR_ENTITY WHEN ''I'' THEN ''Individual (Type 1)'' WHEN ''O'' THEN ''Organization (Type 2)'' ELSE ''Unknown'' END,
                        PRPR_ENTITY,
                        CASE PRPR_STS WHEN ''AC'' THEN ''Active'' WHEN ''IN'' THEN ''Inactive'' WHEN ''SU'' THEN ''Suspended'' ELSE PRPR_STS END,
                        PRPR_STS,
                        CASE PRPR_MCTR_TYPE WHEN ''FFS'' THEN ''Fee for Service'' WHEN ''CAP'' THEN ''Capitation'' WHEN ''PER_DIEM'' THEN ''Per Diem'' ELSE PRPR_MCTR_TYPE END,
                        PRPR_MCTR_TYPE, PRPR_TAXONOMY_CD, PRPR_TERM_DT,
                        _SNOWFLAKE_DELETED, _SNOWFLAKE_UPDATED_AT, NULL::TIMESTAMP_NTZ, TRUE,
                        _SNOWFLAKE_UPDATED_AT, CURRENT_TIMESTAMP()
                    FROM TMP_PROVIDER_CHANGES
                    WHERE METADATA$ACTION = ''INSERT'' AND _SNOWFLAKE_DELETED = FALSE;
                    rows_inserted := SQLROWCOUNT;

                    DROP TABLE IF EXISTS TMP_PROVIDER_CHANGES;
                    RETURN ''Closed: '' || rows_closed || '' | Inserted: '' || rows_inserted;
                END;
                $$
            ';

            EXECUTE IMMEDIATE '
                CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_QA
                    WAREHOUSE = WH_XS
                    COMMENT   = ''SCD2 refresh for FACETS_QA.SILVER.PROVIDER_SCD2_VIA_STREAM''
                    WHEN      SYSTEM$STREAM_HAS_DATA(''FACETS_BRONZE.UTILS.PRPR_PROV_CHANGE_STREAM_QA'')
                AS
                    CALL FACETS_QA.SILVER.SP_PROVIDER_SCD2_STREAM_REFRESH()
            ';

        END IF;
        log_out := log_out || '[QA] Done. Rows loaded: ' || :qa_count::VARCHAR || '\n';
    END IF;

    -- =========================================================================
    -- STEP D: Rebuild PROD
    -- =========================================================================
    IF (:P_REBUILD_PROD) THEN
        log_out := log_out || '\n--- PROD ---\n';

        IF (NOT :P_DRY_RUN) THEN

            EXECUTE IMMEDIATE '
                CREATE OR REPLACE STREAM FACETS_BRONZE.UTILS.PRPR_PROV_CHANGE_STREAM_PROD
                    ON TABLE FACETS_BRONZE.RAW.CMC_PRPR_PROV
                    APPEND_ONLY = FALSE SHOW_INITIAL_ROWS = FALSE
                    COMMENT = ''CDC stream on CMC_PRPR_PROV for FACETS_PROD.SILVER.PROVIDER_SCD2_VIA_STREAM''
            ';

            EXECUTE IMMEDIATE '
                CREATE OR REPLACE TABLE FACETS_PROD.SILVER.PROVIDER_SCD2_VIA_STREAM (
                    PROVIDER_SK      VARCHAR       NOT NULL,
                    PRPR_ID          NUMBER        NOT NULL,
                    PRPR_NPI         VARCHAR,
                    PRPR_NAME        VARCHAR,
                    PROVIDER_TYPE    VARCHAR,
                    PRPR_ENTITY      VARCHAR,
                    STATUS_DESC      VARCHAR,
                    PRPR_STS         VARCHAR,
                    CONTRACT_TYPE    VARCHAR,
                    PRPR_MCTR_TYPE   VARCHAR,
                    PRPR_TAXONOMY_CD VARCHAR,
                    TERM_DT          DATE,
                    IS_DELETED       BOOLEAN       DEFAULT FALSE,
                    EFFECTIVE_FROM   TIMESTAMP_NTZ NOT NULL,
                    EFFECTIVE_TO     TIMESTAMP_NTZ,
                    IS_CURRENT       BOOLEAN       NOT NULL,
                    BRONZE_UPDATED_AT  TIMESTAMP_NTZ,
                    SILVER_LOADED_AT   TIMESTAMP_NTZ
                )
            ';

            EXECUTE IMMEDIATE '
                INSERT INTO FACETS_PROD.SILVER.PROVIDER_SCD2_VIA_STREAM
                SELECT
                    MD5(PRPR_ID::VARCHAR || ''|'' || _SNOWFLAKE_UPDATED_AT::VARCHAR),
                    PRPR_ID, PRPR_NPI, PRPR_NAME,
                    CASE PRPR_ENTITY WHEN ''I'' THEN ''Individual (Type 1)'' WHEN ''O'' THEN ''Organization (Type 2)'' ELSE ''Unknown'' END,
                    PRPR_ENTITY,
                    CASE PRPR_STS WHEN ''AC'' THEN ''Active'' WHEN ''IN'' THEN ''Inactive'' WHEN ''SU'' THEN ''Suspended'' ELSE PRPR_STS END,
                    PRPR_STS,
                    CASE PRPR_MCTR_TYPE WHEN ''FFS'' THEN ''Fee for Service'' WHEN ''CAP'' THEN ''Capitation'' WHEN ''PER_DIEM'' THEN ''Per Diem'' ELSE PRPR_MCTR_TYPE END,
                    PRPR_MCTR_TYPE, PRPR_TAXONOMY_CD, PRPR_TERM_DT,
                    _SNOWFLAKE_DELETED, _SNOWFLAKE_UPDATED_AT, NULL::TIMESTAMP_NTZ, TRUE,
                    _SNOWFLAKE_UPDATED_AT, CURRENT_TIMESTAMP()
                FROM FACETS_BRONZE.RAW.CMC_PRPR_PROV
            ';

            SELECT COUNT(*) INTO :prod_count FROM FACETS_PROD.SILVER.PROVIDER_SCD2_VIA_STREAM;

            EXECUTE IMMEDIATE '
                CREATE OR REPLACE PROCEDURE FACETS_PROD.SILVER.SP_PROVIDER_SCD2_STREAM_REFRESH()
                RETURNS VARCHAR LANGUAGE SQL AS
                $$
                DECLARE
                    rows_closed   INT DEFAULT 0;
                    rows_inserted INT DEFAULT 0;
                BEGIN
                    CREATE OR REPLACE TEMPORARY TABLE TMP_PROVIDER_CHANGES AS
                    SELECT PRPR_ID, PRPR_NPI, PRPR_NAME, PRPR_ENTITY, PRPR_STS,
                           PRPR_MCTR_TYPE, PRPR_TAXONOMY_CD, PRPR_TERM_DT,
                           _SNOWFLAKE_UPDATED_AT, _SNOWFLAKE_DELETED,
                           METADATA$ACTION, METADATA$ISUPDATE
                    FROM FACETS_BRONZE.UTILS.PRPR_PROV_CHANGE_STREAM_PROD;

                    UPDATE FACETS_PROD.SILVER.PROVIDER_SCD2_VIA_STREAM t
                    SET EFFECTIVE_TO = c._SNOWFLAKE_UPDATED_AT, IS_CURRENT = FALSE
                    FROM (SELECT DISTINCT PRPR_ID, _SNOWFLAKE_UPDATED_AT
                          FROM TMP_PROVIDER_CHANGES WHERE METADATA$ACTION = ''INSERT'') c
                    WHERE t.PRPR_ID = c.PRPR_ID AND t.IS_CURRENT = TRUE;
                    rows_closed := SQLROWCOUNT;

                    INSERT INTO FACETS_PROD.SILVER.PROVIDER_SCD2_VIA_STREAM
                    SELECT
                        MD5(PRPR_ID::VARCHAR || ''|'' || _SNOWFLAKE_UPDATED_AT::VARCHAR),
                        PRPR_ID, PRPR_NPI, PRPR_NAME,
                        CASE PRPR_ENTITY WHEN ''I'' THEN ''Individual (Type 1)'' WHEN ''O'' THEN ''Organization (Type 2)'' ELSE ''Unknown'' END,
                        PRPR_ENTITY,
                        CASE PRPR_STS WHEN ''AC'' THEN ''Active'' WHEN ''IN'' THEN ''Inactive'' WHEN ''SU'' THEN ''Suspended'' ELSE PRPR_STS END,
                        PRPR_STS,
                        CASE PRPR_MCTR_TYPE WHEN ''FFS'' THEN ''Fee for Service'' WHEN ''CAP'' THEN ''Capitation'' WHEN ''PER_DIEM'' THEN ''Per Diem'' ELSE PRPR_MCTR_TYPE END,
                        PRPR_MCTR_TYPE, PRPR_TAXONOMY_CD, PRPR_TERM_DT,
                        _SNOWFLAKE_DELETED, _SNOWFLAKE_UPDATED_AT, NULL::TIMESTAMP_NTZ, TRUE,
                        _SNOWFLAKE_UPDATED_AT, CURRENT_TIMESTAMP()
                    FROM TMP_PROVIDER_CHANGES
                    WHERE METADATA$ACTION = ''INSERT'' AND _SNOWFLAKE_DELETED = FALSE;
                    rows_inserted := SQLROWCOUNT;

                    DROP TABLE IF EXISTS TMP_PROVIDER_CHANGES;
                    RETURN ''Closed: '' || rows_closed || '' | Inserted: '' || rows_inserted;
                END;
                $$
            ';

            EXECUTE IMMEDIATE '
                CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_PROD
                    WAREHOUSE = WH_XS
                    COMMENT   = ''SCD2 refresh for FACETS_PROD.SILVER.PROVIDER_SCD2_VIA_STREAM''
                    AFTER     FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_QA
                    WHEN      SYSTEM$STREAM_HAS_DATA(''FACETS_BRONZE.UTILS.PRPR_PROV_CHANGE_STREAM_PROD'')
                AS
                    CALL FACETS_PROD.SILVER.SP_PROVIDER_SCD2_STREAM_REFRESH()
            ';

        END IF;
        log_out := log_out || '[PROD] Done. Rows loaded: ' || :prod_count::VARCHAR || '\n';
    END IF;

    -- =========================================================================
    -- STEP E: Resume task chain (leaf → root)
    -- =========================================================================
    IF (NOT :P_DRY_RUN) THEN
        ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_PROD   RESUME;
        ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_QA     RESUME;
        ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_DEV     RESUME;
        ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_PROD            RESUME;
        ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_QA              RESUME;
        ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_DEV             RESUME;
        ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK          RESUME;
    END IF;
    log_out := log_out || '\n[E] Task chain resumed\n';

    log_out := log_out || '\n=== COMPLETE ===\n'
            || 'DEV rows:  ' || :dev_count::VARCHAR  || '\n'
            || 'QA rows:   ' || :qa_count::VARCHAR   || '\n'
            || 'PROD rows: ' || :prod_count::VARCHAR || '\n';

    RETURN :log_out;

END;
$$;


-- =============================================================================
-- STEP 2: Verify the procedure was created
-- =============================================================================

SHOW PROCEDURES LIKE 'SP_REBUILD_PROVIDER_SCD2_PIPELINE' IN SCHEMA FACETS_BRONZE.UTILS;


-- =============================================================================
-- STEP 3: CALL examples  (DO NOT RUN unless you want to rebuild from scratch)
-- =============================================================================

-- Rebuild all three environments (full reset)
CALL FACETS_BRONZE.UTILS.SP_REBUILD_PROVIDER_SCD2_PIPELINE(
    P_REBUILD_DEV  => TRUE,
    P_REBUILD_QA   => TRUE,
    P_REBUILD_PROD => TRUE,
    P_DRY_RUN      => FALSE
);

-- Rebuild DEV only (e.g. after a dev stream got corrupted)
CALL FACETS_BRONZE.UTILS.SP_REBUILD_PROVIDER_SCD2_PIPELINE(
    P_REBUILD_DEV  => TRUE,
    P_REBUILD_QA   => FALSE,
    P_REBUILD_PROD => FALSE,
    P_DRY_RUN      => FALSE
);

-- Rebuild QA + PROD only (e.g. after promoting from dev)
CALL FACETS_BRONZE.UTILS.SP_REBUILD_PROVIDER_SCD2_PIPELINE(
    P_REBUILD_DEV  => FALSE,
    P_REBUILD_QA   => TRUE,
    P_REBUILD_PROD => TRUE,
    P_DRY_RUN      => FALSE
);

-- Dry run — logs what would happen without executing anything
CALL FACETS_BRONZE.UTILS.SP_REBUILD_PROVIDER_SCD2_PIPELINE(
    P_REBUILD_DEV  => TRUE,
    P_REBUILD_QA   => TRUE,
    P_REBUILD_PROD => TRUE,
    P_DRY_RUN      => TRUE
);
