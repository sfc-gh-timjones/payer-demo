-- =============================================================================
-- FILE: 01_governance_setup.sql
-- PURPOSE: CalOptima RFP 26-038 | Topic 4 (Data Governance) + Topic 5 (Security)
--          One-time setup: roles, clone, classification profile, masking policies,
--          row access policy, MEMBER_PHI table, and all grants.
--
-- DEMO SCRIPTS REFERENCE (by section):
--   Section A  Lines   1-75   → Roles, databases, warehouses
--   Section B  Lines  77-160  → DATA_CLASSIFICATION tag + CALOPTIMA profile
--   Section C  Lines 162-195  → AI classification applied to zFACETS_DEV_CLONE
--   Section D  Lines 197-310  → Tag-based masking policies (STRING / DATE / TIMESTAMP)
--   Section E  Lines 312-325  → Attach masking policies to the tag
--   Section F  Lines 327-370  → MEMBER_PHI table in PROTECTED schema
--   Section G  Lines 372-420  → Manual PII/PHI tags on MEMBER_PHI columns
--   Section H  Lines 422-480  → Row access policy (MEME_MCTR_TYPE plan-type filter)
--   Section I  Lines 482-560  → Role grants
--
-- SOURCE TABLE: FACETS_DEV.SILVER.MEMBER (29 columns, ~92k rows)
-- PHI TABLE:    GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI (managed access schema)
-- CLONE:        zFACETS_DEV_CLONE (zero-copy clone of FACETS_DEV for discovery demo)
-- =============================================================================


-- =============================================================================
-- SECTION A: ROLES, DATABASES, WAREHOUSES
-- Lines 1-75
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WH_XS;

-- ── Demo roles (Scenario 5: 4 privilege levels) ─────────────────────────────
CREATE ROLE IF NOT EXISTS DATA_GOVERNOR_ROLE
    COMMENT = 'Owns governance objects: tags, masking policies, row access policies.';
CREATE ROLE IF NOT EXISTS DATA_ENGINEER_ROLE
    COMMENT = 'Full data access — builds pipelines, no DDL on governed schemas.';
CREATE ROLE IF NOT EXISTS ANALYTICS_INNOVATOR_ROLE
    COMMENT = 'Analyst with own sandbox; reads governed data with partial masking. No Medi-Cal rows.';
CREATE ROLE IF NOT EXISTS BUSINESS_ANALYST_ROLE
    COMMENT = 'Read-only. HMO commercial members only. All PHI columns masked.';

-- ── Role hierarchy ───────────────────────────────────────────────────────────
-- ACCOUNTADMIN > DATA_GOVERNOR > DATA_ENGINEER > ANALYTICS_INNOVATOR > BUSINESS_ANALYST
GRANT ROLE DATA_GOVERNOR_ROLE        TO ROLE SYSADMIN;
GRANT ROLE DATA_ENGINEER_ROLE        TO ROLE DATA_GOVERNOR_ROLE;
GRANT ROLE ANALYTICS_INNOVATOR_ROLE  TO ROLE DATA_ENGINEER_ROLE;
GRANT ROLE BUSINESS_ANALYST_ROLE     TO ROLE ANALYTICS_INNOVATOR_ROLE;

-- Assign roles to current user so we can USE ROLE in demo scripts
GRANT ROLE DATA_GOVERNOR_ROLE        TO USER COCO;
GRANT ROLE DATA_ENGINEER_ROLE        TO USER COCO;
GRANT ROLE ANALYTICS_INNOVATOR_ROLE  TO USER COCO;
GRANT ROLE BUSINESS_ANALYST_ROLE     TO USER COCO;

-- ── Warehouse access for all demo roles ─────────────────────────────────────
GRANT USAGE ON WAREHOUSE WH_XS TO ROLE DATA_GOVERNOR_ROLE;
GRANT USAGE ON WAREHOUSE WH_XS TO ROLE DATA_ENGINEER_ROLE;
GRANT USAGE ON WAREHOUSE WH_XS TO ROLE ANALYTICS_INNOVATOR_ROLE;
GRANT USAGE ON WAREHOUSE WH_XS TO ROLE BUSINESS_ANALYST_ROLE;

