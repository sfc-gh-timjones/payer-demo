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