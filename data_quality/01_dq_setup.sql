/*
================================================================================
  CalOptima RFP 26-038 | Topic 9: Data Quality Demo
  File: 01_dq_setup.sql
  Purpose: Complete teardown and rebuild of the zzFACETS_DEV_CLONE data quality
           demo environment. Safe to re-run at any time — drops the clone first.
  Scope:   zzFACETS_DEV_CLONE only. No changes to any other database.
================================================================================
*/

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WH_XS;

/* ============================================================================
   TEARDOWN — safe to re-run
   ============================================================================ */

DROP DATABASE IF EXISTS zzFACETS_DEV_CLONE;

/* ============================================================================
   SECTION A: Clone FACETS_DEV and create DQ_POLICIES schema
   ============================================================================ */

CREATE DATABASE zzFACETS_DEV_CLONE
  CLONE FACETS_DEV
  COMMENT = 'Data Quality demo clone — CalOptima RFP 26-038 Topic 9';

CREATE SCHEMA zzFACETS_DEV_CLONE.DQ_POLICIES
  COMMENT = 'Custom data metric functions for healthcare data quality';

/* ============================================================================
   SECTION B: Email notification integration
   Note: MY_EMAIL_INTEGRATION already exists in this account (created 2024-10-10).
   The CREATE OR REPLACE below is idempotent — recreates with the same settings
   so this script remains self-contained and can rebuild from scratch.
   ============================================================================ */

CREATE OR REPLACE NOTIFICATION INTEGRATION MY_EMAIL_INTEGRATION
  TYPE = EMAIL
  ENABLED = TRUE
  COMMENT = 'Email integration for data quality alerts — CalOptima demo';

/* ============================================================================
   SECTION C: Privileges
   ============================================================================ */

-- Allow querying DATA_QUALITY_MONITORING_RESULTS and EXPECTATION_STATUS
GRANT DATABASE ROLE SNOWFLAKE.DATA_METRIC_USER TO ROLE ACCOUNTADMIN;

-- Allow DMFs to execute on demand (required for custom DMFs)
GRANT EXECUTE DATA METRIC FUNCTION ON ACCOUNT TO ROLE ACCOUNTADMIN;

-- Allow ALTER TABLE to add/remove DMF associations and set schedules
GRANT MANAGE DATA QUALITY ON ACCOUNT TO ROLE ACCOUNTADMIN;

/* ============================================================================
   SECTION D: Custom DMFs (healthcare-specific validations)
   ============================================================================ */

USE SCHEMA zzFACETS_DEV_CLONE.DQ_POLICIES;

-- NPI (National Provider Identifier) format check: must be exactly 10 digits
CREATE OR REPLACE DATA METRIC FUNCTION invalid_npi_count(
  arg_t TABLE(npi_col VARCHAR)
)
RETURNS NUMBER
COMMENT = 'Count of NPI values that are not exactly 10 numeric digits'
AS
$$
  SELECT COUNT(*)
  FROM arg_t
  WHERE npi_col IS NOT NULL
    AND NOT REGEXP_LIKE(npi_col, '^[0-9]{10}$')
$$;

-- Medicaid members missing BIC: cross-column validation
CREATE OR REPLACE DATA METRIC FUNCTION medicaid_missing_bic_count(
  arg_t TABLE(mctr_type VARCHAR, bic VARCHAR)
)
RETURNS NUMBER
COMMENT = 'Count of Medicaid members (MEME_MCTR_TYPE=MEDCAID) missing a BIC'
AS
$$
  SELECT COUNT(*)
  FROM arg_t
  WHERE mctr_type = 'MEDCAID'
    AND bic IS NULL
$$;

/* ============================================================================
   SECTION E: Per-table monitoring schedule (TRIGGER_ON_CHANGES)
   DMFs re-run automatically whenever rows are inserted, updated, or deleted.
   Violations appear ~30 seconds after data changes — makes demo reactive.
   ============================================================================ */