-- ── Zero-copy clone of FACETS_DEV for the discovery demo ────────────────────
-- Isolated from live Bronze/Silver — classification demo cannot affect production
CREATE OR REPLACE DATABASE zFACETS_DEV_CLONE CLONE FACETS_DEV;

-- ── Isolated governance database (PHI table lives here, separate from FACETS_DEV) ──
CREATE DATABASE IF NOT EXISTS GOVERNANCE_CA_DEMO;

-- PROTECTED: WITH MANAGED ACCESS
-- All grants flow through schema owner (ACCOUNTADMIN) — object owners
-- cannot self-grant on PHI tables. Required for HIPAA-aligned PHI isolation.
CREATE SCHEMA IF NOT EXISTS GOVERNANCE_CA_DEMO.PROTECTED
    WITH MANAGED ACCESS
    COMMENT = 'PHI/PII governed schema. Managed access: only schema owner may grant privileges.';

-- POLICY_STORE: holds tags, masking policies, and the row access policy mapping table
CREATE SCHEMA IF NOT EXISTS GOVERNANCE_CA_DEMO.POLICY_STORE
    COMMENT = 'Governance policy objects: tags, masking policies, row access policies.';


-- =============================================================================
-- SECTION B: DATA_CLASSIFICATION TAG + CALOPTIMA CLASSIFICATION PROFILE
-- Lines 77-160
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE GOVERNANCE_CA_DEMO;
USE SCHEMA POLICY_STORE;

-- ── DATA_CLASSIFICATION tag ──────────────────────────────────────────────────
-- PROPAGATE = ON_DEPENDENCY_AND_DATA_MOVEMENT:
--   Tags follow data through CTAS, clones, and view dependencies automatically.
--   No manual re-tagging required when analysts copy/move governed tables.
CREATE OR REPLACE TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION
    ALLOWED_VALUES 'PII', 'RESTRICTED', 'SENSITIVE', 'INTERNAL', 'PUBLIC'
    COMMENT = 'CalOptima enterprise PHI/PII classification. HIPAA/CCPA/GDPR compliance. Propagates on dependency and data movement.'
    PROPAGATE = ON_DEPENDENCY_AND_DATA_MOVEMENT;

-- ── CALOPTIMA_CLASSIFICATION_PROFILE ────────────────────────────────────────
-- Maps Snowflake AI semantic categories → DATA_CLASSIFICATION tag values.
-- Created under SYSADMIN (SNOWFLAKE.DATA_PRIVACY requires SYSADMIN privileges).
-- Applied to zFACETS_DEV_CLONE for the discovery demo.
--
-- Compliance mapping:
--   PII        → GDPR Art.4(1), HIPAA PHI, CCPA Personal Information
--   RESTRICTED → GDPR Art.9 (special categories), HIPAA limited dataset
--   SENSITIVE  → GDPR Art.6 (legitimate interest), HIPAA §164.514(b) safe harbor
--   INTERNAL   → SOX controls, internal business data
USE ROLE SYSADMIN;

CREATE OR REPLACE SNOWFLAKE.DATA_PRIVACY.CLASSIFICATION_PROFILE
    GOVERNANCE_CA_DEMO.POLICY_STORE.CALOPTIMA_CLASSIFICATION_PROFILE(
    {
      'minimum_object_age_for_classification_days': 0,
      'maximum_classification_validity_days': 90,
      'auto_tag': true,
      'classify_views': false,
      'tag_map': {
        'column_tag_map': [
          {
            'tag_name': 'GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION',
            'tag_value': 'PII',
            'semantic_categories': [
              'NATIONAL_IDENTIFIER',
              'US_BANK_ACCOUNT_NUMBER',
              'EMAIL',
              'CREDIT_CARD_NUMBER',
              'US_SOCIAL_SECURITY_NUMBER'
            ]
          },
          {
            'tag_name': 'GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION',
            'tag_value': 'RESTRICTED',
            'semantic_categories': [
              'DATE_OF_BIRTH',
              'PHONE_NUMBER'
            ]
          },
          {
            'tag_name': 'GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION',
            'tag_value': 'SENSITIVE',
            'semantic_categories': [
              'NAME',
              'STREET_ADDRESS',
              'CITY',
              'US_STATE',
              'ZIP_CODE'
            ]
          },
          {
            'tag_name': 'GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION',
            'tag_value': 'INTERNAL',
            'semantic_categories': [
              'JOB_TITLE',
              'OCCUPATION',
              'COMPANY'
            ]
          }
        ]
      }
    });

