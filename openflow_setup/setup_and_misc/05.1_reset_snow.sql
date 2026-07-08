-- =============================================================================
-- FILE: 05.1_reset_snow.sql
-- PURPOSE: Full reset of FACETS_BRONZE.RAW schema so Openflow can re-onboard
--          all tables from scratch with a clean initial snapshot.
--
-- USE WHEN: Starting the demo over, recovering from a bad state, or re-running
--           the initial load after testing.
--
-- !! WARNING !! This drops ALL tables in FACETS_BRONZE.RAW and the schema itself.
--               All Bronze data will be lost. Only run this in the demo account.
--
-- =============================================================================
-- STEP ORDER — follow exactly:
--
--   STEP 1 (Openflow UI)   → Remove all tables from replication
--   STEP 2 (This script)   → Drop FACETS_BRONZE.RAW schema in Snowflake
--   STEP 3 (Openflow UI)   → Add tables back — Openflow re-creates the schema
--                            and runs a fresh initial snapshot for each table
--
-- =============================================================================

-- =============================================================================
-- STEP 1: OPENFLOW UI — Remove all tables from replication FIRST
--
--   Before running the DROP below, go into the Openflow connector and either:
--     a) Clear the "Included Table Names" field entirely, OR
--     b) Suspend/stop the connector
--
--   If you drop the schema while Openflow is still replicating, the connector
--   will error on the next polling cycle. Remove tables from replication first,
--   then come back and run STEP 2.
-- =============================================================================



-- =============================================================================
-- STEP 2: Drop FACETS_BRONZE.RAW schema (run this after STEP 1 is complete)
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE FACETS_BRONZE;

-- Confirm what will be dropped
SHOW TABLES IN SCHEMA FACETS_BRONZE.RAW;

-- Drop the entire RAW schema and all tables within it
DROP SCHEMA IF EXISTS FACETS_BRONZE.RAW CASCADE;

-- Verify it's gone
SHOW SCHEMAS IN DATABASE FACETS_BRONZE;

-- After reset, use 05.2_table_list.sql to re-onboard all 36 tables in Openflow.