ALTER TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER
  SET DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';

/* ============================================================================
   SECTION F: Attach DMFs to SILVER.MEMBER
   9 DMF associations covering volume, freshness, completeness, validity,
   and custom healthcare rules.

   IMPORTANT SYNTAX NOTES (verified against Snowflake docs):
   - ACCEPTED_VALUES: lambda goes inside ON clause: ON (col, col -> condition)
   - No WITH / ALLOWED keyword exists for ACCEPTED_VALUES
   - FRESHNESS: requires TIMESTAMP_LTZ or TIMESTAMP_TZ — NOT TIMESTAMP_NTZ
     Use SILVER_LOADED_AT (TIMESTAMP_LTZ), not BRONZE_UPDATED_AT (TIMESTAMP_NTZ)
   ============================================================================ */

USE SCHEMA zzFACETS_DEV_CLONE.SILVER;

-- 1. Volume: total row count
ALTER TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ();

-- 2. Freshness: seconds since newest SILVER_LOADED_AT value
ALTER TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS
  ON (SILVER_LOADED_AT);

-- 3. Completeness: null BIC values (critical for Medicaid compliance)
ALTER TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT
  ON (MECD_BIC);

-- 4. Completeness: null date of birth
ALTER TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT
  ON (MEME_DOB);

-- 5. Uniqueness: duplicate member IDs
ALTER TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.DUPLICATE_COUNT
  ON (MEME_ID);

-- 6. Validity: plan type must be COMM, DSNP, or MEDCAID
--    Lambda syntax: ON (column, column -> expression)
ALTER TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES
  ON (MEME_MCTR_TYPE, MEME_MCTR_TYPE -> MEME_MCTR_TYPE IN ('COMM', 'DSNP', 'MEDCAID'));

-- 7. Validity: sex code must be M, F, or U
ALTER TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES
  ON (MEME_SEX, MEME_SEX -> MEME_SEX IN ('M', 'F', 'U'));

-- 8. Custom: invalid NPI formats on the PCP NPI column
ALTER TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER
  ADD DATA METRIC FUNCTION zzFACETS_DEV_CLONE.DQ_POLICIES.INVALID_NPI_COUNT
  ON (ACTIVE_PCP_NPI);

-- 9. Custom: Medicaid members missing BIC (cross-column)
ALTER TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER
  ADD DATA METRIC FUNCTION zzFACETS_DEV_CLONE.DQ_POLICIES.MEDICAID_MISSING_BIC_COUNT
  ON (MEME_MCTR_TYPE, MECD_BIC);

/* ============================================================================
   SECTION G: Expectations (pass/fail thresholds per DMF)
   Syntax: MODIFY DATA METRIC FUNCTION ... ADD EXPECTATION name (expression)
   Expectation violations visible in:
     SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS
   ============================================================================ */

-- Volume: row count > 0
ALTER TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ()
  ADD EXPECTATION member_table_has_rows (VALUE > 0);

-- Freshness: data loaded within the last 24 hours (86400 seconds)
ALTER TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS ON (SILVER_LOADED_AT)
  ADD EXPECTATION data_fresh_within_24h (VALUE < 86400);

-- Completeness: zero null BIC values
ALTER TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (MECD_BIC)
  ADD EXPECTATION no_null_bic (VALUE = 0);

-- Completeness: zero null DOB values
ALTER TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (MEME_DOB)
  ADD EXPECTATION no_null_dob (VALUE = 0);

-- Uniqueness: zero duplicate member IDs
ALTER TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.DUPLICATE_COUNT ON (MEME_ID)
  ADD EXPECTATION no_duplicate_member_ids (VALUE = 0);

-- Validity: zero invalid plan types
ALTER TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES
  ON (MEME_MCTR_TYPE, MEME_MCTR_TYPE -> MEME_MCTR_TYPE IN ('COMM', 'DSNP', 'MEDCAID'))
  ADD EXPECTATION all_valid_plan_types (VALUE = 0);