-- Grant DATA_GOVERNOR_ROLE the ability to apply tags
GRANT APPLY ON TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION TO ROLE DATA_GOVERNOR_ROLE;
GRANT APPLY ON TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION TO ROLE SYSADMIN;


-- =============================================================================
-- SECTION C: AI CLASSIFICATION APPLIED TO CLONE
-- Lines 162-195
-- (Run: applies CALOPTIMA_CLASSIFICATION_PROFILE to zFACETS_DEV_CLONE.SILVER.MEMBER)
-- =============================================================================

USE ROLE SYSADMIN;

-- Attach classification profile to the clone database
ALTER DATABASE zFACETS_DEV_CLONE
    SET CLASSIFICATION_PROFILE =
        'GOVERNANCE_CA_DEMO.POLICY_STORE.CALOPTIMA_CLASSIFICATION_PROFILE';

-- Grant DATA_GOVERNOR_ROLE access to the clone for the discovery demo
GRANT USAGE ON DATABASE zFACETS_DEV_CLONE TO ROLE DATA_GOVERNOR_ROLE;
GRANT USAGE ON ALL SCHEMAS IN DATABASE zFACETS_DEV_CLONE TO ROLE DATA_GOVERNOR_ROLE;
GRANT SELECT ON ALL TABLES IN DATABASE zFACETS_DEV_CLONE TO ROLE DATA_GOVERNOR_ROLE;
GRANT CREATE TABLE ON SCHEMA zFACETS_DEV_CLONE.SILVER TO ROLE DATA_ENGINEER_ROLE;
GRANT USAGE ON DATABASE zFACETS_DEV_CLONE TO ROLE DATA_ENGINEER_ROLE;
GRANT USAGE ON ALL SCHEMAS IN DATABASE zFACETS_DEV_CLONE TO ROLE DATA_ENGINEER_ROLE;
GRANT SELECT ON ALL TABLES IN DATABASE zFACETS_DEV_CLONE TO ROLE DATA_ENGINEER_ROLE;

-- Run AI classification on the MEMBER table in the clone (auto_tag: true applies tags)
USE ROLE SYSADMIN;
CALL SYSTEM$CLASSIFY(
    'zFACETS_DEV_CLONE.SILVER.MEMBER',
    'GOVERNANCE_CA_DEMO.POLICY_STORE.CALOPTIMA_CLASSIFICATION_PROFILE'
);


-- =============================================================================
-- SECTION D: TAG-BASED MASKING POLICIES
-- Lines 197-310
--
-- Three policies cover all column data types in MEMBER_PHI.
-- Attached to DATA_CLASSIFICATION tag once → applies to every tagged column
-- automatically, regardless of which table it lands in.
--
-- Role privilege matrix:
-- ┌──────────────────────────┬─────────────┬─────────────┬───────────────────┬──────────────────┐
-- │ Classification           │ ACCOUNTADMIN│ DATA_ENGINEER│ ANALYTICS_INNOVATOR│ BUSINESS_ANALYST │
-- │                          │ DATA_GOVERNOR│            │                   │                  │
-- ├──────────────────────────┼─────────────┼─────────────┼───────────────────┼──────────────────┤
-- │ PII   (MECD_AID_CD/BIC)  │ Full        │ Full        │ *** PHI REDACTED**│ *** PHI REDACTED*│
-- │ RESTRICTED (DOB)         │ Full        │ Full        │ Year only         │ NULL             │
-- │ SENSITIVE (name, sex)    │ Full        │ Full        │ First initial+*** │ *** SENSITIVE ***│
-- │ INTERNAL                 │ Full        │ Full        │ Full              │ Full             │
-- └──────────────────────────┴─────────────┴─────────────┴───────────────────┴──────────────────┘
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE GOVERNANCE_CA_DEMO;
USE SCHEMA POLICY_STORE;

