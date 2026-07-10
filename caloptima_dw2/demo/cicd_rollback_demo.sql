-- =============================================================================
-- FILE: cicd_rollback_demo.sql
-- PURPOSE: Demo Scenario 6 — CI/CD rollback using Snowflake Time Travel.

/*
  PRE-DEMO SETUP: Introduce a bad change into member.sql to simulate a bad deployment.

  In caloptima_dw/models/silver/member.sql, add this line to the WHERE clause
  at the bottom of the model (just before the {% if is_incremental() %} block):

      WHERE m.IS_DUPLICATE = FALSE
        AND m.MEME_STS = 'IN'     -- ← BAD LINE: only keeps Inactive members, wipes Active ones

  Then commit to a feature branch, open a PR, and let CI/CD merge and deploy it.
  The Silver MEMBER table will drop from ~5000 rows to a small fraction.
  This is the "bad deployment" the rollback demo recovers from.

  After the demo, revert the bad commit:
      git revert <bad-commit-sha>
      git push origin dev
  Open a new PR and let CI/CD redeploy the corrected model.
*/
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
-- STEP 1: Confirm current state is still good (bad code deployed but not yet run)
--         CI/CD ran incrementally — 0 new Bronze rows → existing Silver rows untouched
-- =============================================================================

SELECT COUNT(*) AS current_row_count FROM FACETS_DEV.SILVER.MEMBER;
-- Expected: full count still intact (incremental run did nothing to existing rows)


-- =============================================================================
-- STEP 2: Trigger the full refresh — this is when the bad filter does damage
--         Narrate: "full refreshes happen in prod — someone adds a column,
--         a DBA triggers maintenance, CI runs with --full-refresh flag, etc."
-- =============================================================================

EXECUTE DBT PROJECT ANALYTICS_ADMIN.PROJECTS.CALOPTIMA_DW
    ARGS = 'run --select member --full-refresh --target dev';

-- Now re-check — row count should have collapsed (only MEME_STS = 'IN' rows survive)
SELECT COUNT(*) AS bad_row_count FROM FACETS_DEV.SILVER.MEMBER;


-- =============================================================================
-- STEP 3: Find the query ID of the bad dbt MERGE run
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
WHERE QUERY_TEXT ILIKE '%MERGE%INTO%FACETS_DEV%SILVER%MEMBER%'
  AND START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC
LIMIT 10;

-- NOTE: Filter uses FACETS_DEV (not just MEMBER) because dev and qa now run in
-- parallel in CI — both generate MERGE INTO MEMBER queries at the same time.
-- dbt fully qualifies the table name so FACETS_DEV.SILVER.MEMBER vs
-- FACETS_QA.SILVER.MEMBER appears in the query text, making them distinguishable.

-- Copy the QUERY_ID of the bad run from the results above
-- and paste it into the BEFORE (STATEMENT => ...) clauses below


-- =============================================================================
-- STEP 4: Clone to a NEW table first — non-destructive, zero-copy
--         Replace the query ID placeholder with the actual ID from Step 2
-- =============================================================================

CREATE TABLE FACETS_DEV.SILVER.MEMBER_RESTORE
    CLONE FACETS_DEV.SILVER.MEMBER
    BEFORE (STATEMENT => '01b3f4e2-0001-a2b3-0000-000100012345');  -- ← replace


-- =============================================================================
-- STEP 5: Verify the restored data looks correct BEFORE swapping
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
-- STEP 6: Swap atomically
--         SWAP WITH preserves all grants, pipes, streams, and object identity.
--         Production is restored in a single atomic operation — no downtime.
-- =============================================================================

ALTER TABLE FACETS_DEV.SILVER.MEMBER
    SWAP WITH FACETS_DEV.SILVER.MEMBER_RESTORE;


-- =============================================================================
-- STEP 7: Confirm the swap worked
-- =============================================================================

SELECT COUNT(*) AS restored_row_count FROM FACETS_DEV.SILVER.MEMBER;
-- Should now match the RESTORE count from Step 4


-- =============================================================================
-- STEP 8: Clean up the temp table (now holds the bad data)
-- =============================================================================

DROP TABLE FACETS_DEV.SILVER.MEMBER_RESTORE;


-- =============================================================================
-- STEP 9: Fix the code (separate from data recovery)
--
--   git revert <bad-commit-sha>
--   git push origin dev
--   Open PR → CI/CD redeploys the corrected dbt model
--
--   Data was restored immediately in Steps 3-6.
--   The code fix goes through normal PR review at its own pace.
--   The Silver table is never down waiting for a code review.
-- =============================================================================
