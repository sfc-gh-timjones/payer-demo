-- =============================================================================
-- FILE: 01_governance_setup.sql
-- PURPOSE: CalOptima RFP 26-038 | Topic 4 (Data Governance) + Topic 5 (Security)
--          Teardown + rebuild — safe to run repeatedly. Every execution drops all
--          demo objects and rebuilds from scratch. Run top-to-bottom as ACCOUNTADMIN.
--
-- ROLES (3 demo roles; ACCOUNTADMIN plays the admin/governance persona):
--   ACCOUNTADMIN          → Full access, all PHI, all plan types (admin view)
--   DATA_ENGINEER_ROLE    → Full PHI access, all plan types, no DDL on PROTECTED
--   ANALYTICS_INNOVATOR_ROLE → Partial masking, COMM + DSNP only (no Medi-Cal)
--   BUSINESS_ANALYST_ROLE → Full masking, COMM only
--
-- DEMO SCRIPTS REFERENCE (by section):
--   Section A → Roles, databases, warehouses, clone
--   Section B → DATA_CLASSIFICATION tag + classification profile
--   Section C → AI classification run on zFACETS_DEV_CLONE
--   Section D → Tag-based masking policies (STRING / DATE / TIMESTAMP)
--   Section E → Attach masking policies to tag
--   Section F → Manual PII/PHI tags on zFACETS_DEV_CLONE.SILVER.MEMBER
--   Section G → Row access policy (MEME_MCTR_TYPE plan-type filter)
--   Section H → Row access policy (MEME_MCTR_TYPE plan-type filter)
--   Section I → Role grants
--
-- DATA TABLE:   zFACETS_DEV_CLONE.SILVER.MEMBER — governance policies applied directly
-- POLICY DB:    GOVERNANCE_CA_DEMO.POLICY_STORE — tag, masking policies, row access policy
-- CLONE:        zFACETS_DEV_CLONE (zero-copy clone of FACETS_DEV)
-- =============================================================================


-- =============================================================================
-- TEARDOWN — runs first on every execution
-- Drops all CalOptima governance demo objects. Safe to run on first run (all
-- statements guarded with IF EXISTS). Dropping the databases cascades and removes
-- all schemas, tables, tags, masking policies, row access policies, functions,
-- and classification profiles contained within them — no manual detaching needed.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Demo databases (cascade drops all objects inside)
-- zFACETS_DEV_CLONE must drop FIRST — its SILVER schema holds tag references
-- from GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION. Dropping the tag
-- owner (GOVERNANCE_CA_DEMO) while those references exist will fail.
DROP DATABASE IF EXISTS zFACETS_DEV_CLONE;
DROP DATABASE IF EXISTS GOVERNANCE_CA_DEMO;

-- Demo roles (drop in leaf-first order to avoid hierarchy conflicts)
DROP ROLE IF EXISTS BUSINESS_ANALYST_ROLE;
DROP ROLE IF EXISTS ANALYTICS_INNOVATOR_ROLE;
DROP ROLE IF EXISTS DATA_ENGINEER_ROLE;

SELECT 'Teardown complete — CalOptima governance demo objects removed. Rebuilding...' AS status;


-- =============================================================================
-- BUILD
-- =============================================================================


-- =============================================================================
-- SECTION A: ROLES, DATABASES, WAREHOUSES, CLONE
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WH_XS;

-- ── Demo roles ───────────────────────────────────────────────────────────────
-- ACCOUNTADMIN is used for the "admin view" persona in demo scripts.
-- 3 additional roles cover the engineer → analyst → business analyst gradient.
CREATE ROLE IF NOT EXISTS DATA_ENGINEER_ROLE
    COMMENT = 'Full PHI access — builds and validates pipelines. No DDL on governed PROTECTED schema.';
CREATE ROLE IF NOT EXISTS ANALYTICS_INNOVATOR_ROLE
    COMMENT = 'Partial masking. COMM + DSNP rows only — Medi-Cal hidden. Owns analytics sandbox schema.';
CREATE ROLE IF NOT EXISTS BUSINESS_ANALYST_ROLE
    COMMENT = 'Read-only. Commercial (COMM) members only. All PHI columns fully masked.';