-- Grant CREATE MASKING POLICY to DATA_GOVERNOR_ROLE so they can own policy objects
GRANT CREATE MASKING POLICY ON SCHEMA GOVERNANCE_CA_DEMO.POLICY_STORE TO ROLE DATA_GOVERNOR_ROLE;
GRANT APPLY MASKING POLICY ON ACCOUNT TO ROLE DATA_GOVERNOR_ROLE;
GRANT CREATE ROW ACCESS POLICY ON SCHEMA GOVERNANCE_CA_DEMO.POLICY_STORE TO ROLE DATA_GOVERNOR_ROLE;
GRANT APPLY ROW ACCESS POLICY ON ACCOUNT TO ROLE DATA_GOVERNOR_ROLE;
GRANT CREATE TAG ON SCHEMA GOVERNANCE_CA_DEMO.POLICY_STORE TO ROLE DATA_GOVERNOR_ROLE;

USE ROLE ACCOUNTADMIN;

-- ── STRING masking policy ────────────────────────────────────────────────────
-- Covers: MEME_LAST_NAME, MEME_FIRST_NAME, MEME_SEX, SEX_DESC, SUBSCRIBER names,
--         MECD_AID_CD, MECD_BIC, ACTIVE_PCP_NAME, ACTIVE_PCP_NPI
CREATE OR REPLACE MASKING POLICY GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION_MASK_STRING
AS (VAL STRING) RETURNS STRING ->
CASE
    -- Full access: admins and engineers see raw PHI
    WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'DATA_GOVERNOR_ROLE', 'DATA_ENGINEER_ROLE')
        THEN VAL
    -- ANALYTICS_INNOVATOR: partial masking by classification level
    WHEN CURRENT_ROLE() = 'ANALYTICS_INNOVATOR_ROLE' THEN
        CASE SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION')
            -- PII: Medi-Cal BIC/AID — fully redacted (HIPAA §164.514)
            WHEN 'PII'        THEN '*** PHI REDACTED ***'
            -- RESTRICTED: show last 4 chars only
            WHEN 'RESTRICTED' THEN CONCAT('***-', RIGHT(VAL, 4))
            -- SENSITIVE: first initial + asterisks (GDPR pseudonymization)
            WHEN 'SENSITIVE'  THEN CONCAT(LEFT(VAL, 1), REPEAT('*', GREATEST(LENGTH(VAL) - 1, 0)))
            ELSE VAL
        END
    -- BUSINESS_ANALYST: most restrictive — all PHI/PII fully masked
    WHEN CURRENT_ROLE() = 'BUSINESS_ANALYST_ROLE' THEN
        CASE SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION')
            WHEN 'PII'        THEN '*** PHI REDACTED ***'
            WHEN 'RESTRICTED' THEN '*** RESTRICTED ***'
            WHEN 'SENSITIVE'  THEN '*** SENSITIVE ***'
            ELSE VAL
        END
    ELSE '*** ACCESS DENIED ***'
END
COMMENT = 'STRING masking for DATA_CLASSIFICATION tag. PII→redacted, RESTRICTED→partial, SENSITIVE→pseudonymized. HIPAA §164.514 / GDPR Art.25.';

