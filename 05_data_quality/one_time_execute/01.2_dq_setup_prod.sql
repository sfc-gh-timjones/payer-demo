/*
================================================================================
  Payer RFP 26-038 | Topic 9: Data Quality — Production Monitor
  File: 01.2_dq_setup_prod.sql
  Purpose: Apply the same 9 data metric functions to the LIVE FACETS_DEV data
           (not the demo clone). No alert, no demo sprocs — monitoring only.
  Safe to re-run: ADD DMF steps use IF NOT EXISTS semantics via MODIFY patterns;
  re-running the ADD steps will error if already attached — comment them out
  on subsequent runs and just re-apply expectations if needed.
================================================================================
*/

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WH_XS;
USE DATABASE FACETS_DEV;

/* ============================================================================
   SECTION A: DQ_POLICIES schema and privileges
   ============================================================================ */

CREATE SCHEMA IF NOT EXISTS FACETS_DEV.DQ_POLICIES
  COMMENT = 'Custom data metric functions for healthcare data quality';

GRANT DATABASE ROLE SNOWFLAKE.DATA_METRIC_USER    TO ROLE ACCOUNTADMIN;
GRANT EXECUTE DATA METRIC FUNCTION ON ACCOUNT     TO ROLE ACCOUNTADMIN;
GRANT MANAGE DATA QUALITY ON ACCOUNT              TO ROLE ACCOUNTADMIN;

/* ============================================================================
   SECTION B: Custom DMFs (healthcare-specific validations)
   ============================================================================ */

USE SCHEMA FACETS_DEV.DQ_POLICIES;

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
   SECTION C: Monitoring schedule
   ============================================================================ */

ALTER TABLE SILVER.MEMBER
  SET DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';

/* ============================================================================
   SECTION D: Attach DMFs to SILVER.MEMBER
   Note: FRESHNESS requires TIMESTAMP_LTZ — use SILVER_LOADED_AT, not
   BRONZE_UPDATED_AT (TIMESTAMP_NTZ).
   Lambda syntax for ACCEPTED_VALUES: ON (col, col -> expression)
   ============================================================================ */

USE SCHEMA FACETS_DEV.SILVER;

-- 1. Volume
ALTER TABLE SILVER.MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ();

-- 2. Freshness
ALTER TABLE SILVER.MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS
  ON (SILVER_LOADED_AT);

-- 3. Completeness: null BIC (Medicaid compliance)
ALTER TABLE SILVER.MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT
  ON (MECD_BIC);

-- 4. Completeness: null DOB
ALTER TABLE SILVER.MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT
  ON (MEME_DOB);

-- 5. Uniqueness: duplicate member IDs
ALTER TABLE SILVER.MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.DUPLICATE_COUNT
  ON (MEME_ID);

-- 6. Validity: plan type
ALTER TABLE SILVER.MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES
  ON (MEME_MCTR_TYPE, MEME_MCTR_TYPE -> MEME_MCTR_TYPE IN ('COMM', 'DSNP', 'MEDCAID'));

-- 7. Validity: sex code
ALTER TABLE SILVER.MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES
  ON (MEME_SEX, MEME_SEX -> MEME_SEX IN ('M', 'F', 'U'));

-- 8. Custom: NPI format
ALTER TABLE SILVER.MEMBER
  ADD DATA METRIC FUNCTION DQ_POLICIES.INVALID_NPI_COUNT
  ON (ACTIVE_PCP_NPI);

-- 9. Custom: Medicaid members missing BIC
ALTER TABLE SILVER.MEMBER
  ADD DATA METRIC FUNCTION DQ_POLICIES.MEDICAID_MISSING_BIC_COUNT
  ON (MEME_MCTR_TYPE, MECD_BIC);

/* ============================================================================
   SECTION E: Expectations
   ============================================================================ */

ALTER TABLE SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ()
  ADD EXPECTATION member_table_has_rows (VALUE > 0);

ALTER TABLE SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS ON (SILVER_LOADED_AT)
  ADD EXPECTATION data_fresh_within_15m (VALUE < 900);

ALTER TABLE SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (MECD_BIC)
  ADD EXPECTATION no_null_bic (VALUE = 0);

ALTER TABLE SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (MEME_DOB)
  ADD EXPECTATION no_null_dob (VALUE = 0);

ALTER TABLE SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.DUPLICATE_COUNT ON (MEME_ID)
  ADD EXPECTATION no_duplicate_member_ids (VALUE = 0);

ALTER TABLE SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES
  ON (MEME_MCTR_TYPE, MEME_MCTR_TYPE -> MEME_MCTR_TYPE IN ('COMM', 'DSNP', 'MEDCAID'))
  ADD EXPECTATION all_valid_plan_types (VALUE = 0);

ALTER TABLE SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES
  ON (MEME_SEX, MEME_SEX -> MEME_SEX IN ('M', 'F', 'U'))
  ADD EXPECTATION all_valid_sex_codes (VALUE = 0);

ALTER TABLE SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION DQ_POLICIES.INVALID_NPI_COUNT
  ON (ACTIVE_PCP_NPI)
  ADD EXPECTATION all_valid_npi_formats (VALUE = 0);

ALTER TABLE SILVER.MEMBER
  MODIFY DATA METRIC FUNCTION DQ_POLICIES.MEDICAID_MISSING_BIC_COUNT
  ON (MEME_MCTR_TYPE, MECD_BIC)
  ADD EXPECTATION no_medicaid_missing_bic (VALUE = 0);