-- Validity: zero invalid sex codes
ALTER TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES
  ON (MEME_SEX, MEME_SEX -> MEME_SEX IN ('M', 'F', 'U'))
  ADD EXPECTATION all_valid_sex_codes (VALUE = 0);

-- Custom: zero invalid NPI formats
ALTER TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION zzFACETS_DEV_CLONE.DQ_POLICIES.INVALID_NPI_COUNT
  ON (ACTIVE_PCP_NPI)
  ADD EXPECTATION all_valid_npi_formats (VALUE = 0);

-- Custom: zero Medicaid members missing BIC
ALTER TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION zzFACETS_DEV_CLONE.DQ_POLICIES.MEDICAID_MISSING_BIC_COUNT
  ON (MEME_MCTR_TYPE, MECD_BIC)
  ADD EXPECTATION no_medicaid_missing_bic (VALUE = 0);

/* ============================================================================
   SECTION H: Quarantine pattern (circuit breaker)
   New rows staged in MEMBER_STAGING are evaluated by MEMBER_QUALITY_GATE task.
   Valid records → SILVER.MEMBER, invalid → MEMBER_QUARANTINE.
   ============================================================================ */

-- Staging table for incoming data
CREATE OR REPLACE TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER_STAGING
  LIKE zzFACETS_DEV_CLONE.SILVER.MEMBER
  COMMENT = 'Staging area — rows pending quality gate evaluation';