-- ── DATE masking policy ──────────────────────────────────────────────────────
-- Covers: MEME_DOB, SUBSCRIBER_DOB, PCP_EFF_DT, MEDICAID_EFF_DT, MEDICAID_TERM_DT
-- HIPAA §164.514(b) safe harbor: dates generalized to year for RESTRICTED columns
CREATE OR REPLACE MASKING POLICY GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION_MASK_DATE
AS (VAL DATE) RETURNS DATE ->
CASE
    WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'DATA_GOVERNOR_ROLE', 'DATA_ENGINEER_ROLE')
        THEN VAL
    WHEN CURRENT_ROLE() = 'ANALYTICS_INNOVATOR_ROLE' THEN
        CASE SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION')
            WHEN 'PII'        THEN NULL
            -- HIPAA §164.514(b): year-only generalization satisfies safe harbor
            WHEN 'RESTRICTED' THEN DATE_TRUNC('YEAR', VAL)
            WHEN 'SENSITIVE'  THEN DATE_TRUNC('MONTH', VAL)
            ELSE VAL
        END
    WHEN CURRENT_ROLE() = 'BUSINESS_ANALYST_ROLE' THEN
        CASE SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION')
            WHEN 'PII'        THEN NULL
            WHEN 'RESTRICTED' THEN NULL
            WHEN 'SENSITIVE'  THEN DATE_TRUNC('YEAR', VAL)
            ELSE VAL
        END
    ELSE NULL
END
COMMENT = 'DATE masking for DATA_CLASSIFICATION tag. HIPAA §164.514(b) safe harbor: RESTRICTED dates → year-only for Analytics Innovator, NULL for Business Analyst.';

-- ── TIMESTAMP masking policy ─────────────────────────────────────────────────
-- Covers: BRONZE_UPDATED_AT (TIMESTAMP_NTZ), SILVER_LOADED_AT (TIMESTAMP_LTZ)
-- These are INTERNAL (metadata), so the ELSE VAL branch fires for all roles.
-- Policy exists because tag-based masking requires a policy for each data type
-- present in columns that carry the tag.
CREATE OR REPLACE MASKING POLICY GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION_MASK_TIMESTAMP
AS (VAL TIMESTAMP_NTZ) RETURNS TIMESTAMP_NTZ ->
CASE
    WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'DATA_GOVERNOR_ROLE', 'DATA_ENGINEER_ROLE')
        THEN VAL
    WHEN CURRENT_ROLE() = 'ANALYTICS_INNOVATOR_ROLE' THEN
        CASE SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION')
            WHEN 'PII'        THEN NULL
            WHEN 'RESTRICTED' THEN DATE_TRUNC('DAY', VAL)
            ELSE VAL
        END
    WHEN CURRENT_ROLE() = 'BUSINESS_ANALYST_ROLE' THEN
        CASE SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION')
            WHEN 'PII'        THEN NULL
            WHEN 'RESTRICTED' THEN NULL
            ELSE VAL
        END
    ELSE NULL
END
COMMENT = 'TIMESTAMP_NTZ masking for DATA_CLASSIFICATION tag.';


-- =============================================================================
-- SECTION E: ATTACH MASKING POLICIES TO THE TAG
-- Lines 312-325
--
-- After this: every column tagged DATA_CLASSIFICATION is automatically masked
-- based on its data type and tag value — no per-column ALTER TABLE needed.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE GOVERNANCE_CA_DEMO;
USE SCHEMA POLICY_STORE;

ALTER TAG DATA_CLASSIFICATION
    SET MASKING POLICY DATA_CLASSIFICATION_MASK_STRING;

ALTER TAG DATA_CLASSIFICATION
    SET MASKING POLICY DATA_CLASSIFICATION_MASK_DATE;

ALTER TAG DATA_CLASSIFICATION
    SET MASKING POLICY DATA_CLASSIFICATION_MASK_TIMESTAMP;


-- =============================================================================
-- SECTION F: MEMBER_PHI TABLE IN PROTECTED SCHEMA
-- Lines 327-370
--
-- Isolated copy of FACETS_DEV.SILVER.MEMBER — governance demo runs against
-- this table, not the live Silver table. Decoupled from Openflow CDC pipeline.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE GOVERNANCE_CA_DEMO;
USE SCHEMA PROTECTED;

