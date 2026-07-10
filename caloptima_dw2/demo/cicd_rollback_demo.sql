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
--   2. Pre-clone MEMBER as a safety net (zero-copy, instant, no storage cost yet)
--   3. Trigger full refresh — bad filter wipes Active members
--   4. Verify the damage, then swap the pre-clone back in atomically
--   5. Separately: git revert the bad code commit and let CI/CD redeploy cleanly
--
-- KEY TALKING POINT:
--   Zero-copy clone = safety net before risky ops. SWAP WITH = instant atomic restore.
--   Snowflake separates data recovery from code recovery — table is never down
--   waiting for a code review to complete.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE FACETS_DEV;
USE SCHEMA SILVER;

-- =============================================================================
-- STEP 1: Confirm current state is good, then pre-clone as a safety net
--         Zero-copy clone shares storage with the original until data diverges.
--         Do this BEFORE triggering the bad run.
-- =============================================================================

SELECT COUNT(*) AS current_row_count FROM FACETS_DEV.SILVER.MEMBER;
-- Expected: full count intact

CREATE OR REPLACE TRANSIENT TABLE FACETS_DEV.SILVER.MEMBER_RESTORE
    CLONE FACETS_DEV.SILVER.MEMBER;  -- snapshot the good state right now


-- =============================================================================
-- STEP 2: Trigger the full refresh — this is when the bad filter does damage
--         Narrate: "full refreshes happen in prod — someone adds a column,
--         a DBA triggers maintenance, CI runs with --full-refresh flag, etc."
-- =============================================================================

EXECUTE DBT PROJECT ANALYTICS_ADMIN.PROJECTS.CALOPTIMA_DW
    ARGS = 'run --select member --full-refresh --target dev';

-- Show the damage — row count should have collapsed
SELECT COUNT(*) AS bad_row_count FROM FACETS_DEV.SILVER.MEMBER;


-- =============================================================================
-- STEP 3: Verify the restore clone has the good data
-- =============================================================================

SELECT COUNT(*) AS restored_row_count FROM FACETS_DEV.SILVER.MEMBER_RESTORE;
-- Should match the count from Step 1


-- =============================================================================
-- STEP 4: Swap atomically
--         SWAP WITH preserves all grants, pipes, streams, and object identity.
--         Production is restored in a single atomic operation — no downtime.
-- =============================================================================

ALTER TABLE FACETS_DEV.SILVER.MEMBER
    SWAP WITH FACETS_DEV.SILVER.MEMBER_RESTORE;


-- =============================================================================
-- STEP 5: Confirm the swap worked
-- =============================================================================

SELECT COUNT(*) AS restored_row_count FROM FACETS_DEV.SILVER.MEMBER;
-- Should now match the pre-bad count from Step 1


-- =============================================================================
-- STEP 6: Clean up the temp table (now holds the bad data)
-- =============================================================================

DROP TABLE FACETS_DEV.SILVER.MEMBER_RESTORE;


-- =============================================================================
-- STEP 7: Fix the code (separate from data recovery)
--
--   git revert <bad-commit-sha>
--   git push origin dev
--   Open PR → CI/CD redeploys the corrected dbt model
--
--   Data was restored immediately in Steps 4-5.
--   The code fix goes through normal PR review at its own pace.
--   The Silver table is never down waiting for a code review.
-- =============================================================================
