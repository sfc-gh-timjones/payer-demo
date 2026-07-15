-- =============================================================================
-- FILE: reset_office_hours_clean.sql
-- PURPOSE: Pre-demo reset for CI/CD rollback demo.
--
--   The dev CI/CD pipeline keeps provider_office_hours.sql with BAD code active
--   so the demo runs correctly. This script rebuilds the Silver table with clean
--   data BEFORE the demo starts, giving Step 1 of the demo a pristine baseline.
--
--   Called from one_time_pre_demo_snow.sql (Section 3) via EXECUTE IMMEDIATE.
--
-- HOW IT WORKS:
--   dbt has no internal table ownership metadata — it purely checks IF TABLE EXISTS
--   to decide incremental vs full-build. Replacing the table directly with
--   CREATE OR REPLACE TABLE is safe and gives us a clean Time Travel baseline.
--
-- AFTER THE DEMO:
--   After the Time Travel + SWAP in Steps 3-6 of the rollback demo, the table is
--   back to clean data automatically. This script only needs to run at demo start.
-- =============================================================================

USE ROLE      ACCOUNTADMIN;
USE WAREHOUSE WH_XS;
USE DATABASE  FACETS_DEV;
USE SCHEMA    SILVER;

-- Rebuild with clean data from staging (bypasses incremental bad-code filter)
CREATE OR REPLACE TABLE FACETS_DEV.SILVER.PROVIDER_OFFICE_HOURS AS
SELECT
    PROF_ID,
    PRPR_ID,
    PROF_DAY_OF_WK,
    PROF_OPEN_TM,
    PROF_CLOSE_TM,
    _SNOWFLAKE_DELETED    AS IS_DELETED,
    _SNOWFLAKE_UPDATED_AT AS BRONZE_UPDATED_AT,
    CURRENT_TIMESTAMP()   AS SILVER_LOADED_AT
FROM FACETS_DEV.STAGING.STG_PROF_OFF_HRS;

-- Verify: bad_rows should be 0, total_rows should be the full set
SELECT
    COUNT(*)                                    AS total_rows,
    COUNT_IF(PROF_DAY_OF_WK = 'Bad Data Inserted Here') AS bad_rows,
    COUNT(DISTINCT PROF_DAY_OF_WK)             AS distinct_days
FROM FACETS_DEV.SILVER.PROVIDER_OFFICE_HOURS;
