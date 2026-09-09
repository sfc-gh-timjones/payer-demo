/*

ONE-TIME SETUP. 
NO NEED TO RUN AGAIN DAY OF DEMO. 
NO NEED TO RUN OVER AND OVER AGAIN UNLESS CHANGES.

================================================================================
  Payer RFP 26-038 | Topic 9: Data Quality Demo
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

CREATE DATABASE IF NOT EXISTS zzFACETS_DEV_CLONE
  CLONE FACETS_DEV
  COMMENT = 'Data Quality demo clone — Payer RFP 26-038 Topic 9';

CREATE SCHEMA IF NOT EXISTS zzFACETS_DEV_CLONE.DQ_POLICIES
  COMMENT = 'Custom data metric functions for healthcare data quality';

USE DATABASE zzFACETS_DEV_CLONE;

/* ============================================================================
   SECTION B: Email notification integration
   Note: MY_EMAIL_INTEGRATION already exists in this account (created 2024-10-10).
   The CREATE OR REPLACE below is idempotent — recreates with the same settings
   so this script remains self-contained and can rebuild from scratch.
   ============================================================================ */

CREATE OR REPLACE NOTIFICATION INTEGRATION MY_EMAIL_INTEGRATION
  TYPE = EMAIL
  ENABLED = TRUE
  COMMENT = 'Email integration to t.jones@snowflake.com';

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

USE SCHEMA DQ_POLICIES;

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

CREATE OR REPLACE DATA METRIC FUNCTION median_birth_year(
  arg_t TABLE(dob DATE)
)
RETURNS NUMBER
COMMENT = 'Median birth year of members — proxy for population age distribution'
AS
$$
  SELECT MEDIAN(YEAR(dob))
  FROM arg_t
$$;

/* ============================================================================
   SECTION E: Per-table monitoring schedule (TRIGGER_ON_CHANGES)
   DMFs re-run automatically whenever rows are inserted, updated, or deleted.
   Violations appear ~30 seconds after data changes — makes demo reactive.
   ============================================================================ */

ALTER TABLE SILVER.MEMBER
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

USE SCHEMA SILVER;

-- 1. Volume: total row count
ALTER TABLE SILVER.MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ();

-- 2. Freshness: seconds since newest SILVER_LOADED_AT value
ALTER TABLE SILVER.MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS
  ON (SILVER_LOADED_AT);

-- 3. Completeness: null BIC values (critical for Medicaid compliance)
ALTER TABLE SILVER.MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT
  ON (MECD_BIC);

-- 4. Completeness: null date of birth
ALTER TABLE SILVER.MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT
  ON (MEME_DOB);

-- 5. Uniqueness: duplicate member IDs
ALTER TABLE SILVER.MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.DUPLICATE_COUNT
  ON (MEME_ID);

-- 6. Validity: plan type must be COMM, DSNP, or MEDCAID
--    Lambda syntax: ON (column, column -> expression)
ALTER TABLE SILVER.MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES
  ON (MEME_MCTR_TYPE, MEME_MCTR_TYPE -> MEME_MCTR_TYPE IN ('COMM', 'DSNP', 'MEDCAID'));

-- 7. Validity: sex code must be M, F, or U
ALTER TABLE SILVER.MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES
  ON (MEME_SEX, MEME_SEX -> MEME_SEX IN ('M', 'F', 'U'));

-- 8. Custom: invalid NPI formats on the PCP NPI column
ALTER TABLE SILVER.MEMBER
  ADD DATA METRIC FUNCTION DQ_POLICIES.INVALID_NPI_COUNT
  ON (ACTIVE_PCP_NPI);

-- 9. Custom: Medicaid members missing BIC (cross-column)
ALTER TABLE SILVER.MEMBER
  ADD DATA METRIC FUNCTION DQ_POLICIES.MEDICAID_MISSING_BIC_COUNT
  ON (MEME_MCTR_TYPE, MECD_BIC);

-- 10. Schema: schema change count (detects column add/drop/rename/type changes — ties into Openflow schema drift demo)
ALTER TABLE SILVER.MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.SCHEMA_CHANGE_COUNT ON ();

-- 11. Statistics: median member birth year (proxy for population age distribution)
ALTER TABLE SILVER.MEMBER
  ADD DATA METRIC FUNCTION DQ_POLICIES.MEDIAN_BIRTH_YEAR ON (MEME_DOB);

/* ============================================================================
   SECTION G: Expectations (pass/fail thresholds per DMF)
   Syntax: MODIFY DATA METRIC FUNCTION ... ADD EXPECTATION name (expression)
   Expectation violations visible in:
     SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS
   ============================================================================ */

-- Volume: row count > 0
ALTER TABLE SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ()
  ADD EXPECTATION member_table_has_rows (VALUE > 0);

-- Freshness: data loaded within the last 15 minutes (900 seconds)
ALTER TABLE SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS ON (SILVER_LOADED_AT)
  ADD EXPECTATION data_fresh_within_15m (VALUE < 900);

