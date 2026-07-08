-- =============================================================================
-- FILE: 06.4_schema_revert_snow.sql
-- PURPOSE: Reset CMC_PRTP_PROV_TYPE in Snowflake after the schema drift demo.
--          Drop the Bronze table, then re-add it to Openflow replication.
--
-- WORKFLOW:
--   1. Run 06.3_schema_revert_mssql.sql in SQL Server first
--   2. In Openflow UI: remove CMC_PRTP_PROV_TYPE from "Included Table Names"
--   3. Run the DROP TABLE below in Snowflake
--   4. In Openflow UI: add CMC_PRTP_PROV_TYPE back — fresh snapshot load
--   5. Run verification queries to confirm clean state
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE FACETS_BRONZE;
USE SCHEMA RAW;

-- Confirm state before dropping
DESCRIBE TABLE FACETS_BRONZE.RAW.CMC_PRTP_PROV_TYPE;
SELECT COUNT(*) AS row_count FROM FACETS_BRONZE.RAW.CMC_PRTP_PROV_TYPE;

-- Drop so Openflow re-onboards clean (no PRTP_EFFECTIVE_DT column history)
DROP TABLE IF EXISTS FACETS_BRONZE.RAW.CMC_PRTP_PROV_TYPE;

-- Confirm it's gone
SHOW TABLES LIKE 'CMC_PRTP_PROV_TYPE' IN SCHEMA FACETS_BRONZE.RAW;

-- After Openflow re-onboards, verify clean state
-- DESCRIBE TABLE FACETS_BRONZE.RAW.CMC_PRTP_PROV_TYPE;
-- SELECT COUNT(*) AS row_count FROM FACETS_BRONZE.RAW.CMC_PRTP_PROV_TYPE;  -- expect 15, no PRTP_ID >= 9001