-- Copy the member table to the governed, managed-access schema
CREATE OR REPLACE TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
AS SELECT * FROM FACETS_DEV.SILVER.MEMBER;

-- Confirm row counts match source
SELECT
    (SELECT COUNT(*) FROM GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI)  AS phi_table_rows,
    (SELECT COUNT(*) FROM FACETS_DEV.SILVER.MEMBER)                  AS source_rows;


-- =============================================================================
-- SECTION G: MANUAL PII/PHI TAGS ON MEMBER_PHI COLUMNS
-- Lines 372-420
--
-- The discovery demo uses AI auto-classification on the clone.
-- The security demo (03_security_demo.sql) requires guaranteed tags so masking
-- fires reliably during the live audience walk-through.
-- Manually applying tags here ensures the demo works regardless of AI confidence.
--
-- Column → Classification mapping (CalOptima / HIPAA rationale):
--   MEME_LAST_NAME, MEME_FIRST_NAME        SENSITIVE  — patient name (PHI, GDPR Art.4)
--   SUBSCRIBER_LAST_NAME, FIRST_NAME       SENSITIVE  — policyholder name
--   SEX_DESC, MEME_SEX                     SENSITIVE  — biological sex (HIPAA PHI)
--   ACTIVE_PCP_NAME                        SENSITIVE  — treating provider (HIPAA PHI)
--   MEME_DOB, SUBSCRIBER_DOB              RESTRICTED  — date of birth (HIPAA §164.514(b))
--   MECD_AID_CD                               PII     — Medi-Cal aid code (HIPAA PHI)
--   MECD_BIC                                  PII     — Medi-Cal BIC (beneficiary ID, PHI)
--   ACTIVE_PCP_NPI, ACTIVE_PCP_PRPR_ID       INTERNAL — provider identifiers
--   MEME_MCTR_TYPE, plan-type columns        INTERNAL — plan classification (RLS column)
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- PII: Medi-Cal identifiers — most sensitive, direct HIPAA PHI
ALTER TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
    MODIFY COLUMN MECD_AID_CD
        SET TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION = 'PII';

ALTER TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
    MODIFY COLUMN MECD_BIC
        SET TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION = 'PII';

-- RESTRICTED: Dates of birth — HIPAA §164.514(b) safe harbor requires generalization
ALTER TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
    MODIFY COLUMN MEME_DOB
        SET TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION = 'RESTRICTED';

ALTER TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
    MODIFY COLUMN SUBSCRIBER_DOB
        SET TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION = 'RESTRICTED';

-- SENSITIVE: Names and gender — PHI under HIPAA, special category under GDPR
ALTER TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
    MODIFY COLUMN MEME_LAST_NAME
        SET TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION = 'SENSITIVE';

ALTER TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
    MODIFY COLUMN MEME_FIRST_NAME
        SET TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION = 'SENSITIVE';

ALTER TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
    MODIFY COLUMN SUBSCRIBER_LAST_NAME
        SET TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION = 'SENSITIVE';

ALTER TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
    MODIFY COLUMN SUBSCRIBER_FIRST_NAME
        SET TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION = 'SENSITIVE';

ALTER TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
    MODIFY COLUMN MEME_SEX
        SET TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION = 'SENSITIVE';

ALTER TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
    MODIFY COLUMN SEX_DESC
        SET TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION = 'SENSITIVE';

ALTER TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
    MODIFY COLUMN ACTIVE_PCP_NAME
        SET TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION = 'SENSITIVE';


