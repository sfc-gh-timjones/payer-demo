-- =============================================================================
-- FILE: 06.4_schema_revert_snow.sql
-- PURPOSE: Reset CMC_PRFA_FACILITY in Snowflake after the schema drift demo.
--          Drop the Bronze table, then re-add it to Openflow replication.
--
-- WORKFLOW:
--   1. Run 06.3_schema_revert_mssql.sql in SQL Server first
--   2. In Openflow UI: remove CMC_PRFA_FACILITY from "Included Table Names"
--   3. Run the DROP TABLE below in Snowflake
--   4. In Openflow UI: add CMC_PRFA_FACILITY back — fresh snapshot load
--   5. Run verification queries to confirm clean state
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE FACETS_BRONZE;
USE SCHEMA RAW;

-- Confirm state before dropping
DESCRIBE TABLE FACETS_BRONZE.RAW.CMC_PRFA_FACILITY;
SELECT COUNT(*) AS row_count FROM FACETS_BRONZE.RAW.CMC_PRFA_FACILITY;

-- Drop so Openflow re-onboards clean (no PRFA_COUNTY column history)
DROP TABLE IF EXISTS FACETS_BRONZE.RAW.CMC_PRFA_FACILITY;

-- Confirm it's gone
SHOW TABLES LIKE 'CMC_PRFA_FACILITY' IN SCHEMA FACETS_BRONZE.RAW;

-- After Openflow re-onboards, verify clean state
-- DESCRIBE TABLE FACETS_BRONZE.RAW.CMC_PRFA_FACILITY;
-- SELECT COUNT(*) AS row_count FROM FACETS_BRONZE.RAW.CMC_PRFA_FACILITY;  -- expect ~300, no PRFA_ID >= 9001
