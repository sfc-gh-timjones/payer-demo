/***************************************************************************************************
|  C | A | L | O | P | T | I | M | A  |  D  |  E  |  M  |  O  |

One-click pre-demo reset! This script:
    1. Creates a temporary deploy database + git repo pointer
    2. Fetches the latest code from the caloptima GitHub repo
    3. Runs all execute_pre_demo scripts in folder order via EXECUTE IMMEDIATE FROM
       (mssql files are excluded — run those separately in SQL Server)

  Files executed in order:
    01_openflow  /execute_pre_demo/00_OF_schema_revert_snow.sql
    02_data_quality/execute_pre_demo/01_reset_for_demo.sql
    03_governance_demo/execute_pre_demo/01_restore_ba_access.sql

  BEFORE RUNNING:
    - Ensure GIT_HUB_INTEGRATION API integration exists (see 01_openflow/one_time_execute/github_actions_setup.sql)
    - Run mssql pre-demo scripts separately in SQL Server first
    - Confirm Openflow connector is running and tables are current

  AFTER THIS COMPLETES:
    - Schema drift table (CMC_PRTP_PROV_TYPE) is dropped + ready for re-onboarding
    - Data quality baseline is clean (dirty records removed, one inject/clean cycle run)
    - Business Analyst role access is restored after any REVOKE demos
    - Run demo scripts in each folder in order
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

CREATE OR REPLACE GIT REPOSITORY DEMO_DEPLOY.GIT.CALOPTIMA_REPO
    API_INTEGRATION = GIT_HUB_INTEGRATION
    ORIGIN          = 'https://github.com/sfc-gh-timjones/caloptima';

-- Pull latest commits from GitHub
ALTER GIT REPOSITORY DEMO_DEPLOY.GIT.CALOPTIMA_REPO FETCH;


/*=============================================================================
  2. OPENFLOW — schema revert (Snowflake side)
     Drops CMC_PRTP_PROV_TYPE so Openflow can re-onboard it cleanly.
     NOTE: Run the matching mssql script in SQL Server BEFORE re-adding the
     table to Openflow replication.
=============================================================================*/

EXECUTE IMMEDIATE FROM
    @DEMO_DEPLOY.GIT.CALOPTIMA_REPO/branches/dev/01_openflow/execute_pre_demo/00_OF_schema_revert_snow.sql;


/*=============================================================================
  3. DATA QUALITY — clean baseline reset
     Removes dirty records from the previous run, seeds one inject/clean cycle
     for DMF trend charts, then verifies all expectations pass.
     Wait ~30 seconds after this completes for DMFs to evaluate before going live.
=============================================================================*/

EXECUTE IMMEDIATE FROM
    @DEMO_DEPLOY.GIT.CALOPTIMA_REPO/branches/dev/02_data_quality/execute_pre_demo/01_reset_for_demo.sql;


/*=============================================================================
  4. GOVERNANCE — restore Business Analyst role access
     Re-grants access revoked during the Part 2 REVOKE demo in 03_security_demo.
=============================================================================*/

EXECUTE IMMEDIATE FROM
    @DEMO_DEPLOY.GIT.CALOPTIMA_REPO/branches/dev/03_governance_demo/execute_pre_demo/01_restore_ba_access.sql;


/*=============================================================================
  DONE!

  CalOptima demo environment is reset and ready. Run demo scripts in order:
    01_openflow/         Pillar 1: Openflow CDC / Schema Drift
    02_data_quality/     Pillar 2: Data Quality (wait ~30s for DMF eval)
    03_governance_demo/  Pillar 3: Governance / Security
    04_performance_scale/ Pillar 4: Performance & Scale

  mssql files NOT executed here — run these in SQL Server first:
    01_openflow/execute_pre_demo/01_OF_schema_revert_mssql.sql
=============================================================================*/

SELECT 'CalOptima demo environment reset and ready.' AS status;
