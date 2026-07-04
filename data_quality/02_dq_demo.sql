/*
================================================================================
  CalOptima RFP 26-038 | Topic 9: Data Quality Demo
  File: 02_dq_demo.sql
  Purpose: Live demo walkthrough — run blocks sequentially during presentation.
           Shows: DMF configuration, clean baseline, violation injection,
           expectation status, quarantine, alert check, and historical trends.
  Pre-req:  01_dq_setup.sql must have been run first.
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
SHOW DATA METRIC FUNCTIONS IN TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER;

-- Describe what each custom DMF does
DESCRIBE DATA METRIC FUNCTION zzFACETS_DEV_CLONE.DQ_POLICIES.INVALID_NPI_COUNT;
DESCRIBE DATA METRIC FUNCTION zzFACETS_DEV_CLONE.DQ_POLICIES.MEDICAID_MISSING_BIC_COUNT;

/* ============================================================================
   STEP 2: Clean baseline — all expectations passing
   "Let's confirm our data is clean before we start."
   Run this ~30 seconds after setup to let the first DMF evaluation complete.
   ============================================================================ */

SELECT
  METRIC_NAME,
  ARGUMENT_NAME,
  EXPECTATION_EXPRESSION,
  LATEST_VALUE,
  EXPECTATION_VIOLATED,
  LATEST_MEASUREMENT_TIME
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS
WHERE TABLE_NAME = 'MEMBER'
  AND TABLE_SCHEMA = 'SILVER'
  AND TABLE_DATABASE = 'ZZFACETS_DEV_CLONE'
ORDER BY METRIC_NAME;

-- Quick count: how many rules are currently passing?
SELECT
  COUNT(*) AS total_rules,
  SUM(CASE WHEN EXPECTATION_VIOLATED = FALSE THEN 1 ELSE 0 END) AS passing,
  SUM(CASE WHEN EXPECTATION_VIOLATED = TRUE  THEN 1 ELSE 0 END) AS failing
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS
WHERE TABLE_NAME = 'MEMBER'
  AND TABLE_SCHEMA = 'SILVER'
  AND TABLE_DATABASE = 'ZZFACETS_DEV_CLONE';

/* ============================================================================
   STEP 3: Inject dirty data
   "Now let's simulate what happens when bad data enters the pipeline."
   TRIGGER_ON_CHANGES means DMFs will re-run automatically — wait ~30 seconds
   after calling this before checking violations.
   ============================================================================ */

CALL zzFACETS_DEV_CLONE.SILVER.INJECT_DIRTY_DATA();

-- Show the dirty rows just inserted
SELECT
  MEME_ID,
  MEME_LAST_NAME || ', ' || MEME_FIRST_NAME AS MEMBER_NAME,
  MEME_DOB,
  MEME_SEX,
  MEME_MCTR_TYPE,
  MECD_BIC,
  ACTIVE_PCP_NPI,
  SILVER_LOADED_AT
FROM zzFACETS_DEV_CLONE.SILVER.MEMBER
WHERE MEME_ID >= 9000000
   OR MEME_LAST_NAME LIKE 'DUPLICATE_%'
ORDER BY SILVER_LOADED_AT DESC;

/* ============================================================================
   STEP 4: Expectation violations (run ~30 sec after Step 3)
   "Snowflake detected the violations automatically — no manual query needed."
   ============================================================================ */

SELECT
  METRIC_NAME,
  ARGUMENT_NAME,
  EXPECTATION_EXPRESSION,
  LATEST_VALUE,
  EXPECTATION_VIOLATED,
  LATEST_MEASUREMENT_TIME
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS
WHERE TABLE_NAME = 'MEMBER'
  AND TABLE_SCHEMA = 'SILVER'
  AND TABLE_DATABASE = 'ZZFACETS_DEV_CLONE'
ORDER BY EXPECTATION_VIOLATED DESC, METRIC_NAME;

-- Violations only — the "alert dashboard" view
SELECT
  METRIC_NAME                             AS rule_name,
  ARGUMENT_NAME                           AS column_checked,
  EXPECTATION_EXPRESSION                  AS pass_threshold,
  LATEST_VALUE                            AS current_value,
  LATEST_MEASUREMENT_TIME                 AS detected_at
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS
WHERE TABLE_NAME         = 'MEMBER'
  AND TABLE_SCHEMA       = 'SILVER'
  AND TABLE_DATABASE     = 'ZZFACETS_DEV_CLONE'
  AND EXPECTATION_VIOLATED = TRUE
ORDER BY LATEST_MEASUREMENT_TIME DESC;

