-- =============================================================================
-- FILE: cicd_rollback_demo.sql
-- PURPOSE: Demo Scenario 6 — CI/CD rollback using Snowflake Time Travel.
--
-- DEMO STORY:
--   1. Bad code merged via PR → CI/CD deployed it
--   2. Run incremental → bad filter + bad value MERGEs 'Bad Data Inserted Here' into ~1,981 rows
--   3. Provider directory is broken — half the office hours show day = 'Bad Data Inserted Here'
--   4. Use Time Travel to restore retrospectively, no data reload needed
--   5. Swap atomically — table restored with no downtime

-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE FACETS_DEV;
USE SCHEMA SILVER;

-- =============================================================================
-- STEP 1: View table
-- =============================================================================

-- Overall row count
SELECT COUNT(*) AS total_rows FROM FACETS_DEV.SILVER.PROVIDER_OFFICE_HOURS;

-- Clean data: 5 days of the weekday
SELECT PROF_DAY_OF_WK, COUNT(*) AS cnt
FROM FACETS_DEV.SILVER.PROVIDER_OFFICE_HOURS
GROUP BY PROF_DAY_OF_WK
ORDER BY cnt DESC;

SELECT *
FROM FACETS_DEV.SILVER.PROVIDER_OFFICE_HOURS
ORDER BY PROF_DAY_OF_WK; 

-- =============================================================================
-- STEP 2: Run the incremental model to introduce the damage
--         (skip if damage is already present from a prior run)
-- =============================================================================

EXECUTE DBT PROJECT ANALYTICS_ADMIN.PROJECTS.CALOPTIMA_DW_DEV
    ARGS = 'run --select provider_office_hours --target dev';

-- Capture query ID of last run
SET bad_run_id = LAST_QUERY_ID();
SELECT $bad_run_id AS bad_run_query_id;

--view bad data introduced on last run
SELECT *
FROM FACETS_DEV.SILVER.PROVIDER_OFFICE_HOURS
ORDER BY PROF_DAY_OF_WK; 

SELECT PROF_DAY_OF_WK, COUNT(*) AS cnt
FROM FACETS_DEV.SILVER.PROVIDER_OFFICE_HOURS
GROUP BY PROF_DAY_OF_WK
ORDER BY cnt DESC;

-- =============================================================================
-- STEP 3: Clone to a restore point using Time Travel
--         MERGE preserves the table object — Time Travel history is intact.
-- =============================================================================

CREATE TABLE FACETS_DEV.SILVER.PROVIDER_OFFICE_HOURS_RESTORE
    CLONE FACETS_DEV.SILVER.PROVIDER_OFFICE_HOURS
    BEFORE (STATEMENT => $bad_run_id);
    
    -- BEFORE (TIMESTAMP => DATEADD(minute, -5, CURRENT_TIMESTAMP()));  
    -- BEFORE (OFFSET => -300);                                        

-- =============================================================================
-- STEP 4: Verify the restored data looks correct
-- =============================================================================

SELECT PROF_DAY_OF_WK, COUNT(*) AS cnt
FROM FACETS_DEV.SILVER.PROVIDER_OFFICE_HOURS_RESTORE
GROUP BY PROF_DAY_OF_WK
ORDER BY cnt DESC;
-- Shows MON/TUE/WED/THU/FRI/SAT/SUN with no 'Bad Data Inserted Here'

-- =============================================================================
-- STEP 5: Swap atomically
--         SWAP WITH preserves all grants, pipes, streams, and object identity.
--         Production is restored in a single atomic operation — no downtime.
-- =============================================================================

ALTER TABLE FACETS_DEV.SILVER.PROVIDER_OFFICE_HOURS
    SWAP WITH FACETS_DEV.SILVER.PROVIDER_OFFICE_HOURS_RESTORE;

-- =============================================================================
-- STEP 6: Confirm the swap worked
-- =============================================================================

SELECT *
FROM FACETS_DEV.SILVER.PROVIDER_OFFICE_HOURS
ORDER BY PROF_DAY_OF_WK; 


SELECT PROF_DAY_OF_WK, COUNT(*) AS cnt
FROM FACETS_DEV.SILVER.PROVIDER_OFFICE_HOURS
GROUP BY PROF_DAY_OF_WK
ORDER BY cnt DESC;
-- 'Bad Data Inserted Here' is gone — MON/TUE/WED/THU/FRI/SAT/SUN back to normal

-- =============================================================================
-- STEP 7: Clean up the temp table (now holds the bad data)
-- =============================================================================

DROP TABLE FACETS_DEV.SILVER.PROVIDER_OFFICE_HOURS_RESTORE;


-- =============================================================================
-- STEP 8: Fix the code (separate from data recovery)
--
--   git revert <bad-commit-sha>
--   git push origin dev
--   Open PR → CI/CD redeploys the corrected dbt model
--
--   Data was restored immediately in Steps 3-6.
--   The code fix goes through normal PR review at its own pace.
--   The Silver table is never down waiting for a code review.
-- =============================================================================
