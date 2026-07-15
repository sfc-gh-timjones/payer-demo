/***************************************************************************************************

BEFORE RUNNING: 

Need to go into Openflow and manually remove the below table from replication:
FACETS_BRONZE.RAW.CMC_PRTP_PROV_TYPE

Run this script top-to-bottom. It handles:
  - Openflow schema revert (Section 2)
  - PROVIDER_OFFICE_HOURS clean rebuild (Section 3)  ← replaces the manual step
  - Governance role restore (Section 4)

BAD CODE IS ALREADY ACTIVE in provider_office_hours.sql (committed to dev).
Section 3 rebuilds the Silver table with clean data so the demo starts from a
baseline, then Step 2 of the demo runs the bad code incrementally.

***************************************************************************************************/

USE ROLE      ACCOUNTADMIN;
USE WAREHOUSE WH_XS;

/*=============================================================================
  1. DEPLOY DATABASE + GIT REPO
     Creates a lightweight temp database to hold the git repository object.
     Points at the caloptima GitHub repo, branch: dev.
=============================================================================*/

CREATE DATABASE IF NOT EXISTS DEMO_DEPLOY;
CREATE SCHEMA  IF NOT EXISTS DEMO_DEPLOY.GIT;

CREATE GIT REPOSITORY IF NOT EXISTS DEMO_DEPLOY.GIT.CALOPTIMA_REPO
    API_INTEGRATION = MY_GIT_API_INTEGRATION
    GIT_CREDENTIALS = POLICY_SETTINGS.POLICY_SCHEMA.MY_GIT_SECRET
    ORIGIN          = 'https://github.com/sfc-gh-timjones/caloptima';

-- Pull latest commits from GitHub (run this each time to get the newest scripts)
ALTER GIT REPOSITORY DEMO_DEPLOY.GIT.CALOPTIMA_REPO FETCH;


/*=============================================================================
  2. OPENFLOW — schema revert (Snowflake side)
     Drops CMC_PRTP_PROV_TYPE and JOURNAL tables. 
=============================================================================*/

EXECUTE IMMEDIATE FROM
    @DEMO_DEPLOY.GIT.CALOPTIMA_REPO/branches/dev/01_openflow/execute_pre_demo/00_OF_schema_revert_snow.sql;



/*=============================================================================
  3. OPENFLOW — schema revert (SQL Server side)
     Reverts CMC_PRTP_PROV_TYPE data and schema on Azure SQL Server.
     Idempotent: PRTP_ID 2 insert skipped if already present;
     PRTP_EFFECTIVE_DT drop skipped if column already removed.
=============================================================================*/

CALL FACETS_BRONZE.UTILS.OPENFLOW_SCHEMA_REVERT_MSSQL(
    'tjonessqlserver.database.windows.net',
    'openflow'
);


/*=============================================================================
  4. DBT — rebuild PROVIDER_OFFICE_HOURS with clean data
     Bad code is deployed to CALOPTIMA_DW_DEV but NOT yet run.
     This overwrites the Silver table directly so demo Step 1 shows clean data.
     After demo Steps 3-6 (Time Travel + SWAP), the table is clean again automatically.

DEMO-DAY SEQUENCE REMINDER:

1. Bad code already committed to dev branch (provider_office_hours.sql).
2. Push to dev triggers CI: deploys CALOPTIMA_DW_DEV (bad code), skips running provider_office_hours.
3. Run this script LAST — after CI completes — so the Silver table starts clean.
4. Demo Step 1: confirm clean data (all 7 days, no 'Bad Data Inserted Here').
5. Demo Step 2: EXECUTE DBT PROJECT ... CALOPTIMA_DW_DEV — corrupts ~1,981 rows.
6. Demo Steps 3-6: Time Travel clone → verify → SWAP atomically.
7. After the SWAP, data is clean. Pre-reset needed again before the NEXT demo session.
=============================================================================*/

EXECUTE IMMEDIATE FROM
    @DEMO_DEPLOY.GIT.CALOPTIMA_REPO/branches/dev/02_dbt/execute_pre_demo/reset_office_hours_clean.sql;


/*=============================================================================
  5. GOVERNANCE — restore Business Analyst role access
     Re-grants access revoked during the Part 2 REVOKE demo in 03_security_demo.
=============================================================================*/

EXECUTE IMMEDIATE FROM
    @DEMO_DEPLOY.GIT.CALOPTIMA_REPO/branches/dev/06_governance_demo/execute_pre_demo/01_restore_ba_access.sql;


/*=============================================================================
  DONE!
=============================================================================*/

SELECT 'CalOptima demo environment reset and ready.' AS status;