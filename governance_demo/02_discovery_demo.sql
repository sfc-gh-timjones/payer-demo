-- =============================================================================
-- FILE: 02_discovery_demo.sql
-- PURPOSE: CalOptima RFP 26-038 | Topic 4 + Topic 5 — Live Demo
--          Walk-through: Tags → Column-Level Masking → Row-Level Security
--
-- TABLE: GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
--        ~92,101 rows | DSNP: 30,866 | MEDCAID: 30,642 | COMM: 30,593
--
-- SETUP REFERENCE: 01_governance_setup.sql
--   Classification tag + profile:     Section B, lines 62-145
--   AI classification run (clone):    Section C, lines 147-180
--   Masking policies (STRING/DATE):   Section D, lines 182-295
--   Policies attached to tag:         Section E, lines 297-310
--   Manual PHI tags on MEMBER_PHI:    Section G, lines 352-400
--   Row access policy:                Section H, lines 402-455
-- =============================================================================

USE DATABASE GOVERNANCE_CA_DEMO;
USE SCHEMA PROTECTED;
USE WAREHOUSE WH_XS;


-- =============================================================================
-- PART 1: TAGS — SNOWFLAKE AUTOMATICALLY IDENTIFIES SENSITIVE DATA
-- "Before we enforce anything, we need to know what's sensitive.
--  Snowflake's AI scanned every column and assigned a classification level."
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

-- Step 1b: Preview AI classification (read-only, no tags applied)
-- Run this on the clone to show Snowflake's AI recommendations live
USE DATABASE zFACETS_DEV_CLONE;
USE SCHEMA SILVER;

CALL SYSTEM$CLASSIFY(
    'zFACETS_DEV_CLONE.SILVER.MEMBER',
    {'auto_tag': false}
);

-- Parse recommendations into a readable table
SELECT
    col.key                                                   AS column_name,
    col.value:recommendation:semantic_category::STRING        AS semantic_category,
    col.value:recommendation:privacy_category::STRING         AS privacy_category,
    col.value:recommendation:confidence::STRING               AS confidence
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) r,
    LATERAL FLATTEN(input => r."SYSTEM$CLASSIFY":classification_result) col
ORDER BY
    CASE col.value:recommendation:privacy_category::STRING
        WHEN 'IDENTIFIER'       THEN 1
        WHEN 'QUASI_IDENTIFIER' THEN 2
        WHEN 'SENSITIVE'        THEN 3
        ELSE 4
    END,
    col.key;
-- Talking point: AI scanned 29 columns, found every HIPAA PHI element.
-- No business rules written. No manual column cataloging.

-- Step 1c: Show the DATA_CLASSIFICATION tags already applied by setup
-- (01_governance_setup.sql Section C ran SYSTEM$CLASSIFY with auto_tag: true)
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

-- Summary by classification level
SELECT
    TAG_VALUE                                            AS classification_level,
    COUNT(*)                                             AS column_count,
    LISTAGG(COLUMN_NAME, ', ')
        WITHIN GROUP (ORDER BY COLUMN_NAME)              AS columns
FROM TABLE(
    INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
        'zFACETS_DEV_CLONE.SILVER.MEMBER', 'table'
    )
)
WHERE TAG_NAME = 'DATA_CLASSIFICATION'
GROUP BY TAG_VALUE
ORDER BY
    CASE TAG_VALUE
        WHEN 'PII' THEN 1 WHEN 'RESTRICTED' THEN 2
        WHEN 'SENSITIVE' THEN 3 WHEN 'INTERNAL' THEN 4
    END;

-- Step 1d: Tag propagation — labels follow data through CTAS automatically
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
-- Audience sees: all DATA_CLASSIFICATION tags propagated to the copy.
-- Zero manual tagging. Governance followed the data.
-- Setup ref: tag created with PROPAGATE = ON_DEPENDENCY_AND_DATA_MOVEMENT
--            (01_governance_setup.sql Section B, line 78)


-- =============================================================================
-- PART 2: COLUMN-LEVEL MASKING — SAME QUERY, FOUR DIFFERENT VIEWS
-- "Now that we've tagged the data, the masking policies enforce automatically.
--  Every role runs the exact same SELECT — Snowflake handles the rest."
-- =============================================================================

USE DATABASE GOVERNANCE_CA_DEMO;
USE SCHEMA PROTECTED;

-- ── Admin view (ACCOUNTADMIN): full PHI — no masking ─────────────────────────
USE ROLE ACCOUNTADMIN;

SELECT
    MEME_ID,
    MEME_LAST_NAME,       -- SENSITIVE: unmasked
    MEME_FIRST_NAME,      -- SENSITIVE: unmasked
    MEME_DOB,             -- RESTRICTED: exact date
    MEME_SEX,             -- SENSITIVE: unmasked
    MECD_AID_CD,          -- PII: unmasked
    MECD_BIC,             -- PII: unmasked
    MEME_MCTR_TYPE,
    ACTIVE_PCP_NAME       -- SENSITIVE: unmasked
FROM MEMBER_PHI
ORDER BY MEME_ID
LIMIT 10;

-- ── Data Engineer view: same full access — needed to build/validate pipelines ──
USE ROLE DATA_ENGINEER_ROLE;

SELECT
    MEME_ID,
    MEME_LAST_NAME,
    MEME_FIRST_NAME,
    MEME_DOB,
    MEME_SEX,
    MECD_AID_CD,
    MECD_BIC,
    MEME_MCTR_TYPE,
    ACTIVE_PCP_NAME