-- Completeness: zero null BIC values
ALTER TABLE SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (MECD_BIC)
  ADD EXPECTATION no_null_bic (VALUE = 0);

-- Completeness: zero null DOB values
ALTER TABLE SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (MEME_DOB)
  ADD EXPECTATION no_null_dob (VALUE = 0);

-- Uniqueness: zero duplicate member IDs
ALTER TABLE SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.DUPLICATE_COUNT ON (MEME_ID)
  ADD EXPECTATION no_duplicate_member_ids (VALUE = 0);

-- Validity: zero invalid plan types
ALTER TABLE SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES
  ON (MEME_MCTR_TYPE, MEME_MCTR_TYPE -> MEME_MCTR_TYPE IN ('COMM', 'DSNP', 'MEDCAID'))
  ADD EXPECTATION all_valid_plan_types (VALUE = 0);

-- Validity: zero invalid sex codes
ALTER TABLE SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES
  ON (MEME_SEX, MEME_SEX -> MEME_SEX IN ('M', 'F', 'U'))
  ADD EXPECTATION all_valid_sex_codes (VALUE = 0);

-- Custom: zero invalid NPI formats
ALTER TABLE SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION DQ_POLICIES.INVALID_NPI_COUNT
  ON (ACTIVE_PCP_NPI)
  ADD EXPECTATION all_valid_npi_formats (VALUE = 0);

-- Custom: zero Medicaid members missing BIC
ALTER TABLE SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION DQ_POLICIES.MEDICAID_MISSING_BIC_COUNT
  ON (MEME_MCTR_TYPE, MECD_BIC)
  ADD EXPECTATION no_medicaid_missing_bic (VALUE = 0);

-- Schema: zero unexpected schema changes (flags Openflow column drift)
ALTER TABLE SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.SCHEMA_CHANGE_COUNT ON ()
  ADD EXPECTATION no_schema_changes (VALUE = 0);

-- Statistics: median birth year should fall within a plausible member population range
ALTER TABLE SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION DQ_POLICIES.MEDIAN_BIRTH_YEAR ON (MEME_DOB)
  ADD EXPECTATION median_birth_year_plausible (VALUE BETWEEN 1960 AND 2010);

/* ============================================================================
   SECTION H: Data quality alert
   Fires every 5 minutes when new DMF results exist (TRIGGER_ON_CHANGES means
   results appear shortly after data changes).
   Sends email to t.jones@snowflake.com via MY_EMAIL_INTEGRATION.
   ============================================================================ */

CREATE OR REPLACE ALERT SILVER.MEMBER_DQ_ALERT
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
      'Payer DQ Alert: Data Quality Violations on SILVER.MEMBER',
      'One or more data quality expectations have been violated on zzFACETS_DEV_CLONE.SILVER.MEMBER.\n\nReview violations:\n  SELECT * FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS\n  WHERE TABLE_NAME = ''MEMBER''\n    AND TABLE_SCHEMA = ''SILVER''\n    AND EXPECTATION_VIOLATED = TRUE;\n\nGenerated by Payer RFP 26-038 Topic 9 demo.'
    );

ALTER ALERT SILVER.MEMBER_DQ_ALERT RESUME;

/* ============================================================================
   SECTION I: Demo helper stored procedures
   ============================================================================ */

-- inject_dirty_data(): inserts rows with known violations to trigger DMF alerts
CREATE OR REPLACE PROCEDURE SILVER.INJECT_DIRTY_DATA()
  RETURNS VARCHAR
  LANGUAGE SQL
  COMMENT = 'Inserts 250 dirty member records (50 per violation type) to demonstrate data quality violations'
