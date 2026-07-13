-- =============================================================================
-- FILE: 02_discovery_demo.sql
-- PURPOSE: CalOptima RFP 26-038 | Topic 4 + Topic 5 — Live Demo
--          Walk-through: Tags → Column-Level Masking → Row-Level Security
--
-- DATABASE ARCHITECTURE:
--   zFACETS_DEV_CLONE.SILVER.MEMBER  — the demo table (governance applied here)
--   GOVERNANCE_CA_DEMO.POLICY_STORE  — tag, masking policies, row access policy
--
-- SETUP REFERENCES (01_governance_setup.sql):
--   Tags + classification:  Section B (line 106), Section C (line 200)
--   Masking policies:       Section D (line 225), Section E (line 352)
--   Manual PHI tags:        Section F (line 369)
--   Row access policy:      Section G (line 421)
--   Role grants:            Section H (line 481)
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;

USE DATABASE zFACETS_DEV_CLONE;
USE SCHEMA SILVER;
USE WAREHOUSE WH_XS;


-- =============================================================================
-- PART 1: TAGS — SNOWFLAKE AUTOMATICALLY IDENTIFIES SENSITIVE DATA
-- Setup ref: 01_governance_setup.sql Section B (line 106) — tag + profile
--            Section C (line 200) — SYSTEM$CLASSIFY run on clone
-- "Snowflake's AI scanned every column and assigned a classification level
--  automatically. Let's look at the raw data first, then see what was found."
-- =============================================================================

-- Step 1a: Show the raw problem — PHI is fully exposed with no controls
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
FROM MEMBER
ORDER BY MEME_ID
LIMIT 10;

-- Step 1b: Show the DATA_CLASSIFICATION tags applied by setup
SELECT
    COLUMN_NAME,
    TAG_VALUE AS classification_level
FROM TABLE(
    INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
        'MEMBER', 'table'
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
-- AI scanned 29 columns and labeled every HIPAA PHI element automatically.
-- No business rules written. No manual column cataloging.

-- Step 1c: Tag propagation — labels follow data through CTAS automatically
-- Setup ref: tag created with PROPAGATE = ON_DEPENDENCY_AND_DATA_MOVEMENT
--            (01_governance_setup.sql Section B, line ~129)
CREATE OR REPLACE TABLE MEMBER_COPY
    AS SELECT * FROM MEMBER;

SELECT
    COLUMN_NAME,
    TAG_VALUE AS classification_level
FROM TABLE(
    INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
        'MEMBER_COPY', 'table'
    )
)
WHERE TAG_NAME = 'DATA_CLASSIFICATION'
ORDER BY
    CASE TAG_VALUE
        WHEN 'PII' THEN 1 WHEN 'RESTRICTED' THEN 2
        WHEN 'SENSITIVE' THEN 3 WHEN 'INTERNAL' THEN 4
    END, COLUMN_NAME;
-- Tags propagated automatically — zero manual tagging required.


-- =============================================================================
-- PART 2: COLUMN-LEVEL MASKING
-- Setup ref: 01_governance_setup.sql Section D (line 225) — masking policies
--            Section E (line 352) — policies attached to tag
--            Section F (line 369) — manual PHI tags on MEMBER columns
-- "Every role runs the exact same SELECT — Snowflake handles the rest."
--
-- HOW TO RUN: Click the USE ROLE line for the role you want and run just that
-- line, then run the SELECT below. Repeat to compare views.
-- =============================================================================
-- Role privilege matrix:
-- ┌──────────────────────────┬─────────────┬──────────────┬───────────────────┬──────────────────┐
-- │ Classification           │ ACCOUNTADMIN│ DATA_ENGINEER│ ANALYTICS_INNOVATOR│ BUSINESS_ANALYST │
-- ├──────────────────────────┼─────────────┼──────────────┼───────────────────┼──────────────────┤
-- │ PII   (MECD_AID_CD/BIC)  │ Full        │ Full         │ ***PHI REDACTED***│ ***PHI REDACTED**│
-- │ RESTRICTED (DOB)         │ Full        │ Full         │ Year only         │ NULL             │
-- │ SENSITIVE (name, sex)    │ Full        │ Full         │ First initial+*** │ ***SENSITIVE***  │
-- │ INTERNAL                 │ Full        │ Full         │ Full              │ Full             │
-- └──────────────────────────┴─────────────┴──────────────┴───────────────────┴──────────────────┘