-- ── Role hierarchy ───────────────────────────────────────────────────────────
-- ACCOUNTADMIN → DATA_ENGINEER → ANALYTICS_INNOVATOR → BUSINESS_ANALYST
GRANT ROLE DATA_ENGINEER_ROLE        TO ROLE SYSADMIN;      -- ACCOUNTADMIN inherits via SYSADMIN
GRANT ROLE ANALYTICS_INNOVATOR_ROLE  TO ROLE DATA_ENGINEER_ROLE;
GRANT ROLE BUSINESS_ANALYST_ROLE     TO ROLE ANALYTICS_INNOVATOR_ROLE;

-- Assign all three roles to the ADMIN user for USE ROLE switching in demo scripts
GRANT ROLE DATA_ENGINEER_ROLE        TO USER ADMIN;
GRANT ROLE ANALYTICS_INNOVATOR_ROLE  TO USER ADMIN;
GRANT ROLE BUSINESS_ANALYST_ROLE     TO USER ADMIN;

-- ── Warehouse access ─────────────────────────────────────────────────────────
GRANT USAGE ON WAREHOUSE WH_XS TO ROLE DATA_ENGINEER_ROLE;
GRANT USAGE ON WAREHOUSE WH_XS TO ROLE ANALYTICS_INNOVATOR_ROLE;
GRANT USAGE ON WAREHOUSE WH_XS TO ROLE BUSINESS_ANALYST_ROLE;

-- ── Zero-copy clone of FACETS_DEV for the discovery/classification demo ──────
-- Isolated from live Bronze/Silver — classification does not touch production.
CREATE OR REPLACE DATABASE zFACETS_DEV_CLONE CLONE FACETS_DEV;

-- ── Governance database ───────────────────────────────────────────────────────
CREATE DATABASE IF NOT EXISTS GOVERNANCE_CA_DEMO;

-- POLICY_STORE: owns the tag, masking policies, row access policy, and audit table
CREATE SCHEMA IF NOT EXISTS GOVERNANCE_CA_DEMO.POLICY_STORE
    COMMENT = 'Governance policy objects: DATA_CLASSIFICATION tag, masking policies, row access policy, role mapping table.';


-- =============================================================================
-- SECTION B: DATA_CLASSIFICATION TAG + CALOPTIMA CLASSIFICATION PROFILE
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE GOVERNANCE_CA_DEMO;
USE SCHEMA POLICY_STORE;

-- ── DATA_CLASSIFICATION tag ──────────────────────────────────────────────────
-- PROPAGATE = ON_DEPENDENCY_AND_DATA_MOVEMENT:
--   Classification labels follow data automatically through CTAS, clones, and
--   view dependencies. Engineers cannot create untagged PHI copies.
CREATE OR REPLACE TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION
    ALLOWED_VALUES 'PII', 'RESTRICTED', 'SENSITIVE', 'INTERNAL', 'PUBLIC'
    COMMENT = 'CalOptima enterprise PHI/PII classification. HIPAA/CCPA/GDPR. Propagates on dependency and data movement.'
    PROPAGATE = ON_DEPENDENCY_AND_DATA_MOVEMENT;

-- ── CALOPTIMA_CLASSIFICATION_PROFILE ────────────────────────────────────────
-- Snowflake AI maps semantic categories to DATA_CLASSIFICATION tag values.
-- Applied to zFACETS_DEV_CLONE — used for the live SYSTEM$CLASSIFY discovery demo.
--
-- HOW SNOWFLAKE CLASSIFICATION WORKS (profile-driven model):
--   Snowflake treats automatic sensitive data classification as profile-driven rather
--   than something that happens by default. To enable ongoing automatic scanning, you
--   create a CLASSIFICATION_PROFILE and attach it to a database or schema. The profile
--   controls:
--     • Whether tags are auto-applied after classification (auto_tag)
--     • Which objects are included (tables, views via classify_views)
--     • How often reclassification happens (maximum_classification_validity_days)
--     • Minimum object age before first scan (minimum_object_age_for_classification_days)
--     • Any custom classifiers or tag mappings (tag_map / column_tag_map)
--   Manual/one-time classification still exists separately for spot checks or testing
--   (e.g. SYSTEM$CLASSIFY with auto_tag: false — see 02_discovery_demo.sql Beat 2).
--   In Snowsight / Trust Center the same concept applies: the UI saves those settings
--   as a classification profile behind the scenes.
--
-- Compliance mapping:
--   PII        → GDPR Art.4(1), HIPAA PHI, CCPA Personal Information
--   RESTRICTED → GDPR Art.9 (special categories), HIPAA limited dataset
--   SENSITIVE  → GDPR Art.6 (legitimate interest), HIPAA §164.514(b) safe harbor
--   INTERNAL   → SOX controls, low-risk business data
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