AS
$$
BEGIN
  -- Violation 1: Duplicate MEME_IDs — copy 50 existing members with same IDs
  -- Identified by DUPLICATE_ prefix on MEME_LAST_NAME for easy cleanup
  INSERT INTO SILVER.MEMBER (
    MEME_ID, SBSB_ID, MEME_LAST_NAME, MEME_FIRST_NAME, MEME_DOB,
    MEME_SEX, MEME_MCTR_TYPE, MEME_STS, MEMBER_STATUS,
    ACTIVE_PCP_NPI, MECD_BIC, SILVER_LOADED_AT, BRONZE_UPDATED_AT, DUPLICATE_COUNT
  )
  SELECT TOP 50
    MEME_ID, SBSB_ID + 99999, 'DUPLICATE_' || MEME_LAST_NAME,
    MEME_FIRST_NAME, MEME_DOB, MEME_SEX, MEME_MCTR_TYPE,
    MEME_STS, MEMBER_STATUS, ACTIVE_PCP_NPI, MECD_BIC,
    CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, 0
  FROM SILVER.MEMBER
  WHERE MEME_ID IS NOT NULL
    AND MEME_LAST_NAME NOT LIKE 'DUPLICATE_%';

  -- Violation 2: Invalid plan type (MEME_ID 9000001–9000050)
  FOR i IN 1 TO 50 DO
    INSERT INTO SILVER.MEMBER (
      MEME_ID, SBSB_ID, MEME_LAST_NAME, MEME_FIRST_NAME, MEME_DOB,
      MEME_SEX, MEME_MCTR_TYPE, MEME_STS, MEMBER_STATUS,
      ACTIVE_PCP_NPI, MECD_BIC, SILVER_LOADED_AT, BRONZE_UPDATED_AT, DUPLICATE_COUNT
    ) VALUES (
      9000000 + :i, 9000000 + :i, 'DIRTY', 'PLAN_TYPE',
      DATEADD('year', -MOD(:i, 60) - 18, CURRENT_DATE()),
      IFF(MOD(:i, 2) = 0, 'M', 'F'), 'UNKNOWN_PLAN', 'A', 'Active',
      '1234567890', NULL, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, 0
    );
  END FOR;

  -- Violation 3: Medicaid member with NULL BIC (MEME_ID 9000051–9000100)
  FOR i IN 1 TO 50 DO
    INSERT INTO SILVER.MEMBER (
      MEME_ID, SBSB_ID, MEME_LAST_NAME, MEME_FIRST_NAME, MEME_DOB,
      MEME_SEX, MEME_MCTR_TYPE, MEME_STS, MEMBER_STATUS,
      ACTIVE_PCP_NPI, MECD_BIC, SILVER_LOADED_AT, BRONZE_UPDATED_AT, DUPLICATE_COUNT
    ) VALUES (
      9000050 + :i, 9000050 + :i, 'DIRTY', 'MISSING_BIC',
      DATEADD('year', -MOD(:i, 55) - 20, CURRENT_DATE()),
      IFF(MOD(:i, 2) = 0, 'F', 'M'), 'MEDCAID', 'A', 'Active',
      '1234567890', NULL, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, 0
    );
  END FOR;

  -- Violation 4: Invalid NPI format (MEME_ID 9000101–9000150)
  FOR i IN 1 TO 50 DO
    INSERT INTO SILVER.MEMBER (
      MEME_ID, SBSB_ID, MEME_LAST_NAME, MEME_FIRST_NAME, MEME_DOB,
      MEME_SEX, MEME_MCTR_TYPE, MEME_STS, MEMBER_STATUS,
      ACTIVE_PCP_NPI, MECD_BIC, SILVER_LOADED_AT, BRONZE_UPDATED_AT, DUPLICATE_COUNT
    ) VALUES (
      9000100 + :i, 9000100 + :i, 'DIRTY', 'BAD_NPI',
      DATEADD('year', -MOD(:i, 45) - 25, CURRENT_DATE()),
      IFF(MOD(:i, 2) = 0, 'M', 'F'), 'COMM', 'A', 'Active',
      'NPI' || LPAD(:i::VARCHAR, 5, '0'), NULL,
      CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, 0
    );
  END FOR;

  -- Violation 5: Missing date of birth (MEME_ID 9000151–9000200)
  FOR i IN 1 TO 50 DO
    INSERT INTO SILVER.MEMBER (
      MEME_ID, SBSB_ID, MEME_LAST_NAME, MEME_FIRST_NAME, MEME_DOB,
      MEME_SEX, MEME_MCTR_TYPE, MEME_STS, MEMBER_STATUS,
      ACTIVE_PCP_NPI, MECD_BIC, SILVER_LOADED_AT, BRONZE_UPDATED_AT, DUPLICATE_COUNT
    ) VALUES (
      9000150 + :i, 9000150 + :i, 'DIRTY', 'NO_DOB', NULL,
      IFF(MOD(:i, 2) = 0, 'F', 'M'), 'DSNP', 'A', 'Active',
      '9876543210', NULL, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, 0
    );
  END FOR;

  RETURN 'Injected 250 dirty records (50 per type): duplicate IDs, invalid plan type, missing BIC, bad NPI, missing DOB. DMFs will re-evaluate within ~30 seconds.';
END;
$$;

-- clean_dirty_data(): removes all injected violation rows
CREATE OR REPLACE PROCEDURE SILVER.CLEAN_DIRTY_DATA()
  RETURNS VARCHAR
  LANGUAGE SQL
  COMMENT = 'Removes dirty records injected by INJECT_DIRTY_DATA — restores clean baseline'
AS
$$
BEGIN
  DELETE FROM SILVER.MEMBER
  WHERE MEME_ID BETWEEN 9000001 AND 9000200
     OR MEME_LAST_NAME LIKE 'DUPLICATE_%';

  RETURN 'Dirty records removed. DMFs will re-evaluate within ~30 seconds — all expectations should clear.';
END;
$$;

/* ============================================================================
   DONE
   ============================================================================ */

SELECT
  'zzFACETS_DEV_CLONE created and fully configured.' AS status,
  'Run CALL INJECT_DIRTY_DATA() to start the demo.' AS next_step;