/* ============================================================================
   STEP 5: Quarantine pattern — live circuit breaker
   "Invalid records are automatically intercepted and routed to quarantine
    instead of polluting the Silver MEMBER table."
   ============================================================================ */

-- Insert a test record through the staging path (simulates upstream pipeline)
INSERT INTO zzFACETS_DEV_CLONE.SILVER.MEMBER_STAGING (
  MEME_ID, SBSB_ID, MEME_LAST_NAME, MEME_FIRST_NAME, MEME_DOB,
  MEME_SEX, MEME_MCTR_TYPE, MEME_STS, MEMBER_STATUS,
  ACTIVE_PCP_NPI, MECD_BIC, SILVER_LOADED_AT, BRONZE_UPDATED_AT, DUPLICATE_COUNT
) VALUES
-- Good record
(8000001, 8000001, 'GOODRECORD', 'VALID', '1985-04-12',
 'F', 'DSNP', 'A', 'Active',
 '1234567890', NULL, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, 0),
-- Bad record: invalid sex code
(8000002, 8000002, 'BADRECORD', 'INVALID_SEX', '1990-07-30',
 'X', 'COMM', 'A', 'Active',  -- 'X' is not a valid sex code
 '0987654321', NULL, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, 0),
-- Bad record: Medicaid member without BIC
(8000003, 8000003, 'BADRECORD', 'MISSING_BIC', '1978-11-20',
 'M', 'MEDCAID', 'A', 'Active',
 '1122334455', NULL, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, 0);

-- Wait 1 minute for the MEMBER_QUALITY_GATE task to run, then check:

-- Records that PASSED quality gate (promoted to MEMBER)
SELECT 'MEMBER (passed)' AS destination, MEME_ID, MEME_LAST_NAME, MEME_MCTR_TYPE, MEME_SEX
FROM zzFACETS_DEV_CLONE.SILVER.MEMBER
WHERE MEME_ID IN (8000001, 8000002, 8000003);

-- Records that FAILED quality gate (quarantined)
SELECT
  MEME_ID,
  MEME_LAST_NAME || ', ' || MEME_FIRST_NAME AS MEMBER_NAME,
  MEME_MCTR_TYPE,
  MEME_SEX,
  MECD_BIC,
  QUARANTINE_REASON,
  QUARANTINED_AT
FROM zzFACETS_DEV_CLONE.SILVER.MEMBER_QUARANTINE
WHERE MEME_ID IN (8000001, 8000002, 8000003)
ORDER BY QUARANTINED_AT DESC;

-- Quarantine summary by rejection reason
SELECT
  QUARANTINE_REASON,
  COUNT(*)    AS rejected_count,
  MAX(QUARANTINED_AT) AS last_seen
FROM zzFACETS_DEV_CLONE.SILVER.MEMBER_QUARANTINE
GROUP BY QUARANTINE_REASON
ORDER BY rejected_count DESC;

/* ============================================================================
   STEP 6: Alert check
   "If we were in production, an email alert would have already fired.
    Let's check the alert status."
   ============================================================================ */

-- Alert state and last triggered time
SHOW ALERTS LIKE 'MEMBER_DQ_ALERT' IN SCHEMA zzFACETS_DEV_CLONE.SILVER;

-- Alert execution history
SELECT
  NAME,
  STATE,
  CONDITION_QUERY_ID,
  SCHEDULED_TIME,
  COMPLETED_TIME,
  ERROR_MESSAGE
FROM TABLE(INFORMATION_SCHEMA.ALERT_HISTORY(
  SCHEDULED_TIME_RANGE_START => DATEADD('HOUR', -1, CURRENT_TIMESTAMP()),
  RESULT_LIMIT => 10
))
WHERE NAME = 'MEMBER_DQ_ALERT'
ORDER BY SCHEDULED_TIME DESC;

/* ============================================================================
   STEP 7: Historical trends
   "Every evaluation run is stored — here's the trend over time for each rule."
   Use SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS() for raw metric history.
   ============================================================================ */

-- Last 50 measurement results across all DMFs on MEMBER
SELECT
  MEASUREMENT_TIME,
  METRIC_NAME,
  ARGUMENT_NAME,
  VALUE,
  -- Annotate clean vs dirty periods
  CASE
    WHEN VALUE = 0 THEN 'CLEAN'
    WHEN VALUE > 0 THEN 'VIOLATION'
    ELSE 'N/A'
  END AS quality_state
FROM TABLE(SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS(
  REF_ENTITY_NAME   => 'zzFACETS_DEV_CLONE.SILVER.MEMBER',
  REF_ENTITY_DOMAIN => 'TABLE'
))
ORDER BY MEASUREMENT_TIME DESC
LIMIT 50;

