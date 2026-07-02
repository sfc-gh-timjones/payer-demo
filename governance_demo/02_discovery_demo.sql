-- =============================================================================
-- FILE: 02_discovery_demo.sql
-- PURPOSE: CalOptima RFP 26-038 | Topic 4 + Topic 5 — Live Demo
--          Walk-through: Tags → Column-Level Masking → Row-Level Security
--
-- TABLE: GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
--        ~92,101 rows | DSNP: 30,866 | MEDCAID: 30,642 | COMM: 30,593
--
-- SETUP REFERENCE: 01_governance_setup.sql
--   Classification tag + profile:  Section B
--   AI classification run (clone): Section C
--   Masking policies (STRING/DATE): Section D
--   Policies attached to tag:      Section E
--   Manual PHI tags on MEMBER_PHI: Section G
--   Row access policy:             Section H
-- =============================================================================

USE DATABASE GOVERNANCE_CA_DEMO;
USE SCHEMA PROTECTED;
USE WAREHOUSE WH_XS;


-- =============================================================================
-- PART 1: TAGS — SNOWFLAKE AUTOMATICALLY IDENTIFIES SENSITIVE DATA
-- "Before we enforce anything, we need to know what's sensitive.
--  Snowflake's AI scanned every column and assigned a classification level
--  automatically. Let's look at the raw data first, then see what was found."
-- =============================================================================

-- Step 1a: Show the raw problem — PHI is fully exposed with no controls
USE ROLE ACCOUNTADMIN;

SELECT
    MEME_ID,
    MEME_LAST_NAME,
    MEME_FIRST_NAME,
    MEME_DOB,
    MEME_SEX,
    MECD_AID_CD,       -- Medi-Cal aid code — HIPAA PHI
    MECD_BIC,          -- Medi-Cal beneficiary ID — HIPAA PHI
    MEME_MCTR_TYPE,
    ACTIVE_PCP_NAME
FROM MEMBER_PHI
ORDER BY MEME_ID
LIMIT 10;

-- Step 1b: Show the DATA_CLASSIFICATION tags applied by setup
-- (01_governance_setup.sql Section C ran SYSTEM$CLASSIFY with auto_tag: true)
-- Tags are already on the clone — no need to run classification live
USE DATABASE zFACETS_DEV_CLONE;

SELECT
    COLUMN_NAME,
    TAG_VALUE AS classification_level
FROM TABLE(
    INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
        'zFACETS_DEV_CLONE.SILVER.MEMBER', 'table'
    )
)
WHERE TAG_NAME = 'DATA_CLASSIFICATION'
ORDER BY
    CASE TAG_VALUE
        WHEN 'PII'        THEN 1
        WHEN 'RESTRICTED' THEN 2
        WHEN 'SENSITIVE'  THEN 3
        WHEN 'INTERNAL'   THEN 4
        WHEN 'PUBLIC'     THEN 5
    END,
    COLUMN_NAME;
-- Talking point: Snowflake scanned 29 columns automatically and labeled every
-- HIPAA PHI element. No business rules written. No manual column cataloging.

-- Step 1c: Tag propagation — labels follow data through CTAS automatically
-- Talking point: engineers cannot create untagged PHI copies
USE ROLE DATA_ENGINEER_ROLE;

CREATE OR REPLACE TABLE zFACETS_DEV_CLONE.SILVER.MEMBER_ANALYTICS_COPY
    AS SELECT * FROM zFACETS_DEV_CLONE.SILVER.MEMBER;

USE ROLE ACCOUNTADMIN;

SELECT
    COLUMN_NAME,
    TAG_VALUE AS classification_level
FROM TABLE(
    zFACETS_DEV_CLONE.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
        'zFACETS_DEV_CLONE.SILVER.MEMBER_ANALYTICS_COPY', 'table'
    )
)
WHERE TAG_NAME = 'DATA_CLASSIFICATION'
ORDER BY
    CASE TAG_VALUE
        WHEN 'PII' THEN 1 WHEN 'RESTRICTED' THEN 2
        WHEN 'SENSITIVE' THEN 3 WHEN 'INTERNAL' THEN 4
    END, COLUMN_NAME;
-- Audience sees: all DATA_CLASSIFICATION tags propagated to the copy automatically.
-- Zero manual tagging. The tag was created with PROPAGATE = ON_DEPENDENCY_AND_DATA_MOVEMENT.


-- =============================================================================
-- PART 2: COLUMN-LEVEL MASKING
-- "Now that we've tagged the data, the masking policies enforce automatically.
--  Every role runs the exact same SELECT — Snowflake handles the rest."
--
-- HOW TO RUN:
--   1. Uncomment ONE USE ROLE line below
--   2. Run that line to switch roles
--   3. Run the SELECT query beneath it
--   4. Repeat with different roles to compare results
-- =============================================================================