FROM MEMBER_PHI
ORDER BY MEME_ID
LIMIT 10;
-- Identical to ACCOUNTADMIN — engineers see raw PHI for pipeline work

-- ── Analytics Innovator view: partial masking ────────────────────────────────
-- SENSITIVE → first initial + *** (pseudonymization)
-- RESTRICTED → year only (HIPAA §164.514(b) safe harbor)
-- PII → *** PHI REDACTED ***
USE ROLE ANALYTICS_INNOVATOR_ROLE;

SELECT
    MEME_ID,
    MEME_LAST_NAME,       -- SENSITIVE: "S*****" (first initial + ***)
    MEME_FIRST_NAME,      -- SENSITIVE: pseudonymized
    MEME_DOB,             -- RESTRICTED: "2001-01-01" (year only)
    MEME_SEX,             -- SENSITIVE: pseudonymized
    MECD_AID_CD,          -- PII: "*** PHI REDACTED ***"
    MECD_BIC,             -- PII: "*** PHI REDACTED ***"
    MEME_MCTR_TYPE,       -- INTERNAL: visible
    ACTIVE_PCP_NAME       -- SENSITIVE: pseudonymized
FROM MEMBER_PHI
ORDER BY MEME_ID
LIMIT 10;

-- ── Business Analyst view: full masking ──────────────────────────────────────
-- All PHI/PII columns fully opaque — minimum necessary principle
USE ROLE BUSINESS_ANALYST_ROLE;

SELECT
    MEME_ID,
    MEME_LAST_NAME,       -- SENSITIVE: "*** SENSITIVE ***"
    MEME_FIRST_NAME,      -- SENSITIVE: "*** SENSITIVE ***"
    MEME_DOB,             -- RESTRICTED: NULL
    MEME_SEX,             -- SENSITIVE: "*** SENSITIVE ***"
    MECD_AID_CD,          -- PII: "*** PHI REDACTED ***"
    MECD_BIC,             -- PII: "*** PHI REDACTED ***"
    MEME_MCTR_TYPE,       -- INTERNAL: visible (COMM only — row policy fires)
    ACTIVE_PCP_NAME       -- SENSITIVE: "*** SENSITIVE ***"
FROM MEMBER_PHI
ORDER BY MEME_ID
LIMIT 10;

-- Talking point: same SQL in all four queries — no WHERE clauses, no CASE statements,
-- no application-level logic. Masking is enforced at the Snowflake layer,
-- invisible to the analyst and impossible to bypass.


-- =============================================================================
-- PART 3: ROW-LEVEL SECURITY — MEDICAID POPULATION ACCESS CONTROL
-- "Column masking controls what you SEE. Row-level security controls
--  what populations you can ACCESS at all."
-- =============================================================================

USE DATABASE GOVERNANCE_CA_DEMO;
USE SCHEMA PROTECTED;

-- Show the row access policy mapping so audience understands the logic
USE ROLE ACCOUNTADMIN;

SELECT * FROM GOVERNANCE_CA_DEMO.POLICY_STORE.ROW_POLICY_MAP
ORDER BY ROLE, VISIBLE_PLAN_TYPE;

-- ── Admin + Engineer: all three plan populations ──────────────────────────────
USE ROLE ACCOUNTADMIN;

SELECT MEME_MCTR_TYPE, COUNT(*) AS member_count
FROM MEMBER_PHI
GROUP BY MEME_MCTR_TYPE
ORDER BY member_count DESC;
-- Expected: DSNP ~30,866 | MEDCAID ~30,642 | COMM ~30,593

-- ── Analytics Innovator: MEDCAID rows gone entirely ───────────────────────────
USE ROLE ANALYTICS_INNOVATOR_ROLE;

SELECT MEME_MCTR_TYPE, COUNT(*) AS member_count
FROM MEMBER_PHI
GROUP BY MEME_MCTR_TYPE
ORDER BY member_count DESC;
-- Expected: DSNP + COMM only — MEDCAID has vanished from query results

-- Try to count MEDCAID directly — still zero
SELECT COUNT(*) AS medcaid_rows
FROM MEMBER_PHI
WHERE MEME_MCTR_TYPE = 'MEDCAID';
-- Returns 0 — row policy fires silently. No error, no indication rows were filtered.
-- Talking point: the analyst doesn't know MEDCAID exists. No error message.
-- HIPAA minimum necessary: system enforces access without revealing what was hidden.

-- ── Business Analyst: COMM only ──────────────────────────────────────────────
USE ROLE BUSINESS_ANALYST_ROLE;

SELECT MEME_MCTR_TYPE, COUNT(*) AS member_count
FROM MEMBER_PHI
GROUP BY MEME_MCTR_TYPE;
-- Expected: COMM only (~30,593 rows)

SELECT COUNT(*) AS total_visible_members
FROM MEMBER_PHI;
-- ~30,593 — only commercial HMO members

-- Talking point: a business analyst running commercial plan performance analytics
-- gets exactly the population they need — no Medi-Cal or DSNP records,
-- no regulatory exposure. CalOptima's compliance team sleeps soundly.


-- =============================================================================
-- Next: Run 03_schema_access_demo.sql for:
--   Managed access schema (separation of duties)
--   Analytics Innovator sandbox
--   Instant REVOKE demo
--   ACCESS_HISTORY audit log
-- =============================================================================