-- =============================================================================
-- SECTION H: ROW ACCESS POLICY — PLAN TYPE FILTER
-- Lines 422-480
--
-- Filters rows in MEMBER_PHI by MEME_MCTR_TYPE based on role.
-- Plan types in data: DSNP (30,866 rows), MEDCAID (30,642 rows), COMM (30,593 rows)
--
-- Role → Visible plan types:
--   ACCOUNTADMIN / DATA_GOVERNOR / DATA_ENGINEER → ALL (DSNP + MEDCAID + COMM)
--   ANALYTICS_INNOVATOR_ROLE                     → DSNP + COMM (no Medi-Cal)
--   BUSINESS_ANALYST_ROLE                        → COMM only
--
-- Story: Business analysts running commercial plan analytics should never see
-- Medi-Cal (MEDCAID) or DSNP members — heightened regulatory sensitivity.
-- HIPAA minimum necessary standard. CalOptima regulatory compliance.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE GOVERNANCE_CA_DEMO;
USE SCHEMA POLICY_STORE;

-- Mapping table: role → which plan types are visible
CREATE OR REPLACE TABLE ROW_POLICY_MAP (
    ROLE               VARCHAR(100)  NOT NULL,
    VISIBLE_PLAN_TYPE  VARCHAR(20)   NOT NULL,
    COMMENT            VARCHAR(200)
);

INSERT INTO ROW_POLICY_MAP VALUES
    ('DATA_ENGINEER_ROLE',        'ALL',    'Full access — pipeline engineers'),
    ('DATA_GOVERNOR_ROLE',        'ALL',    'Full access — governance team'),
    ('ANALYTICS_INNOVATOR_ROLE',  'COMM',   'Commercial HMO plan members'),
    ('ANALYTICS_INNOVATOR_ROLE',  'DSNP',   'Dual-eligible Special Needs Plan members'),
    ('BUSINESS_ANALYST_ROLE',     'COMM',   'Commercial members only — no Medi-Cal or DSNP');

-- Row access policy: filter MEMBER_PHI rows by plan type based on role
-- Attaches on MEME_MCTR_TYPE column
CREATE OR REPLACE ROW ACCESS POLICY GOVERNANCE_CA_DEMO.POLICY_STORE.MEMBER_PLAN_ACCESS_POLICY
    AS (PLAN_TYPE VARCHAR) RETURNS BOOLEAN ->
    CASE
        -- Admins and governors see everything
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'DATA_GOVERNOR_ROLE', 'DATA_ENGINEER_ROLE')
            THEN TRUE
        -- Other roles: check mapping table
        ELSE EXISTS (
            SELECT 1
            FROM GOVERNANCE_CA_DEMO.POLICY_STORE.ROW_POLICY_MAP rp
            WHERE rp.ROLE = CURRENT_ROLE()
              AND (rp.VISIBLE_PLAN_TYPE = 'ALL' OR rp.VISIBLE_PLAN_TYPE = PLAN_TYPE)
        )
    END
    COMMENT = 'Row-level filter: limits MEMBER_PHI rows by MEME_MCTR_TYPE per role. HIPAA minimum necessary standard. Medi-Cal (MEDCAID) and DSNP protected from commercial analyst access.';

-- Attach row access policy to MEMBER_PHI on the plan type column
ALTER TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
    ADD ROW ACCESS POLICY GOVERNANCE_CA_DEMO.POLICY_STORE.MEMBER_PLAN_ACCESS_POLICY
    ON (MEME_MCTR_TYPE);


-- =============================================================================
-- SECTION I: ROLE GRANTS
-- Lines 482-560
--
-- GOVERNANCE_CA_DEMO.PROTECTED is a managed-access schema:
-- ALL grants on tables inside it must come from ACCOUNTADMIN (schema owner).
-- DATA_ENGINEER_ROLE cannot grant SELECT on MEMBER_PHI to others.
-- This is the governance control — engineers cannot bypass the policy store.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- ── GOVERNANCE_CA_DEMO database access ──────────────────────────────────────
GRANT USAGE ON DATABASE GOVERNANCE_CA_DEMO TO ROLE DATA_GOVERNOR_ROLE;
GRANT USAGE ON DATABASE GOVERNANCE_CA_DEMO TO ROLE DATA_ENGINEER_ROLE;
GRANT USAGE ON DATABASE GOVERNANCE_CA_DEMO TO ROLE ANALYTICS_INNOVATOR_ROLE;
GRANT USAGE ON DATABASE GOVERNANCE_CA_DEMO TO ROLE BUSINESS_ANALYST_ROLE;