/* ============================================================================
   DONE — verify with:

   SELECT
     METRIC_NAME,
     ARGUMENT_NAMES AS column_name,
     EXPECTATION_EXPRESSION,
     VALUE,
     EXPECTATION_VIOLATED,
     MEASUREMENT_TIME
   FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS
   WHERE TABLE_NAME     = 'MEMBER'
     AND TABLE_SCHEMA   = 'SILVER'
     AND TABLE_DATABASE = 'FACETS_DEV'
     AND EXPECTATION_NAME IN (
       SELECT EXPECTATION_NAME
       FROM TABLE(FACETS_DEV.INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_EXPECTATIONS(
         REF_ENTITY_NAME => 'FACETS_DEV.SILVER.MEMBER', REF_ENTITY_DOMAIN => 'TABLE'))
     )
   QUALIFY ROW_NUMBER() OVER (PARTITION BY METRIC_NAME, ARGUMENT_NAMES, EXPECTATION_NAME
                               ORDER BY MEASUREMENT_TIME DESC) = 1
   ORDER BY METRIC_NAME;
   ============================================================================ */

SELECT
  'FACETS_DEV.SILVER.MEMBER data quality monitoring configured.' AS status,
  '9 DMFs attached with TRIGGER_ON_CHANGES schedule.'           AS details;

/* ============================================================================
   ── PART 2: FACETS_BRONZE.RAW.CMC_MEME_MEMBER (Openflow CDC source) ─────────
   Applies 6 DMFs to the raw Bronze table coming directly from Openflow.
   No NPI or BIC columns exist at this layer — those custom DMFs are omitted.
   All timestamps in this table are TIMESTAMP_NTZ so FRESHNESS() uses the
   no-argument version (entity metadata) rather than a column value.
   ============================================================================ */

USE DATABASE FACETS_BRONZE;

/* ============================================================================
   SECTION F: Monitoring schedule for Bronze table
   ============================================================================ */

ALTER TABLE FACETS_BRONZE.RAW.CMC_MEME_MEMBER
  SET DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';

/* ============================================================================
   SECTION G: Attach DMFs to RAW.CMC_MEME_MEMBER
   ============================================================================ */

USE SCHEMA FACETS_BRONZE.RAW;

-- 1. Volume: total row count
ALTER TABLE CMC_MEME_MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ();

-- 2. Freshness: entity-level — no TIMESTAMP_LTZ/TZ column exists in Bronze.
--    FRESHNESS() (no args) measures time since the table was last modified,
--    which reflects the last Openflow write.
ALTER TABLE CMC_MEME_MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS ON ();

-- 3. Completeness: null DOB
ALTER TABLE CMC_MEME_MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT
  ON (MEME_DOB);

-- 4. Uniqueness: duplicate member IDs
ALTER TABLE CMC_MEME_MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.DUPLICATE_COUNT
  ON (MEME_ID);

-- 5. Validity: plan type
ALTER TABLE CMC_MEME_MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES
  ON (MEME_MCTR_TYPE, MEME_MCTR_TYPE -> MEME_MCTR_TYPE IN ('COMM', 'DSNP', 'MEDCAID'));

-- 6. Validity: sex code
ALTER TABLE CMC_MEME_MEMBER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES
  ON (MEME_SEX, MEME_SEX -> MEME_SEX IN ('M', 'F', 'U'));

/* ============================================================================
   SECTION H: Expectations for CMC_MEME_MEMBER
   ============================================================================ */

ALTER TABLE CMC_MEME_MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ()
  ADD EXPECTATION member_table_has_rows (VALUE > 0);

-- Freshness: table must have been written to within the last 15 minutes
ALTER TABLE CMC_MEME_MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS ON ()
  ADD EXPECTATION data_fresh_within_15m (VALUE < 900);

ALTER TABLE CMC_MEME_MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (MEME_DOB)
  ADD EXPECTATION no_null_dob (VALUE = 0);

ALTER TABLE CMC_MEME_MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.DUPLICATE_COUNT ON (MEME_ID)
  ADD EXPECTATION no_duplicate_member_ids (VALUE = 0);

ALTER TABLE CMC_MEME_MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES
  ON (MEME_MCTR_TYPE, MEME_MCTR_TYPE -> MEME_MCTR_TYPE IN ('COMM', 'DSNP', 'MEDCAID'))
  ADD EXPECTATION all_valid_plan_types (VALUE = 0);

ALTER TABLE CMC_MEME_MEMBER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES
  ON (MEME_SEX, MEME_SEX -> MEME_SEX IN ('M', 'F', 'U'))
  ADD EXPECTATION all_valid_sex_codes (VALUE = 0);

/* ============================================================================
   DONE — verify with:

   SELECT
     METRIC_NAME,
     ARGUMENT_NAMES AS column_name,
     EXPECTATION_EXPRESSION,
     VALUE,
     EXPECTATION_VIOLATED,
     MEASUREMENT_TIME
   FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS
   WHERE TABLE_NAME     = 'CMC_MEME_MEMBER'
     AND TABLE_SCHEMA   = 'RAW'
     AND TABLE_DATABASE = 'FACETS_BRONZE'
     AND EXPECTATION_NAME IN (
       SELECT EXPECTATION_NAME
       FROM TABLE(FACETS_BRONZE.INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_EXPECTATIONS(
         REF_ENTITY_NAME => 'FACETS_BRONZE.RAW.CMC_MEME_MEMBER', REF_ENTITY_DOMAIN => 'TABLE'))
     )
   QUALIFY ROW_NUMBER() OVER (PARTITION BY METRIC_NAME, ARGUMENT_NAMES, EXPECTATION_NAME
                               ORDER BY MEASUREMENT_TIME DESC) = 1
   ORDER BY METRIC_NAME;
   ============================================================================ */

SELECT
  'FACETS_BRONZE.RAW.CMC_MEME_MEMBER data quality monitoring configured.' AS status,
  '6 DMFs attached with TRIGGER_ON_CHANGES schedule.'                      AS details;