-- ── Switch to the role you want, then run the query below ────────────────────
--USE ROLE ACCOUNTADMIN;
USE ROLE DATA_ENGINEER_ROLE;
USE ROLE ANALYTICS_INNOVATOR_ROLE;
--USE ROLE BUSINESS_ANALYST_ROLE;

-- ── Same query every time — Snowflake applies masking based on current role ──
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
FROM MEMBER
ORDER BY MEME_ID
LIMIT 10;

-- Same SQL — no WHERE clauses, no CASE statements, no app-level logic.
-- Masking is enforced at the Snowflake layer, invisible to the analyst.


-- =============================================================================
-- PART 3: ROW-LEVEL SECURITY — PLAN POPULATION ACCESS CONTROL
-- Setup ref: 01_governance_setup.sql Section G (line 421) — row access policy
--            ROW_POLICY_MAP table + MEMBER_PLAN_ACCESS_POLICY created there
-- "Column masking controls what you SEE. Row-level security controls
--  which populations you can ACCESS at all."
-- =============================================================================
-- Show the row access policy mapping so the audience understands the logic
/*

USE ROLE ACCOUNTADMIN;

SELECT * FROM GOVERNANCE_CA_DEMO.POLICY_STORE.ROW_POLICY_MAP
ORDER BY ROLE, VISIBLE_PLAN_TYPE;

*/

/*

-- Plan types:
--   COMM    → Commercial managed care (CalOptima Access HMO/PPO)
--   DSNP    → Dual Special Needs Plan (Medicare + Medi-Cal dual-eligible)
--   MEDCAID → Medi-Cal / California Medicaid (heightened privacy — reveals low-income status)

*/

-- ── Switch role, then run the row count query below ───────────────────────────
--USE ROLE ACCOUNTADMIN;
USE ROLE DATA_ENGINEER_ROLE;
USE ROLE ANALYTICS_INNOVATOR_ROLE;
USE ROLE BUSINESS_ANALYST_ROLE;

SELECT MEME_MCTR_TYPE, COUNT(*) AS member_count
FROM MEMBER
GROUP BY MEME_MCTR_TYPE
ORDER BY member_count DESC;

-- Row visibility matrix (enforced by row access policy — 01 Section G, line 421):
-- ┌─────────────────────────┬─────────────┬──────────────┬───────────────────┬──────────────────┐
-- │ Plan Type               │ ACCOUNTADMIN│ DATA_ENGINEER│ ANALYTICS_INNOVATOR│ BUSINESS_ANALYST │
-- ├─────────────────────────┼─────────────┼──────────────┼───────────────────┼──────────────────┤
-- │ COMM   (~30,593 rows)   │ ✓ Visible   │ ✓ Visible    │ ✓ Visible         │ ✓ Visible        │
-- │ DSNP   (~30,866 rows)   │ ✓ Visible   │ ✓ Visible    │ ✓ Visible         │ ✗ Hidden         │
-- │ MEDCAID (~30,642 rows)  │ ✓ Visible   │ ✓ Visible    │ ✗ Hidden          │ ✗ Hidden         │
-- └─────────────────────────┴─────────────┴──────────────┴───────────────────┴──────────────────┘

-- Confirm DSNP is invisible to Business Analyst (run this as that role)
USE ROLE BUSINESS_ANALYST_ROLE;
SELECT *
FROM MEMBER
WHERE MEME_MCTR_TYPE = 'DSNP'
LIMIT 5;
-- Returns 0 rows — row policy fires silently. No error.
-- The analyst doesn't know DSNP exists. HIPAA minimum necessary.


-- =============================================================================
-- Next: Run 03_schema_access_demo.sql for:
--   Separation of duties (BA sandbox + blocked DDL)
--   Instant REVOKE demo
--   Pre-built audit log
-- =============================================================================
