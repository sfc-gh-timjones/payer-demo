-- =============================================================================
-- FILE: 07_schema_drift_cleanup.sql
-- PURPOSE: Post-demo cleanup — removes CMC_PRTP_PROV_TYPE from Snowflake
--          after the schema drift demo is complete.
--
-- !! IMPORTANT — Follow this order exactly !!
--
-- STEP 1 (Openflow UI — do this FIRST):
--   Remove CMC_PRTP_PROV_TYPE from the connector's included table list.
--   If Openflow is still replicating the table when you drop it in Snowflake,
--   the connector will error on its next polling cycle.
--
-- STEP 2 (This script — run after Step 1 is complete):
--   Drop the table from FACETS_BRONZE.RAW.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE FACETS_BRONZE;
USE SCHEMA RAW;

-- Confirm it exists before dropping
SHOW TABLES LIKE 'CMC_PRTP_PROV_TYPE' IN SCHEMA FACETS_BRONZE.RAW;

-- Drop the schema drift demo table
DROP TABLE IF EXISTS FACETS_BRONZE.RAW.CMC_PRTP_PROV_TYPE;

-- Verify it is gone
SHOW TABLES LIKE 'CMC_PRTP_PROV_TYPE' IN SCHEMA FACETS_BRONZE.RAW;