-- Trend: null count violations over time (completeness)
SELECT
  MEASUREMENT_TIME,
  METRIC_NAME,
  ARGUMENT_NAME,
  VALUE AS metric_value
FROM TABLE(SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS(
  REF_ENTITY_NAME   => 'zzFACETS_DEV_CLONE.SILVER.MEMBER',
  REF_ENTITY_DOMAIN => 'TABLE'
))
WHERE METRIC_NAME IN ('NULL_COUNT', 'DUPLICATE_COUNT', 'ACCEPTED_VALUES',
                      'MEDICAID_MISSING_BIC_COUNT', 'INVALID_NPI_COUNT')
ORDER BY MEASUREMENT_TIME DESC, METRIC_NAME
LIMIT 100;

-- Row count trend (volume monitoring)
SELECT
  MEASUREMENT_TIME,
  VALUE AS total_member_count
FROM TABLE(SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS(
  REF_ENTITY_NAME   => 'zzFACETS_DEV_CLONE.SILVER.MEMBER',
  REF_ENTITY_DOMAIN => 'TABLE'
))
WHERE METRIC_NAME = 'ROW_COUNT'
ORDER BY MEASUREMENT_TIME;

/* ============================================================================
   STEP 8: Clean up violations
   "Let's restore the clean state and confirm all expectations pass again."
   ============================================================================ */

CALL zzFACETS_DEV_CLONE.SILVER.CLEAN_DIRTY_DATA();

-- Wait ~30 seconds for TRIGGER_ON_CHANGES to fire, then re-run Step 2 to
-- confirm all expectations return to EXPECTATION_VIOLATED = FALSE.

/* ============================================================================
   APPENDIX: Useful queries for Snowsight dashboard tiles
   These queries power the data quality monitoring dashboard.
   ============================================================================ */

-- Dashboard tile 1: DQ health score (% rules passing)
SELECT
  ROUND(
    100.0 * SUM(CASE WHEN EXPECTATION_VIOLATED = FALSE THEN 1 ELSE 0 END)
          / COUNT(*),
    1
  ) AS dq_health_score_pct,
  COUNT(*) AS total_rules,
  SUM(CASE WHEN EXPECTATION_VIOLATED = TRUE THEN 1 ELSE 0 END) AS active_violations
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS
WHERE TABLE_NAME      = 'MEMBER'
  AND TABLE_SCHEMA    = 'SILVER'
  AND TABLE_DATABASE  = 'ZZFACETS_DEV_CLONE';

-- Dashboard tile 2: Active violations with severity mapping
SELECT
  METRIC_NAME                AS rule,
  ARGUMENT_NAME              AS column_name,
  LATEST_VALUE               AS violation_count,
  LATEST_MEASUREMENT_TIME    AS last_checked,
  CASE
    WHEN METRIC_NAME IN ('DUPLICATE_COUNT', 'MEDICAID_MISSING_BIC_COUNT') THEN 'HIGH'
    WHEN METRIC_NAME IN ('NULL_COUNT', 'INVALID_NPI_COUNT')               THEN 'MEDIUM'
    ELSE 'LOW'
  END AS severity
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS
WHERE TABLE_NAME        = 'MEMBER'
  AND TABLE_SCHEMA      = 'SILVER'
  AND TABLE_DATABASE    = 'ZZFACETS_DEV_CLONE'
  AND EXPECTATION_VIOLATED = TRUE
ORDER BY
  FIELD(severity, 'HIGH', 'MEDIUM', 'LOW'),
  LATEST_VALUE DESC;

-- Dashboard tile 3: Member count over time (volume trend)
SELECT
  DATE_TRUNC('HOUR', MEASUREMENT_TIME) AS measurement_hour,
  AVG(VALUE)                           AS avg_member_count
FROM TABLE(SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS(
  REF_ENTITY_NAME   => 'zzFACETS_DEV_CLONE.SILVER.MEMBER',
  REF_ENTITY_DOMAIN => 'TABLE'
))
WHERE METRIC_NAME = 'ROW_COUNT'
GROUP BY 1
ORDER BY 1;

-- Dashboard tile 4: Quarantine breakdown
SELECT
  QUARANTINE_REASON,
  COUNT(*) AS total_quarantined,
  MIN(QUARANTINED_AT) AS first_seen,
  MAX(QUARANTINED_AT) AS last_seen
FROM zzFACETS_DEV_CLONE.SILVER.MEMBER_QUARANTINE
GROUP BY QUARANTINE_REASON
ORDER BY total_quarantined DESC;
