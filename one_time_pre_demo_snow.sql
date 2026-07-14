/***************************************************************************************************

BEFORE RUNNING: 

Need to go into Openflow and manually remove the below table from replication:
FACETS_BRONZE.RAW.CMC_PRTP_PROV_TYPE

MANUALLY DELETE JOURNAL TABLES FOR CMC_PRTP_PROV_TYPE

Run silver/provider_office_hours with correct code manually as a full load (IMPORTANT)

Make sure error is introduced into the silver/provider_office_hours model and DEPLOYED to Dbt Project object BUT NOT RUN (you will run during demo).

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
     Drops CMC_PRTP_PROV_TYPE so Openflow can re-onboard it cleanly.
     NOTE: Run the matching mssql script in SQL Server BEFORE re-adding the
     table to Openflow replication.
=============================================================================*/

EXECUTE IMMEDIATE FROM
    @DEMO_DEPLOY.GIT.CALOPTIMA_REPO/branches/dev/01_openflow/execute_pre_demo/00_OF_schema_revert_snow.sql;



/*=============================================================================
  4. GOVERNANCE — restore Business Analyst role access
     Re-grants access revoked during the Part 2 REVOKE demo in 03_security_demo.
=============================================================================*/

EXECUTE IMMEDIATE FROM
    @DEMO_DEPLOY.GIT.CALOPTIMA_REPO/branches/dev/04_governance_demo/execute_pre_demo/01_restore_ba_access.sql;


/*=============================================================================
  DONE!

  CalOptima demo environment is reset and ready. Run demo scripts in order:
    01_openflow/         Pillar 1: Openflow CDC / Schema Drift
    02_performance_scale/ Pillar 2: Performance & Scale
    03_data_quality/      Pillar 3: Data Quality (wait ~30s for DMF eval)
    04_governance_demo/   Pillar 4: Governance / Security

  mssql files NOT executed here — run these in SQL Server first:
    01_openflow/execute_pre_demo/01_OF_schema_revert_mssql.sql
=============================================================================*/

SELECT 'CalOptima demo environment reset and ready. Now go run the SQL Server cleanup script.' AS status;
