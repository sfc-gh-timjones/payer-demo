-- =============================================================================
-- FILE: 06.4_schema_revert_snow.sql
-- PURPOSE: Reset CMC_NWNW_NETWORK in Snowflake after the schema drift demo.
--          Drop the Bronze table, then re-add it to Openflow replication so
--          Openflow performs a fresh initial snapshot with the clean schema.
--
-- WORKFLOW:
--   1. Run 06.3_schema_revert_mssql.sql in SQL Server first
--   2. In Openflow UI: remove CMC_NWNW_NETWORK from "Included Table Names"
--      (use the list in 06.1_openflow_table_list.sql minus the last entry)
--   3. Run the DROP TABLE below in Snowflake
--   4. In Openflow UI: add CMC_NWNW_NETWORK back to "Included Table Names"
--      (paste the full list from 06.1_openflow_table_list.sql)
--   5. Openflow will detect the table is new and perform an initial snapshot load
--   6. Run the verification queries at the bottom to confirm clean state
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE FACETS_BRONZE;
USE SCHEMA RAW;

-- =============================================================================
-- STEP 1: Confirm current state before dropping
-- =============================================================================

DESCRIBE TABLE FACETS_BRONZE.RAW.CMC_NWNW_NETWORK;
SELECT * FROM FACETS_BRONZE.RAW.CMC_NWNW_NETWORK ORDER BY NWNW_ID;

-- =============================================================================
-- STEP 2: Drop the table so Openflow can re-onboard it clean
--
-- After this, Openflow will treat CMC_NWNW_NETWORK as a new table and run an
-- initial snapshot load (INCREMENTAL_REPLICATION → SNAPSHOT → back to CDC).
-- All Openflow CDC metadata (_SNOWFLAKE_INSERTED_AT, _SNOWFLAKE_DELETED, etc.)
-- will be fresh with no NWNW_REGION history.
-- =============================================================================

DROP TABLE IF EXISTS FACETS_BRONZE.RAW.CMC_NWNW_NETWORK;

-- Confirm it's gone
SHOW TABLES LIKE 'CMC_NWNW_NETWORK' IN SCHEMA FACETS_BRONZE.RAW;

-- =============================================================================
-- STEP 3: After Openflow re-onboards the table, run these to verify clean state
-- =============================================================================

-- Confirm schema matches SQL Server (no NWNW_REGION column)
DESCRIBE TABLE FACETS_BRONZE.RAW.CMC_NWNW_NETWORK;

-- Confirm row count matches SQL Server source (~20 original rows)
SELECT COUNT(*) AS row_count FROM FACETS_BRONZE.RAW.CMC_NWNW_NETWORK;

-- Confirm no rows with NWNW_ID >= 101 (demo rows are gone)
SELECT * FROM FACETS_BRONZE.RAW.CMC_NWNW_NETWORK ORDER BY NWNW_ID;

-- =============================================================================
-- REFERENCE: Openflow "Included Table Names" table list
-- See 05.1_reset_snow.sql (STEP 3) for the full copy-paste block.
-- =============================================================================