-- Quarantine table: same shape as MEMBER plus rejection metadata
CREATE OR REPLACE TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER_QUARANTINE (
  MEME_ID              NUMBER,
  SBSB_ID              NUMBER,
  MEME_LAST_NAME       TEXT,
  MEME_FIRST_NAME      TEXT,
  MEME_DOB             DATE,
  RELATIONSHIP_DESC    TEXT,
  MEME_REL_CD          TEXT,
  SEX_DESC             TEXT,
  MEME_SEX             TEXT,
  MEMBER_STATUS        TEXT,
  MEME_STS             TEXT,
  MEME_MCTR_TYPE       TEXT,
  SUBSCRIBER_LAST_NAME  TEXT,
  SUBSCRIBER_FIRST_NAME TEXT,
  SUBSCRIBER_DOB       DATE,
  SUBSCRIBER_STATUS    TEXT,
  SUBSCRIBER_MCTR_TYPE TEXT,
  ACTIVE_PCP_PRPR_ID   NUMBER,
  ACTIVE_PCP_NAME      TEXT,
  ACTIVE_PCP_NPI       TEXT,
  PCP_EFF_DT           DATE,
  ACTIVE_PCP_TYPE      TEXT,
  MECD_AID_CD          TEXT,
  MECD_BIC             TEXT,
  MEDICAID_EFF_DT      DATE,
  MEDICAID_TERM_DT     DATE,
  DUPLICATE_COUNT      NUMBER,
  BRONZE_UPDATED_AT    TIMESTAMP_NTZ,
  SILVER_LOADED_AT     TIMESTAMP_LTZ,
  -- Quarantine metadata
  QUARANTINE_REASON    TEXT,
  QUARANTINED_AT       TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Records that failed data quality rules — routed here by quality gate task';

-- Append-only stream: fires when rows are inserted to MEMBER_STAGING
CREATE OR REPLACE STREAM zzFACETS_DEV_CLONE.SILVER.MEMBER_STAGING_STREAM
  ON TABLE zzFACETS_DEV_CLONE.SILVER.MEMBER_STAGING
  APPEND_ONLY = TRUE
  COMMENT = 'Captures new rows inserted to MEMBER_STAGING for quality gate evaluation';

-- Routing procedure: called by the task
-- Multi-statement logic is in a procedure; the task just calls CALL.
CREATE OR REPLACE PROCEDURE zzFACETS_DEV_CLONE.SILVER.MEMBER_ROUTE_STAGED()
  RETURNS VARCHAR
  LANGUAGE SQL
  COMMENT = 'Routes staged members: valid to SILVER.MEMBER, invalid to MEMBER_QUARANTINE'
AS
$$
BEGIN
  INSERT INTO zzFACETS_DEV_CLONE.SILVER.MEMBER (
    MEME_ID, SBSB_ID, MEME_LAST_NAME, MEME_FIRST_NAME, MEME_DOB,
    RELATIONSHIP_DESC, MEME_REL_CD, SEX_DESC, MEME_SEX, MEMBER_STATUS,
    MEME_STS, MEME_MCTR_TYPE, SUBSCRIBER_LAST_NAME, SUBSCRIBER_FIRST_NAME,
    SUBSCRIBER_DOB, SUBSCRIBER_STATUS, SUBSCRIBER_MCTR_TYPE,
    ACTIVE_PCP_PRPR_ID, ACTIVE_PCP_NAME, ACTIVE_PCP_NPI, PCP_EFF_DT,
    ACTIVE_PCP_TYPE, MECD_AID_CD, MECD_BIC, MEDICAID_EFF_DT, MEDICAID_TERM_DT,
    DUPLICATE_COUNT, BRONZE_UPDATED_AT, SILVER_LOADED_AT
  )
  SELECT
    MEME_ID, SBSB_ID, MEME_LAST_NAME, MEME_FIRST_NAME, MEME_DOB,
    RELATIONSHIP_DESC, MEME_REL_CD, SEX_DESC, MEME_SEX, MEMBER_STATUS,
    MEME_STS, MEME_MCTR_TYPE, SUBSCRIBER_LAST_NAME, SUBSCRIBER_FIRST_NAME,
    SUBSCRIBER_DOB, SUBSCRIBER_STATUS, SUBSCRIBER_MCTR_TYPE,
    ACTIVE_PCP_PRPR_ID, ACTIVE_PCP_NAME, ACTIVE_PCP_NPI, PCP_EFF_DT,
    ACTIVE_PCP_TYPE, MECD_AID_CD, MECD_BIC, MEDICAID_EFF_DT, MEDICAID_TERM_DT,
    DUPLICATE_COUNT, BRONZE_UPDATED_AT, SILVER_LOADED_AT
  FROM zzFACETS_DEV_CLONE.SILVER.MEMBER_STAGING_STREAM
  WHERE METADATA$ACTION = 'INSERT'
    AND MEME_SEX IN ('M', 'F', 'U')
    AND MEME_MCTR_TYPE IN ('COMM', 'DSNP', 'MEDCAID')
    AND MEME_DOB IS NOT NULL
    AND (ACTIVE_PCP_NPI IS NULL OR REGEXP_LIKE(ACTIVE_PCP_NPI, '^[0-9]{10}$'))
    AND NOT (MEME_MCTR_TYPE = 'MEDCAID' AND MECD_BIC IS NULL);

  INSERT INTO zzFACETS_DEV_CLONE.SILVER.MEMBER_QUARANTINE (
    MEME_ID, SBSB_ID, MEME_LAST_NAME, MEME_FIRST_NAME, MEME_DOB,
    RELATIONSHIP_DESC, MEME_REL_CD, SEX_DESC, MEME_SEX, MEMBER_STATUS,
    MEME_STS, MEME_MCTR_TYPE, SUBSCRIBER_LAST_NAME, SUBSCRIBER_FIRST_NAME,
    SUBSCRIBER_DOB, SUBSCRIBER_STATUS, SUBSCRIBER_MCTR_TYPE,
    ACTIVE_PCP_PRPR_ID, ACTIVE_PCP_NAME, ACTIVE_PCP_NPI, PCP_EFF_DT,
    ACTIVE_PCP_TYPE, MECD_AID_CD, MECD_BIC, MEDICAID_EFF_DT, MEDICAID_TERM_DT,
    DUPLICATE_COUNT, BRONZE_UPDATED_AT, SILVER_LOADED_AT, QUARANTINE_REASON
  )
  SELECT
    MEME_ID, SBSB_ID, MEME_LAST_NAME, MEME_FIRST_NAME, MEME_DOB,
    RELATIONSHIP_DESC, MEME_REL_CD, SEX_DESC, MEME_SEX, MEMBER_STATUS,
    MEME_STS, MEME_MCTR_TYPE, SUBSCRIBER_LAST_NAME, SUBSCRIBER_FIRST_NAME,
    SUBSCRIBER_DOB, SUBSCRIBER_STATUS, SUBSCRIBER_MCTR_TYPE,
    ACTIVE_PCP_PRPR_ID, ACTIVE_PCP_NAME, ACTIVE_PCP_NPI, PCP_EFF_DT,
    ACTIVE_PCP_TYPE, MECD_AID_CD, MECD_BIC, MEDICAID_EFF_DT, MEDICAID_TERM_DT,
    DUPLICATE_COUNT, BRONZE_UPDATED_AT, SILVER_LOADED_AT,
    CASE
      WHEN MEME_SEX NOT IN ('M', 'F', 'U')                   THEN 'INVALID_SEX_CODE'
      WHEN MEME_MCTR_TYPE NOT IN ('COMM', 'DSNP', 'MEDCAID') THEN 'INVALID_PLAN_TYPE'
      WHEN MEME_DOB IS NULL                                   THEN 'MISSING_DATE_OF_BIRTH'
      WHEN ACTIVE_PCP_NPI IS NOT NULL
        AND NOT REGEXP_LIKE(ACTIVE_PCP_NPI, '^[0-9]{10}$')   THEN 'INVALID_NPI_FORMAT'
      WHEN MEME_MCTR_TYPE = 'MEDCAID' AND MECD_BIC IS NULL   THEN 'MEDICAID_MISSING_BIC'
      ELSE 'MULTIPLE_VIOLATIONS'
    END
  FROM zzFACETS_DEV_CLONE.SILVER.MEMBER_STAGING_STREAM
  WHERE METADATA$ACTION = 'INSERT'
    AND (
      MEME_SEX NOT IN ('M', 'F', 'U')
      OR MEME_MCTR_TYPE NOT IN ('COMM', 'DSNP', 'MEDCAID')
      OR MEME_DOB IS NULL
      OR (ACTIVE_PCP_NPI IS NOT NULL AND NOT REGEXP_LIKE(ACTIVE_PCP_NPI, '^[0-9]{10}$'))
      OR (MEME_MCTR_TYPE = 'MEDCAID' AND MECD_BIC IS NULL)
    );

  DELETE FROM zzFACETS_DEV_CLONE.SILVER.MEMBER_STAGING;
  RETURN 'Routing complete';
END;
$$;

-- Quality gate task: COMMENT must precede WHEN clause
CREATE OR REPLACE TASK zzFACETS_DEV_CLONE.SILVER.MEMBER_QUALITY_GATE
  WAREHOUSE = WH_XS
  SCHEDULE  = '1 MINUTE'
  COMMENT   = 'Routes staged member rows: valid to SILVER.MEMBER, invalid to MEMBER_QUARANTINE'
  WHEN SYSTEM$STREAM_HAS_DATA('zzFACETS_DEV_CLONE.SILVER.MEMBER_STAGING_STREAM')
AS
  CALL zzFACETS_DEV_CLONE.SILVER.MEMBER_ROUTE_STAGED();

ALTER TASK zzFACETS_DEV_CLONE.SILVER.MEMBER_QUALITY_GATE RESUME;

/* ============================================================================
   SECTION I: Data quality alert
   Fires every 5 minutes when new DMF results exist (TRIGGER_ON_CHANGES means
   results appear shortly after data changes).
   Sends email to t.jones@snowflake.com via MY_EMAIL_INTEGRATION.
   ============================================================================ */

CREATE OR REPLACE ALERT zzFACETS_DEV_CLONE.SILVER.MEMBER_DQ_ALERT
  WAREHOUSE = WH_XS
  SCHEDULE  = '5 MINUTES'
  IF (
    EXISTS (
      SELECT 1
      FROM TABLE(SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS(
        REF_ENTITY_NAME    => 'zzFACETS_DEV_CLONE.SILVER.MEMBER',
        REF_ENTITY_DOMAIN  => 'TABLE'
      ))
      WHERE MEASUREMENT_TIME >= DATEADD('MINUTE', -10, CURRENT_TIMESTAMP())
    )
  )
  THEN
    CALL SYSTEM$SEND_EMAIL(
      'MY_EMAIL_INTEGRATION',
      't.jones@snowflake.com',
      'CalOptima DQ Alert: Data Quality Violations on SILVER.MEMBER',
      'One or more data quality expectations have been violated on zzFACETS_DEV_CLONE.SILVER.MEMBER.\n\nReview violations:\n  SELECT * FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS\n  WHERE TABLE_NAME = ''MEMBER''\n    AND TABLE_SCHEMA = ''SILVER''\n    AND EXPECTATION_VIOLATED = TRUE;\n\nGenerated by CalOptima RFP 26-038 Topic 9 demo.'
    );

ALTER ALERT zzFACETS_DEV_CLONE.SILVER.MEMBER_DQ_ALERT RESUME;

/* ============================================================================
   SECTION J: Demo helper stored procedures
   ============================================================================ */

-- inject_dirty_data(): inserts rows with known violations to trigger DMF alerts
CREATE OR REPLACE PROCEDURE zzFACETS_DEV_CLONE.SILVER.INJECT_DIRTY_DATA()
  RETURNS VARCHAR
  LANGUAGE SQL
  COMMENT = 'Inserts dirty member records to demonstrate data quality violations'
AS
$$
BEGIN
  -- Violation 1: Duplicate MEME_ID — copy existing member with same ID
  INSERT INTO zzFACETS_DEV_CLONE.SILVER.MEMBER (
    MEME_ID, SBSB_ID, MEME_LAST_NAME, MEME_FIRST_NAME, MEME_DOB,
    MEME_SEX, MEME_MCTR_TYPE, MEME_STS, MEMBER_STATUS,
    ACTIVE_PCP_NPI, MECD_BIC, SILVER_LOADED_AT, BRONZE_UPDATED_AT, DUPLICATE_COUNT
  )
  SELECT TOP 1
    MEME_ID, SBSB_ID + 99999, 'DUPLICATE_' || MEME_LAST_NAME,
    MEME_FIRST_NAME, MEME_DOB, MEME_SEX, MEME_MCTR_TYPE,
    MEME_STS, MEMBER_STATUS, ACTIVE_PCP_NPI, MECD_BIC,
    CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, 0
  FROM zzFACETS_DEV_CLONE.SILVER.MEMBER
  WHERE MEME_ID IS NOT NULL;

  -- Violation 2: Invalid plan type (not in COMM / DSNP / MEDCAID)
  INSERT INTO zzFACETS_DEV_CLONE.SILVER.MEMBER (
    MEME_ID, SBSB_ID, MEME_LAST_NAME, MEME_FIRST_NAME, MEME_DOB,
    MEME_SEX, MEME_MCTR_TYPE, MEME_STS, MEMBER_STATUS,
    ACTIVE_PCP_NPI, MECD_BIC, SILVER_LOADED_AT, BRONZE_UPDATED_AT, DUPLICATE_COUNT
  ) VALUES (
    9000001, 9000001, 'DIRTY', 'PLAN_TYPE', '1980-01-01',
    'M', 'UNKNOWN_PLAN', 'A', 'Active',
    '1234567890', NULL, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, 0
  );

  -- Violation 3: Medicaid member with NULL BIC (custom DMF violation)
  INSERT INTO zzFACETS_DEV_CLONE.SILVER.MEMBER (
    MEME_ID, SBSB_ID, MEME_LAST_NAME, MEME_FIRST_NAME, MEME_DOB,
    MEME_SEX, MEME_MCTR_TYPE, MEME_STS, MEMBER_STATUS,
    ACTIVE_PCP_NPI, MECD_BIC, SILVER_LOADED_AT, BRONZE_UPDATED_AT, DUPLICATE_COUNT
  ) VALUES (
    9000002, 9000002, 'DIRTY', 'MISSING_BIC', '1975-06-15',
    'F', 'MEDCAID', 'A', 'Active',
    '1234567890', NULL, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, 0
  );

  -- Violation 4: Invalid NPI format (not 10 numeric digits)
  INSERT INTO zzFACETS_DEV_CLONE.SILVER.MEMBER (
    MEME_ID, SBSB_ID, MEME_LAST_NAME, MEME_FIRST_NAME, MEME_DOB,
    MEME_SEX, MEME_MCTR_TYPE, MEME_STS, MEMBER_STATUS,
    ACTIVE_PCP_NPI, MECD_BIC, SILVER_LOADED_AT, BRONZE_UPDATED_AT, DUPLICATE_COUNT
  ) VALUES (
    9000003, 9000003, 'DIRTY', 'BAD_NPI', '1990-03-20',
    'M', 'COMM', 'A', 'Active',
    '123456X', NULL, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, 0
  );

  -- Violation 5: Missing date of birth
  INSERT INTO zzFACETS_DEV_CLONE.SILVER.MEMBER (
    MEME_ID, SBSB_ID, MEME_LAST_NAME, MEME_FIRST_NAME, MEME_DOB,
    MEME_SEX, MEME_MCTR_TYPE, MEME_STS, MEMBER_STATUS,
    ACTIVE_PCP_NPI, MECD_BIC, SILVER_LOADED_AT, BRONZE_UPDATED_AT, DUPLICATE_COUNT
  ) VALUES (
    9000004, 9000004, 'DIRTY', 'NO_DOB', NULL,
    'F', 'DSNP', 'A', 'Active',
    '9876543210', NULL, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, 0
  );

  RETURN 'Injected 5 dirty records: duplicate ID, invalid plan type, missing BIC, bad NPI, missing DOB. DMFs will re-evaluate within ~30 seconds.';
END;
$$;

-- clean_dirty_data(): removes all injected violation rows
CREATE OR REPLACE PROCEDURE zzFACETS_DEV_CLONE.SILVER.CLEAN_DIRTY_DATA()
  RETURNS VARCHAR
  LANGUAGE SQL
  COMMENT = 'Removes dirty records injected by INJECT_DIRTY_DATA — restores clean baseline'
AS
$$
BEGIN
  DELETE FROM zzFACETS_DEV_CLONE.SILVER.MEMBER
  WHERE MEME_ID IN (9000001, 9000002, 9000003, 9000004)
     OR MEME_LAST_NAME LIKE 'DUPLICATE_%';

  DELETE FROM zzFACETS_DEV_CLONE.SILVER.MEMBER_QUARANTINE
  WHERE MEME_ID IN (9000001, 9000002, 9000003, 9000004)
     OR MEME_LAST_NAME LIKE 'DIRTY%';

  RETURN 'Dirty records removed. DMFs will re-evaluate within ~30 seconds — all expectations should clear.';
END;
$$;

/* ============================================================================
   DONE
   ============================================================================ */

SELECT
  'zzFACETS_DEV_CLONE created and fully configured.' AS status,
  'Run CALL zzFACETS_DEV_CLONE.SILVER.INJECT_DIRTY_DATA() to start the demo.' AS next_step;