-- =============================================================================
-- SECTION C: AI CLASSIFICATION APPLIED TO CLONE
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Attach classification profile to the clone database (auto-tags on schedule)
ALTER DATABASE zFACETS_DEV_CLONE
    SET CLASSIFICATION_PROFILE =
        'GOVERNANCE_CA_DEMO.POLICY_STORE.CALOPTIMA_CLASSIFICATION_PROFILE';

-- Grant clone access to DATA_ENGINEER_ROLE for the tag-propagation demo step
GRANT USAGE ON DATABASE zFACETS_DEV_CLONE               TO ROLE DATA_ENGINEER_ROLE;
GRANT USAGE ON ALL SCHEMAS IN DATABASE zFACETS_DEV_CLONE TO ROLE DATA_ENGINEER_ROLE;
GRANT SELECT ON ALL TABLES IN DATABASE zFACETS_DEV_CLONE TO ROLE DATA_ENGINEER_ROLE;
GRANT CREATE TABLE ON SCHEMA zFACETS_DEV_CLONE.SILVER    TO ROLE DATA_ENGINEER_ROLE;

-- Run AI classification: scans MEMBER table, applies DATA_CLASSIFICATION tags
-- (auto_tag: true — this is what the demo's discovery beat shows the results of)
CALL SYSTEM$CLASSIFY(
    'zFACETS_DEV_CLONE.SILVER.MEMBER',
    'GOVERNANCE_CA_DEMO.POLICY_STORE.CALOPTIMA_CLASSIFICATION_PROFILE'
);


-- =============================================================================
-- SECTION D: TAG-BASED MASKING POLICIES
--
-- Three policies cover all column data types in MEMBER_PHI.
-- Attached to the DATA_CLASSIFICATION tag once (Section E) — every tagged column
-- is automatically masked. No per-column ALTER TABLE required.
--
-- Design: SPLIT PATTERN + IS_ROLE_IN_SESSION (data-governance best practices)
--
--   SPLIT PATTERN: The "full PHI access" condition is extracted into one memoizable
--   function (phi_full_access). All three masking policies call this function
--   instead of duplicating the role list. Adding or revoking a full-access role
--   requires editing ONE function — all policies inherit the change immediately.
--
--   CURRENT_ROLE() for explicit USE ROLE demo switching:
--   In this demo, roles are switched with USE ROLE commands. CURRENT_ROLE() returns
--   the exact active role, making masking deterministic during a live walk-through.
--   phi_full_access() uses CURRENT_ROLE() IN (...) — simple and reliable.
--
-- Role privilege matrix:
-- ┌──────────────────────────┬─────────────┬──────────────┬───────────────────┬──────────────────┐
-- │ Classification           │ ACCOUNTADMIN│ DATA_ENGINEER│ ANALYTICS_INNOVATOR│ BUSINESS_ANALYST │
-- ├──────────────────────────┼─────────────┼──────────────┼───────────────────┼──────────────────┤
-- │ PII   (MECD_AID_CD/BIC)  │ Full        │ Full         │ ***PHI REDACTED***│ ***PHI REDACTED**│
-- │ RESTRICTED (DOB)         │ Full        │ Full         │ Year only         │ NULL             │
-- │ SENSITIVE (name, sex)    │ Full        │ Full         │ First initial+*** │ ***SENSITIVE***  │
-- │ INTERNAL                 │ Full        │ Full         │ Full              │ Full             │
-- └──────────────────────────┴─────────────┴──────────────┴───────────────────┴──────────────────┘
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE GOVERNANCE_CA_DEMO;
USE SCHEMA POLICY_STORE;

-- ── Memoizable helper: full PHI access condition (split pattern) ─────────────
-- Single source of truth for which roles see cleartext PHI.
-- All three masking policies call this function — role changes require ONE edit here.
CREATE OR REPLACE FUNCTION GOVERNANCE_CA_DEMO.POLICY_STORE.phi_full_access()
RETURNS BOOLEAN
MEMOIZABLE
AS
$$
    CURRENT_ROLE() IN ('ACCOUNTADMIN', 'DATA_ENGINEER_ROLE')
$$;

-- ── STRING masking policy ────────────────────────────────────────────────────
-- Covers: MEME_LAST/FIRST_NAME, SUBSCRIBER names, MEME_SEX, SEX_DESC,
--         MECD_AID_CD, MECD_BIC, ACTIVE_PCP_NAME, ACTIVE_PCP_NPI
CREATE OR REPLACE MASKING POLICY GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION_MASK_STRING
AS (VAL STRING) RETURNS STRING ->
CASE
    -- Full PHI access via split-pattern memoizable function (phi_full_access)
    -- IS_ROLE_IN_SESSION honours role hierarchy; CURRENT_ROLE() does not
    WHEN GOVERNANCE_CA_DEMO.POLICY_STORE.phi_full_access()
        THEN VAL
    -- ANALYTICS_INNOVATOR: partial masking — enough for analytics, not full PHI
    WHEN CURRENT_ROLE() = 'ANALYTICS_INNOVATOR_ROLE' THEN
        CASE SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION')
            WHEN 'PII'        THEN '*** PHI REDACTED ***'           -- Medi-Cal IDs fully redacted
            WHEN 'RESTRICTED' THEN CONCAT('***-', RIGHT(VAL, 4))   -- last 4 chars only
            WHEN 'SENSITIVE'  THEN CONCAT(LEFT(VAL, 1), REPEAT('*', GREATEST(LENGTH(VAL) - 1, 0)))
            ELSE VAL
        END
    -- BUSINESS_ANALYST: all PHI/PII fully opaque — minimum necessary
    WHEN CURRENT_ROLE() = 'BUSINESS_ANALYST_ROLE' THEN
        CASE SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION')
            WHEN 'PII'        THEN '*** PHI REDACTED ***'
            WHEN 'RESTRICTED' THEN '*** RESTRICTED ***'
            WHEN 'SENSITIVE'  THEN '*** SENSITIVE ***'
            ELSE VAL
        END
    ELSE '*** ACCESS DENIED ***'
END
COMMENT = 'STRING masking on DATA_CLASSIFICATION tag. Split pattern (phi_full_access). CURRENT_ROLE() for explicit demo USE ROLE switching. HIPAA §164.514 / GDPR Art.25.';

-- ── DATE masking policy ──────────────────────────────────────────────────────
-- Covers: MEME_DOB, SUBSCRIBER_DOB (RESTRICTED — date of birth)
-- HIPAA §164.514(b) safe harbor: dates generalized to year satisfies de-identification
CREATE OR REPLACE MASKING POLICY GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION_MASK_DATE
AS (VAL DATE) RETURNS DATE ->
CASE
    WHEN GOVERNANCE_CA_DEMO.POLICY_STORE.phi_full_access()
        THEN VAL
    WHEN CURRENT_ROLE() = 'ANALYTICS_INNOVATOR_ROLE' THEN
        CASE SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION')
            WHEN 'PII'        THEN NULL
            WHEN 'RESTRICTED' THEN DATE_TRUNC('YEAR', VAL)  -- HIPAA §164.514(b) safe harbor
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
COMMENT = 'DATE masking on DATA_CLASSIFICATION tag. Split pattern (phi_full_access). HIPAA §164.514(b): RESTRICTED → year-only for Analytics Innovator, NULL for Business Analyst.';

-- ── TIMESTAMP masking policy ─────────────────────────────────────────────────
-- Covers: BRONZE_UPDATED_AT (TIMESTAMP_NTZ), SILVER_LOADED_AT (TIMESTAMP_LTZ)
-- These are INTERNAL metadata — masking policy exists because tag-based masking
-- requires one policy per data type present in tagged columns.
CREATE OR REPLACE MASKING POLICY GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION_MASK_TIMESTAMP
AS (VAL TIMESTAMP_NTZ) RETURNS TIMESTAMP_NTZ ->
CASE
    WHEN GOVERNANCE_CA_DEMO.POLICY_STORE.phi_full_access()
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
COMMENT = 'TIMESTAMP_NTZ masking on DATA_CLASSIFICATION tag. Split pattern (phi_full_access).';


-- =============================================================================
-- SECTION E: ATTACH MASKING POLICIES TO THE TAG
--
-- One-time attachment: every column tagged DATA_CLASSIFICATION is now masked
-- automatically according to its data type. No per-column ALTER TABLE needed.
-- New PHI columns added in future classification runs are masked immediately.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE GOVERNANCE_CA_DEMO;
USE SCHEMA POLICY_STORE;

ALTER TAG DATA_CLASSIFICATION SET MASKING POLICY DATA_CLASSIFICATION_MASK_STRING;
ALTER TAG DATA_CLASSIFICATION SET MASKING POLICY DATA_CLASSIFICATION_MASK_DATE;
ALTER TAG DATA_CLASSIFICATION SET MASKING POLICY DATA_CLASSIFICATION_MASK_TIMESTAMP;


-- =============================================================================
-- SECTION F: MANUAL PII/PHI TAGS ON zFACETS_DEV_CLONE.SILVER.MEMBER
--
-- Governance policies (masking + row access) are applied directly to the clone's
-- MEMBER table. No separate PHI table needed.
--
-- The AI classification profile (Section C) already tagged many columns.
-- Manual tags below guarantee key PHI columns fire reliably during the demo
-- regardless of AI confidence scores.
--
-- Column → Classification:
--   MEME_LAST_NAME, MEME_FIRST_NAME          SENSITIVE  — patient name (HIPAA PHI)
--   SUBSCRIBER_LAST_NAME, FIRST_NAME         SENSITIVE  — policyholder name
--   SEX_DESC, MEME_SEX                       SENSITIVE  — biological sex (HIPAA PHI)
--   ACTIVE_PCP_NAME                          SENSITIVE  — treating provider (HIPAA PHI)
--   MEME_DOB, SUBSCRIBER_DOB               RESTRICTED  — date of birth (HIPAA §164.514(b))
--   MECD_AID_CD                                  PII   — Medi-Cal aid code (HIPAA PHI)
--   MECD_BIC                                     PII   — Medi-Cal beneficiary ID (HIPAA PHI)
-- =============================================================================

USE ROLE ACCOUNTADMIN;


-- PII: Medi-Cal identifiers — most sensitive HIPAA PHI in the member record
ALTER TABLE zFACETS_DEV_CLONE.SILVER.MEMBER MODIFY COLUMN MECD_AID_CD
    SET TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION = 'PII';
ALTER TABLE zFACETS_DEV_CLONE.SILVER.MEMBER MODIFY COLUMN MECD_BIC
    SET TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION = 'PII';

-- RESTRICTED: Dates of birth — HIPAA §164.514(b) requires generalization
ALTER TABLE zFACETS_DEV_CLONE.SILVER.MEMBER MODIFY COLUMN MEME_DOB
    SET TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION = 'RESTRICTED';
ALTER TABLE zFACETS_DEV_CLONE.SILVER.MEMBER MODIFY COLUMN SUBSCRIBER_DOB
    SET TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION = 'RESTRICTED';

-- SENSITIVE: Names and gender — PHI under HIPAA, special category under GDPR
ALTER TABLE zFACETS_DEV_CLONE.SILVER.MEMBER MODIFY COLUMN MEME_LAST_NAME
    SET TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION = 'SENSITIVE';
ALTER TABLE zFACETS_DEV_CLONE.SILVER.MEMBER MODIFY COLUMN MEME_FIRST_NAME
    SET TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION = 'SENSITIVE';
ALTER TABLE zFACETS_DEV_CLONE.SILVER.MEMBER MODIFY COLUMN SUBSCRIBER_LAST_NAME
    SET TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION = 'SENSITIVE';
ALTER TABLE zFACETS_DEV_CLONE.SILVER.MEMBER MODIFY COLUMN SUBSCRIBER_FIRST_NAME
    SET TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION = 'SENSITIVE';
ALTER TABLE zFACETS_DEV_CLONE.SILVER.MEMBER MODIFY COLUMN MEME_SEX
    SET TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION = 'SENSITIVE';
ALTER TABLE zFACETS_DEV_CLONE.SILVER.MEMBER MODIFY COLUMN SEX_DESC
    SET TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION = 'SENSITIVE';
ALTER TABLE zFACETS_DEV_CLONE.SILVER.MEMBER MODIFY COLUMN ACTIVE_PCP_NAME
    SET TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION = 'SENSITIVE';


-- =============================================================================
-- SECTION G: ROW ACCESS POLICY — PLAN TYPE FILTER
--
-- Filters zFACETS_DEV_CLONE.SILVER.MEMBER rows by MEME_MCTR_TYPE based on role.
-- Plan types: DSNP (30,866 rows) | MEDCAID (30,642 rows) | COMM (30,593 rows)
--
-- Role → Visible plan types:
--   ACCOUNTADMIN / DATA_ENGINEER  → ALL (DSNP + MEDCAID + COMM)
--   ANALYTICS_INNOVATOR_ROLE      → DSNP + COMM (Medi-Cal hidden)
--   BUSINESS_ANALYST_ROLE         → COMM only
--
-- Story: Business analysts running commercial plan analytics should never access
-- Medi-Cal (MEDCAID) or DSNP members — heightened HIPAA regulatory sensitivity.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE GOVERNANCE_CA_DEMO;
USE SCHEMA POLICY_STORE;

-- Plan type definitions (MEME_MCTR_TYPE values in MEMBER_PHI):
--   COMM    → Commercial — employer-sponsored or individual managed care (CalOptima Access)
--   DSNP    → Dual Special Needs Plan — Medicare + Medi-Cal dual-eligible members
--   MEDCAID → Medi-Cal — California Medicaid; heightened privacy sensitivity because
--             enrollment reveals low-income or disability status (HIPAA minimum necessary)

-- Role → plan type mapping table (driven from data, not hardcoded in policy)
CREATE OR REPLACE TABLE ROW_POLICY_MAP (
    ROLE               VARCHAR(100)  NOT NULL,
    VISIBLE_PLAN_TYPE  VARCHAR(20)   NOT NULL,
    NOTES              VARCHAR(200)
);

INSERT INTO ROW_POLICY_MAP VALUES
    ('DATA_ENGINEER_ROLE',        'ALL',    'Full access — pipeline engineers'),
    ('ANALYTICS_INNOVATOR_ROLE',  'COMM',   'Commercial HMO members'),
    ('ANALYTICS_INNOVATOR_ROLE',  'DSNP',   'Dual-eligible Special Needs Plan members'),
    ('BUSINESS_ANALYST_ROLE',     'COMM',   'Commercial members only — Medi-Cal and DSNP restricted');

-- Row access policy on MEME_MCTR_TYPE
CREATE OR REPLACE ROW ACCESS POLICY GOVERNANCE_CA_DEMO.POLICY_STORE.MEMBER_PLAN_ACCESS_POLICY
    AS (PLAN_TYPE VARCHAR) RETURNS BOOLEAN ->
    CASE
        -- CURRENT_ROLE() matches the explicitly-set USE ROLE for demo switching
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'DATA_ENGINEER_ROLE')
            THEN TRUE
        -- Mapping table lookup: compare the active role name against entitlement rows
        ELSE EXISTS (
            SELECT 1
            FROM GOVERNANCE_CA_DEMO.POLICY_STORE.ROW_POLICY_MAP rp
            WHERE rp.ROLE = CURRENT_ROLE()
              AND (rp.VISIBLE_PLAN_TYPE = 'ALL' OR rp.VISIBLE_PLAN_TYPE = PLAN_TYPE)
        )
    END
    COMMENT = 'Limits MEMBER_PHI rows by MEME_MCTR_TYPE per role. Entitlement table (ROW_POLICY_MAP) controls analyst tiers. HIPAA minimum necessary standard.';