USE DATABASE GOVERNANCE_CA_DEMO;
USE SCHEMA PROTECTED;

-- ── Step 1: Switch to the role you want to test ───────────────────────────────

-- USE ROLE ACCOUNTADMIN;               -- Full PHI — all columns unmasked, all plan types
-- USE ROLE DATA_ENGINEER_ROLE;         -- Full PHI — same as admin (pipeline engineers need raw data)
-- USE ROLE ANALYTICS_INNOVATOR_ROLE;   -- Names → J*****, DOB → year only, Medi-Cal IDs → *** PHI REDACTED ***
-- USE ROLE BUSINESS_ANALYST_ROLE;      -- All PHI → *** SENSITIVE *** or NULL, COMM rows only

-- ── Step 2: Run this query ────────────────────────────────────────────────────
-- Same SQL every time — Snowflake applies masking transparently based on current role

SELECT
    MEME_ID,
    MEME_LAST_NAME,       -- SENSITIVE  → full | J****** | *** SENSITIVE ***
    MEME_FIRST_NAME,      -- SENSITIVE  → full | J****** | *** SENSITIVE ***
    MEME_DOB,             -- RESTRICTED → exact date | year only (HIPAA §164.514(b)) | NULL
    MEME_SEX,             -- SENSITIVE  → full | M* | *** SENSITIVE ***
    MECD_AID_CD,          -- PII        → full | *** PHI REDACTED *** | *** PHI REDACTED ***
    MECD_BIC,             -- PII        → full | *** PHI REDACTED *** | *** PHI REDACTED ***
    MEME_MCTR_TYPE,       -- INTERNAL   → visible for all roles
    ACTIVE_PCP_NAME       -- SENSITIVE  → full | D****** | *** SENSITIVE ***
FROM MEMBER_PHI
ORDER BY MEME_ID
LIMIT 10;

-- Talking point: same SQL — no WHERE clauses, no CASE statements, no app-level logic.
-- Masking is enforced at the Snowflake layer, invisible to the analyst, impossible to bypass.


-- =============================================================================
-- PART 3: ROW-LEVEL SECURITY — PLAN POPULATION ACCESS CONTROL
-- "Column masking controls what you SEE in a row.
--  Row-level security controls which populations you can ACCESS at all."
-- =============================================================================

USE DATABASE GOVERNANCE_CA_DEMO;
USE SCHEMA PROTECTED;

-- Show the row access policy mapping so the audience understands the logic
USE ROLE ACCOUNTADMIN;

SELECT * FROM GOVERNANCE_CA_DEMO.POLICY_STORE.ROW_POLICY_MAP
ORDER BY ROLE, VISIBLE_PLAN_TYPE;
-- Plan types:
--   COMM    → Commercial managed care (CalOptima Access HMO/PPO)
--   DSNP    → Dual Special Needs Plan (Medicare + Medi-Cal dual-eligible)
--   MEDCAID → Medi-Cal / California Medicaid (heightened privacy — reveals low-income status)

-- ── Switch role, then run the row count query below ───────────────────────────

-- USE ROLE ACCOUNTADMIN;               -- Sees ALL plan types: COMM + DSNP + MEDCAID
-- USE ROLE DATA_ENGINEER_ROLE;         -- Sees ALL plan types
-- USE ROLE ANALYTICS_INNOVATOR_ROLE;   -- MEDCAID rows vanish entirely
-- USE ROLE BUSINESS_ANALYST_ROLE;      -- Only COMM rows visible

SELECT MEME_MCTR_TYPE, COUNT(*) AS member_count
FROM MEMBER_PHI
GROUP BY MEME_MCTR_TYPE
ORDER BY member_count DESC;
-- ACCOUNTADMIN / DATA_ENGINEER: DSNP ~30,866 | MEDCAID ~30,642 | COMM ~30,593
-- ANALYTICS_INNOVATOR:          DSNP + COMM only — MEDCAID row is gone entirely
-- BUSINESS_ANALYST:             COMM only — ~30,593 rows

-- Confirm MEDCAID is invisible to Analytics Innovator (run as that role)
-- USE ROLE ANALYTICS_INNOVATOR_ROLE;
SELECT COUNT(*) AS medcaid_rows
FROM MEMBER_PHI
WHERE MEME_MCTR_TYPE = 'MEDCAID';
-- Returns 0 — row policy fires silently. No error. The analyst doesn't know MEDCAID exists.
-- HIPAA minimum necessary: access is restricted without revealing what was restricted.


-- =============================================================================
-- Next: Run 03_schema_access_demo.sql for:
--   Managed access schema (separation of duties)
--   Analytics Innovator sandbox
--   Instant REVOKE demo
--   Pre-built audit log
-- =============================================================================
