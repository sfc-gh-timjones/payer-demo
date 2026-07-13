/*
================================================================================
  CalOptima RFP 26-038 | Topic 9: Data Quality Demo
  File: 02_dq_demo.sql
  Purpose: Live demo walkthrough — run blocks sequentially during presentation.
           Shows: DMF configuration, clean baseline, violation injection,
           expectation status, alert check, historical trends, and Streamlit app.
  Pre-req:  01_dq_setup.sql must have been run first.
  Tip:      Call INJECT_DIRTY_DATA() + CLEAN_DIRTY_DATA() 2-3 times before
            the presentation to seed historical trend data in the charts.
================================================================================
*/

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WH_XS;
USE DATABASE zzFACETS_DEV_CLONE;
USE SCHEMA SILVER;

/* ============================================================================
   STEP 1: Show DMF configuration on SILVER.MEMBER
   "Here is what Snowflake is continuously monitoring — 9 rules across
    volume, freshness, completeness, validity, and custom healthcare logic."
   ============================================================================ */

-- All DMF associations on the MEMBER table
SELECT
  METRIC_NAME,
  METRIC_DATABASE_NAME || '.' || METRIC_SCHEMA_NAME AS metric_source,
  PARSE_JSON(REF_ARGUMENTS)[0]:name::VARCHAR     AS column_name,
  SCHEDULE,
  SCHEDULE_STATUS
FROM TABLE(
  INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
    REF_ENTITY_NAME   => 'zzFACETS_DEV_CLONE.SILVER.MEMBER',
    REF_ENTITY_DOMAIN => 'TABLE'
  )
)
ORDER BY METRIC_NAME;

-- Custom DMF definitions in DQ_POLICIES
SHOW DATA METRIC FUNCTIONS IN SCHEMA DQ_POLICIES;

/* ============================================================================
   STEP 2: View vs expectations.
   ============================================================================ */

SELECT
  METRIC_NAME,
  ARGUMENT_NAMES AS column_name,
  EXPECTATION_EXPRESSION,
  VALUE,
  EXPECTATION_VIOLATED,
  MEASUREMENT_TIME
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS
WHERE TABLE_NAME = 'MEMBER'
  AND TABLE_SCHEMA = 'SILVER'
  AND TABLE_DATABASE = 'ZZFACETS_DEV_CLONE'
  AND EXPECTATION_NAME IN (
    SELECT EXPECTATION_NAME FROM TABLE(INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_EXPECTATIONS(
      REF_ENTITY_NAME => 'zzFACETS_DEV_CLONE.SILVER.MEMBER', REF_ENTITY_DOMAIN => 'TABLE'))
  )
QUALIFY ROW_NUMBER() OVER (PARTITION BY METRIC_NAME, ARGUMENT_NAMES, EXPECTATION_NAME ORDER BY MEASUREMENT_TIME DESC) = 1
ORDER BY EXPECTATION_VIOLATED;