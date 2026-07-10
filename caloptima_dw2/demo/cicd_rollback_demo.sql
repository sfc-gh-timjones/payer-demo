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
--   2. Trigger full refresh — bad filter wipes Active members
--   3. Capture LAST_QUERY_ID(), clone MEMBER to a restore point BEFORE that run
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

-- Capture query ID IMMEDIATELY — before running anything else
SET bad_run_id = LAST_QUERY_ID();
SELECT $bad_run_id AS bad_run_query_id;   -- show it for transparency

-- Now re-check — row count should have collapsed (only MEME_STS = 'IN' rows survive)
SELECT COUNT(*) AS bad_row_count FROM FACETS_DEV.SILVER.MEMBER;


-- =============================================================================
-- STEP 3: Clone to a restore point — three ways to target it (pick one)
--         Full refresh = DROP + CTAS inside dbt, so $bad_run_id is the outer
--         EXECUTE DBT PROJECT statement — Snowflake resolves the table state
--         to just before that wrapper statement started.
-- =============================================================================

CREATE TABLE FACETS_DEV.SILVER.MEMBER_RESTORE
    CLONE FACETS_DEV.SILVER.MEMBER
    BEFORE (STATEMENT => $bad_run_id);                               -- ← most precise: uses captured query ID
    -- BEFORE (TIMESTAMP => DATEADD(minute, -1, CURRENT_TIMESTAMP()));  -- ← by time: 1 min ago
    -- BEFORE (OFFSET => -60);                                          -- ← by offset: 60 seconds back


-- =============================================================================
-- STEP 4: Verify the restored data looks correct BEFORE swapping

SELECT COUNT(*) AS restored_row_count FROM FACETS_DEV.SILVER.MEMBER_RESTORE;


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
-- It will now match the RESTORE count from Step 4


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
