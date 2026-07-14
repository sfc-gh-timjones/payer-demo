-- =============================================================================
-- FILE: 06.4_schema_revert_snow.sql
-- PURPOSE: Reset CMC_PRTP_PROV_TYPE in Snowflake after the schema drift demo.
--          Dropping the Bronze table reverts all three change types at once:
--            • 5 new rows (PRTP_ID 9001-9005) with PRTP_EFFECTIVE_DT
--            • Updated row (PRTP_ID 7: description change)
--            • Soft-deleted row (PRTP_ID 2: _SNOWFLAKE_DELETED = TRUE)
--          After drop, re-adding to Openflow triggers a clean full reload.
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