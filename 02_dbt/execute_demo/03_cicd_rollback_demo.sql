-- =============================================================================
-- FILE: cicd_rollback_demo.sql
-- PURPOSE: Demo Scenario 6 — CI/CD rollback using Snowflake Time Travel.

/*
  PRE-DEMO SETUP: In caloptima_dw/models/silver/provider_office_hours.sql,
  activate the bad code by swapping the two commented blocks:

  1. In the SELECT, comment out the correct line and uncomment the bad one:
        -- PROF_DAY_OF_WK,             ← comment this out
        'BAD' AS PROF_DAY_OF_WK,       ← uncomment this

  2. In the WHERE clause, comment out the correct filter and uncomment the bad one:
        -- _SNOWFLAKE_UPDATED_AT > ... ← comment this out
        PROF_ID % 2 = 0                ← uncomment this

  Then commit to dev, open a PR to main, and let CI/CD deploy it.
  When run incrementally, ~1,981 rows will be MERGEd with PROF_DAY_OF_WK = 'BAD'.

  The table is never dropped (MERGE, not full refresh) so Time Travel is intact.

  After the demo, revert the bad commit:
      git revert <bad-commit-sha>
      git push origin dev
  Open a new PR and let CI/CD redeploy the corrected model.
*/
--
-- DEMO STORY:
--   1. Bad code merged via PR → CI/CD deployed it
--   2. Run incremental → bad filter + bad value MERGEs 'BAD' into ~1,981 rows
--   3. Provider directory is broken — half the office hours show day = 'BAD'
--   4. Use Time Travel to restore retrospectively, no data reload needed
--   5. Swap atomically — table restored with no downtime
--
-- KEY TALKING POINT:
--   MERGE (not full refresh) = table object stays intact = Time Travel works.
--   Snowflake separates data recovery from code recovery.
--   Table is never down waiting for a code review to complete.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE FACETS_DEV;
USE SCHEMA SILVER;

-- =============================================================================
-- STEP 1: Confirm the damage
-- =============================================================================

-- Overall row count
SELECT COUNT(*) AS total_rows FROM FACETS_DEV.SILVER.PROVIDER_OFFICE_HOURS;

-- How many rows have the corrupted day value
SELECT PROF_DAY_OF_WK, COUNT(*) AS cnt
FROM FACETS_DEV.SILVER.PROVIDER_OFFICE_HOURS
GROUP BY PROF_DAY_OF_WK
ORDER BY cnt DESC;


-- =============================================================================
-- STEP 2: Run the incremental model to introduce the damage
--         (skip if damage is already present from a prior run)
-- =============================================================================

EXECUTE DBT PROJECT ANALYTICS_ADMIN.PROJECTS.CALOPTIMA_DW_DEV
    ARGS = 'run --select provider_office_hours --target dev';

-- Capture query ID IMMEDIATELY — before running anything else
SET bad_run_id = LAST_QUERY_ID();
SELECT $bad_run_id AS bad_run_query_id;

-- Confirm damage — BAD should now appear
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
    BEFORE (STATEMENT => $bad_run_id);                               -- ← most precise: uses captured query ID
    -- BEFORE (TIMESTAMP => DATEADD(minute, -5, CURRENT_TIMESTAMP()));  -- ← by time: 5 min ago
    -- BEFORE (OFFSET => -300);                                         -- ← by offset: 300 seconds back


-- =============================================================================
-- STEP 4: Verify the restored data looks correct
-- =============================================================================

SELECT PROF_DAY_OF_WK, COUNT(*) AS cnt
FROM FACETS_DEV.SILVER.PROVIDER_OFFICE_HOURS_RESTORE
GROUP BY PROF_DAY_OF_WK
ORDER BY cnt DESC;
-- Should show MON/TUE/WED/THU/FRI/SAT/SUN with no BAD


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

SELECT PROF_DAY_OF_WK, COUNT(*) AS cnt
FROM FACETS_DEV.SILVER.PROVIDER_OFFICE_HOURS
GROUP BY PROF_DAY_OF_WK
ORDER BY cnt DESC;
-- BAD is gone — MON/TUE/WED/THU/FRI/SAT/SUN back to normal


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