ALTER TABLE zFACETS_DEV_CLONE.SILVER.MEMBER
    ADD ROW ACCESS POLICY GOVERNANCE_CA_DEMO.POLICY_STORE.MEMBER_PLAN_ACCESS_POLICY
    ON (MEME_MCTR_TYPE);


-- =============================================================================
-- SECTION H: ROLE GRANTS
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- ── GOVERNANCE_CA_DEMO: all roles need the database for POLICY_STORE access ───
GRANT USAGE ON DATABASE GOVERNANCE_CA_DEMO TO ROLE DATA_ENGINEER_ROLE;
GRANT USAGE ON DATABASE GOVERNANCE_CA_DEMO TO ROLE ANALYTICS_INNOVATOR_ROLE;
GRANT USAGE ON DATABASE GOVERNANCE_CA_DEMO TO ROLE BUSINESS_ANALYST_ROLE;

-- ── POLICY_STORE: engineer reads the mapping table ────────────────────────────
GRANT USAGE ON SCHEMA GOVERNANCE_CA_DEMO.POLICY_STORE TO ROLE DATA_ENGINEER_ROLE;
GRANT SELECT ON TABLE GOVERNANCE_CA_DEMO.POLICY_STORE.ROW_POLICY_MAP TO ROLE DATA_ENGINEER_ROLE;

