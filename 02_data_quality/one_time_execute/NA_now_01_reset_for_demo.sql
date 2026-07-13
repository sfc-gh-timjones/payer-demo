-- =============================================================================
-- FILE: 01_reset_for_demo.sql
-- PURPOSE: Run before each demo session to restore a clean DQ baseline.
--          1. Removes any dirty data left from the previous demo run
--          2. Optionally seeds historical trend data for the DMF charts
--          3. Verifies all expectations are passing before you go live
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WH_XS;
USE DATABASE zzFACETS_DEV_CLONE;
USE SCHEMA SILVER;


-- =============================================================================
-- STEP 1: Clean any dirty records from the previous run
-- Removes the 5 injected rows (MEME_ID 9000001-9000004 + DUPLICATE_ records).
-- Safe to run even if already clean — deletes 0 rows without error.
-- =============================================================================

CALL SILVER.CLEAN_DIRTY_DATA();


-- =============================================================================
-- STEP 2 (optional): Seed historical trend data for DMF charts
-- Run 2-3 inject → wait ~30 sec → clean cycles to populate the trend timeline.
-- Skip if charts already have history from previous sessions.
--
-- Cycle 1:
CALL SILVER.INJECT_DIRTY_DATA();
-- Wait ~30 seconds for DMFs to evaluate, then:
CALL SILVER.CLEAN_DIRTY_DATA();
-- Wait ~30 seconds for DMFs to evaluate, then run Cycle 2:
-- CALL SILVER.INJECT_DIRTY_DATA();
-- Wait ~30 seconds, then:
-- CALL SILVER.CLEAN_DIRTY_DATA();
-- =============================================================================


-- =============================================================================
-- STEP 3: Verify clean baseline — all expectations should pass before going live
-- DMFs re-evaluate ~30 seconds after the last CLEAN. Run this after the wait.
-- =============================================================================

SELECT
    METRIC_NAME,
    ARGUMENT_NAMES                              AS column_name,
    EXPECTATION_EXPRESSION,
    VALUE,
    EXPECTATION_VIOLATED,
    MEASUREMENT_TIME
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS
WHERE TABLE_NAME     = 'MEMBER'
  AND TABLE_SCHEMA   = 'SILVER'
  AND TABLE_DATABASE = 'ZZFACETS_DEV_CLONE'
ORDER BY EXPECTATION_VIOLATED DESC, METRIC_NAME;
-- All EXPECTATION_VIOLATED values should be FALSE before starting the demo.
-- If any show TRUE, wait another 30 seconds and re-run this query.