-- ── PROTECTED schema (managed access — grants from schema owner only) ────────
GRANT USAGE ON SCHEMA GOVERNANCE_CA_DEMO.PROTECTED TO ROLE DATA_GOVERNOR_ROLE;
GRANT USAGE ON SCHEMA GOVERNANCE_CA_DEMO.PROTECTED TO ROLE DATA_ENGINEER_ROLE;
GRANT USAGE ON SCHEMA GOVERNANCE_CA_DEMO.PROTECTED TO ROLE ANALYTICS_INNOVATOR_ROLE;
GRANT USAGE ON SCHEMA GOVERNANCE_CA_DEMO.PROTECTED TO ROLE BUSINESS_ANALYST_ROLE;

-- All four roles get SELECT on MEMBER_PHI — masking and row policies enforce access transparently
GRANT SELECT ON TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI TO ROLE DATA_GOVERNOR_ROLE;
GRANT SELECT ON TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI TO ROLE DATA_ENGINEER_ROLE;
GRANT SELECT ON TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI TO ROLE ANALYTICS_INNOVATOR_ROLE;
GRANT SELECT ON TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI TO ROLE BUSINESS_ANALYST_ROLE;

-- ── POLICY_STORE schema (governor + engineer can read mapping table) ─────────
GRANT USAGE ON SCHEMA GOVERNANCE_CA_DEMO.POLICY_STORE TO ROLE DATA_GOVERNOR_ROLE;
GRANT USAGE ON SCHEMA GOVERNANCE_CA_DEMO.POLICY_STORE TO ROLE DATA_ENGINEER_ROLE;
GRANT SELECT ON TABLE GOVERNANCE_CA_DEMO.POLICY_STORE.ROW_POLICY_MAP TO ROLE DATA_GOVERNOR_ROLE;
GRANT SELECT ON TABLE GOVERNANCE_CA_DEMO.POLICY_STORE.ROW_POLICY_MAP TO ROLE DATA_ENGINEER_ROLE;

-- ── ANALYTICS_INNOVATOR: gets own sandbox schema to demo separation of duties ──
-- They can CREATE schemas in GOVERNANCE_CA_DEMO but cannot touch PROTECTED
GRANT CREATE SCHEMA ON DATABASE GOVERNANCE_CA_DEMO TO ROLE ANALYTICS_INNOVATOR_ROLE;

-- ── FACETS_DEV: DATA_GOVERNOR + DATA_ENGINEER read access to source ──────────
GRANT USAGE ON DATABASE FACETS_DEV TO ROLE DATA_GOVERNOR_ROLE;
GRANT USAGE ON DATABASE FACETS_DEV TO ROLE DATA_ENGINEER_ROLE;
GRANT USAGE ON ALL SCHEMAS IN DATABASE FACETS_DEV TO ROLE DATA_GOVERNOR_ROLE;
GRANT USAGE ON ALL SCHEMAS IN DATABASE FACETS_DEV TO ROLE DATA_ENGINEER_ROLE;
GRANT SELECT ON ALL TABLES IN DATABASE FACETS_DEV TO ROLE DATA_GOVERNOR_ROLE;
GRANT SELECT ON ALL TABLES IN DATABASE FACETS_DEV TO ROLE DATA_ENGINEER_ROLE;

-- =============================================================================
-- SETUP COMPLETE
-- Verify with:
--   DESCRIBE TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI;
--   SELECT COLUMN_NAME, TAG_VALUE FROM TABLE(
--     GOVERNANCE_CA_DEMO.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
--       'GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI','table')) WHERE TAG_NAME='DATA_CLASSIFICATION';
--   SELECT * FROM GOVERNANCE_CA_DEMO.POLICY_STORE.ROW_POLICY_MAP;
-- Next: Run 02_discovery_demo.sql and 03_security_demo.sql
-- =============================================================================