-- ── Clone: analyst roles need access to query SILVER.MEMBER ──────────────────
-- DATA_ENGINEER_ROLE already granted in Section C
GRANT USAGE ON DATABASE zFACETS_DEV_CLONE              TO ROLE ANALYTICS_INNOVATOR_ROLE;
GRANT USAGE ON DATABASE zFACETS_DEV_CLONE              TO ROLE BUSINESS_ANALYST_ROLE;
GRANT USAGE ON SCHEMA zFACETS_DEV_CLONE.SILVER         TO ROLE ANALYTICS_INNOVATOR_ROLE;
GRANT USAGE ON SCHEMA zFACETS_DEV_CLONE.SILVER         TO ROLE BUSINESS_ANALYST_ROLE;
GRANT SELECT ON TABLE zFACETS_DEV_CLONE.SILVER.MEMBER  TO ROLE ANALYTICS_INNOVATOR_ROLE;
GRANT SELECT ON TABLE zFACETS_DEV_CLONE.SILVER.MEMBER  TO ROLE BUSINESS_ANALYST_ROLE;

-- ── Analytics Innovator: own sandbox schema in GOVERNANCE_CA_DEMO ─────────────
GRANT CREATE SCHEMA ON DATABASE GOVERNANCE_CA_DEMO TO ROLE ANALYTICS_INNOVATOR_ROLE;

