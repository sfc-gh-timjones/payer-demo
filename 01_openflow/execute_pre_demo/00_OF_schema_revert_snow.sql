-- =============================================================================
-- FILE: 06.4_schema_revert_snow.sql
-- PURPOSE: Reset CMC_PRTP_PROV_TYPE in Snowflake after the schema drift demo.
--          Drop the Bronze table, then re-add it to Openflow replication.
--
-- WORKFLOW:
-- SNOWFLAKE FIRST
-- 1. REMOVE FROM OPENFLOW REPLICATION
-- 2. RUN BELOW SCRIPT

-- THEN 

--SQL SERVER
-- Run revert script in mssql. 
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Drop so Openflow re-onboards clean (no PRTP_EFFECTIVE_DT column history)
DROP TABLE IF EXISTS FACETS_BRONZE.RAW.CMC_PRTP_PROV_TYPE;

-- Confirm it's gone
SHOW TABLES LIKE 'CMC_PRTP_PROV_TYPE' IN SCHEMA FACETS_BRONZE.RAW;

-- =============================================================================
-- Drop Openflow journal tables for CMC_PRTP_PROV_TYPE
-- Journal tables accumulate with unpredictable suffixes each Openflow run,
-- e.g. CMC_PRTP_PROV_TYPE_JOURNAL_1783717081_1
--      CMC_PRTP_PROV_TYPE_JOURNAL_1783968863_1
-- The stored procedure below finds them all dynamically via INFORMATION_SCHEMA
-- and drops them. Run the preview SELECT first to confirm what will be dropped.
-- =============================================================================

-- Preview: see which journal tables exist before dropping
SELECT TABLE_NAME,
       CREATED,
       LAST_ALTERED
FROM FACETS_BRONZE.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'RAW'
  AND TABLE_NAME LIKE 'CMC_PRTP_PROV_TYPE_JOURNAL%'
ORDER BY TABLE_NAME;

-- Execute: drop all matching journal tables dynamically
CREATE OR REPLACE PROCEDURE FACETS_BRONZE.UTILS.DROP_PRTP_PROV_TYPE_JOURNALS()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    FOR rec IN (
        SELECT TABLE_NAME
        FROM FACETS_BRONZE.INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA = 'RAW'
          AND TABLE_NAME LIKE 'CMC_PRTP_PROV_TYPE_JOURNAL%'
    ) DO
        EXECUTE IMMEDIATE 'DROP TABLE IF EXISTS FACETS_BRONZE.RAW.' || rec.TABLE_NAME;
    END FOR;
    RETURN 'Journal tables dropped.';
END;
$$;

CALL FACETS_BRONZE.UTILS.DROP_PRTP_PROV_TYPE_JOURNALS();