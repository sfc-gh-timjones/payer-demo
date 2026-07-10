-- =============================================================================
-- FILE: cicd_rollback_demo.sql
-- PURPOSE: Demo Scenario 6 — CI/CD rollback using Snowflake Time Travel.
--          Shows how to restore SILVER.MEMBER to a pre-deployment state
--          without reloading any Bronze data or re-running the pipeline.
--
-- DEMO STORY:
--   1. A bad dbt change merges via PR → CI/CD deploys it → Silver data is wrong
--   2. Use Time Travel to identify the bad MERGE statement's query ID
--   3. Clone MEMBER to a restore point BEFORE that bad run
--   4. Verify the restored data looks correct
--   5. Swap atomically — production table is restored instantly
--   6. Clean up the temp table
--   7. Separately: git revert the bad code commit and let CI/CD redeploy cleanly
--
-- KEY TALKING POINT:
--   Snowflake separates data recovery from code recovery.
--   Data is restored in seconds while the code fix goes through proper PR review.
--   The table is never down waiting for a code review to complete.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE FACETS_DEV;
USE SCHEMA SILVER;

-- =============================================================================
-- STEP 1: Show current (bad) state after the bad deployment
-- =============================================================================

SELECT COUNT(*) AS current_row_count FROM FACETS_DEV.SILVER.MEMBER;

-- Expected: row count is wrong (too low, or data is missing/incorrect)


-- =============================================================================
-- STEP 2: Find the query ID of the bad dbt MERGE run
--         Look for the MERGE into MEMBER from the last CI/CD execution
-- =============================================================================

SELECT
    QUERY_ID,
    LEFT(QUERY_TEXT, 120)   AS query_preview,
    START_TIME,
    TOTAL_ELAPSED_TIME / 1000 AS elapsed_seconds,
    ROWS_INSERTED,
    ROWS_UPDATED
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_USER(USER_NAME => 'ADMIN'))
WHERE QUERY_TEXT ILIKE '%MERGE%INTO%MEMBER%'
  AND START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC
LIMIT 10;

-- Copy the QUERY_ID of the bad run from the results above
-- and paste it into the BEFORE (STATEMENT => ...) clauses below


-- =============================================================================
-- STEP 3: Clone to a NEW table first — non-destructive, zero-copy
--         Replace the query ID placeholder with the actual ID from Step 2
-- =============================================================================

CREATE TABLE FACETS_DEV.SILVER.MEMBER_RESTORE
    CLONE FACETS_DEV.SILVER.MEMBER
    BEFORE (STATEMENT => '01b3f4e2-0001-a2b3-0000-000100012345');  -- ← replace


-- =============================================================================
-- STEP 4: Verify the restored data looks correct BEFORE swapping
-- =============================================================================

-- Row count — should match expected pre-deployment count
SELECT COUNT(*) AS restored_row_count FROM FACETS_DEV.SILVER.MEMBER_RESTORE;

-- Spot-check: active members with PCP assignments present
SELECT COUNT(*) AS active_with_pcp
FROM FACETS_DEV.SILVER.MEMBER_RESTORE
WHERE MEMBER_STATUS = 'Active'
  AND ACTIVE_PCP_PRPR_ID IS NOT NULL;

-- Side-by-side comparison
SELECT 'CURRENT (bad)'   AS version, COUNT(*) AS rows FROM FACETS_DEV.SILVER.MEMBER
UNION ALL
SELECT 'RESTORE (good)'  AS version, COUNT(*) AS rows FROM FACETS_DEV.SILVER.MEMBER_RESTORE;


-- =============================================================================
-- STEP 5: Swap atomically
--         SWAP WITH preserves all grants, pipes, streams, and object identity.
--         Production is restored in a single atomic operation — no downtime.
-- =============================================================================

ALTER TABLE FACETS_DEV.SILVER.MEMBER
    SWAP WITH FACETS_DEV.SILVER.MEMBER_RESTORE;


-- =============================================================================
-- STEP 6: Confirm the swap worked
-- =============================================================================

SELECT COUNT(*) AS restored_row_count FROM FACETS_DEV.SILVER.MEMBER;
-- Should now match the RESTORE count from Step 4


-- =============================================================================
-- STEP 7: Clean up the temp table (now holds the bad data)
-- =============================================================================

DROP TABLE FACETS_DEV.SILVER.MEMBER_RESTORE;


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