-- =============================================================================
-- SECTION J: PRE-BUILT AUDIT ACCESS HISTORY TABLE
-- Materialized snapshot of the last 90 days from ACCOUNT_USAGE.ACCESS_HISTORY.
-- ACCESS_HISTORY has a ~30-min ingestion lag and can be slow to query live.
-- Built at setup time so 03_schema_access_demo.sql can SELECT from it instantly.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE GOVERNANCE_CA_DEMO;
USE SCHEMA POLICY_STORE;

-- ACCESS_HISTORY has query/object metadata; QUERY_HISTORY has role + query text.
-- JOIN them to get the full picture in one table.
CREATE OR REPLACE TABLE ACCOUNT_ACCESS_HISTORY AS
SELECT
    ah.QUERY_ID,
    ah.QUERY_START_TIME,
    qh.USER_NAME,
    qh.ROLE_NAME,
    LEFT(qh.QUERY_TEXT, 200)                             AS query_preview,
    qh.EXECUTION_STATUS,
    ah.DIRECT_OBJECTS_ACCESSED[0]:objectName::STRING     AS first_object_accessed,
    ah.DIRECT_OBJECTS_ACCESSED[0]:objectDomain::STRING   AS object_domain
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY ah
LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY qh
    ON ah.QUERY_ID = qh.QUERY_ID
WHERE ah.QUERY_START_TIME >= DATEADD('day', -90, CURRENT_TIMESTAMP())
ORDER BY ah.QUERY_START_TIME DESC;

GRANT SELECT ON TABLE GOVERNANCE_CA_DEMO.POLICY_STORE.ACCOUNT_ACCESS_HISTORY
    TO ROLE DATA_ENGINEER_ROLE;


-- =============================================================================
-- SETUP COMPLETE
-- Verify with:
--   SELECT COLUMN_NAME, TAG_VALUE
--   FROM TABLE(zFACETS_DEV_CLONE.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
--       'zFACETS_DEV_CLONE.SILVER.MEMBER','table'))
--   WHERE TAG_NAME = 'DATA_CLASSIFICATION';
--
--   SELECT * FROM GOVERNANCE_CA_DEMO.POLICY_STORE.ROW_POLICY_MAP;
--
-- Next: Run 02_discovery_demo.sql (tags → column masking → row-level security)
--       Run 03_schema_access_demo.sql (schema access, separation of duties, audit)
-- =============================================================================

USE ROLE ACCOUNTADMIN;
SELECT 'Setup complete — CalOptima governance demo deployed successfully.' AS status;
