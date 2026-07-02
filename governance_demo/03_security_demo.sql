-- =============================================================================
-- FILE: 03_security_demo.sql
-- PURPOSE: CalOptima RFP 26-038 | Topic 5 + Scenario 5: Security Enforcement
--          Live 4-role walk-through showing row-level security and dynamic
--          column masking in action against GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
--
-- SETUP REFERENCE: 01_governance_setup.sql
--   Masking policies (STRING/DATE):  Section D, lines 197-310
--   Policies attached to tag:        Section E, lines 312-325
--   Manual PHI tags on MEMBER_PHI:   Section G, lines 372-420
--   Row access policy:               Section H, lines 422-480
--   Role grants:                     Section I, lines 482-560
--
-- TABLE: GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
--   ~92,101 rows | Plan types: DSNP (30,866), MEDCAID (30,642), COMM (30,593)
--
-- ROLE PRIVILEGE MATRIX:
-- ┌──────────────────────┬─────────────┬──────────────┬────────────────────┬──────────────────┐
-- │                      │ ACCOUNTADMIN│ DATA_ENGINEER│ ANALYTICS_INNOVATOR│ BUSINESS_ANALYST │
-- ├──────────────────────┼─────────────┼──────────────┼────────────────────┼──────────────────┤
-- │ Visible plan types   │ ALL         │ ALL          │ COMM + DSNP        │ COMM only        │
-- │ Expected row count   │ ~92,101     │ ~92,101      │ ~61,459            │ ~30,593          │
-- │ Names (SENSITIVE)    │ Unmasked    │ Unmasked     │ J****** (initial)  │ *** SENSITIVE ***│
-- │ DOB (RESTRICTED)     │ Unmasked    │ Unmasked     │ Year only (2001-01)│ NULL             │
-- │ MECD_BIC/AID (PII)   │ Unmasked    │ Unmasked     │ ***PHI REDACTED*** │ ***PHI REDACTED**│
-- │ DDL on PROTECTED     │ Yes         │ No           │ No                 │ No               │
-- └──────────────────────┴─────────────┴──────────────┴────────────────────┴──────────────────┘
-- =============================================================================

-- Context set once — all queries below use schema-relative references
USE DATABASE GOVERNANCE_CA_DEMO;
USE SCHEMA PROTECTED;
USE WAREHOUSE WH_XS;


-- =============================================================================
-- STEP 1: ACCOUNTADMIN — Full Access, No Restrictions
-- "Let's start with the admin view — everything is visible."
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Full PHI visible: names unmasked, DOBs exact, Medi-Cal IDs exposed
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

-- All three plan populations visible
SELECT
    MEME_MCTR_TYPE,
    COUNT(*) AS member_count
FROM MEMBER_PHI
GROUP BY MEME_MCTR_TYPE
ORDER BY member_count DESC;
-- Expected: DSNP ~30,866 | MEDCAID ~30,642 | COMM ~30,593


-- =============================================================================
-- STEP 2: DATA_ENGINEER_ROLE — Full Access, All Plan Types
-- "The data engineer who builds the pipeline sees the same as an admin."
-- =============================================================================

USE ROLE DATA_ENGINEER_ROLE;

-- No masking, all rows — DE needs full access to build and validate pipelines
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

SELECT MEME_MCTR_TYPE, COUNT(*) AS member_count
FROM MEMBER_PHI
GROUP BY MEME_MCTR_TYPE
ORDER BY member_count DESC;

-- Demonstrate managed access schema: DE cannot grant SELECT to others
-- (Try this to show the governance control is real)
-- GRANT SELECT ON TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI TO ROLE BUSINESS_ANALYST_ROLE;
-- → Error: "Insufficient privileges" — only schema owner (ACCOUNTADMIN) can grant here


-- =============================================================================
-- STEP 3: ANALYTICS_INNOVATOR_ROLE — Partial Masking, No Medi-Cal
-- "The analytics team gets enough to do their work — but not the Medi-Cal population."
-- =============================================================================

USE ROLE ANALYTICS_INNOVATOR_ROLE;

-- Row-level policy fires: MEDCAID rows are gone
-- Column masking: names → initial + ***, DOBs → year-only, Medi-Cal IDs → redacted
SELECT
    MEME_ID,
    MEME_LAST_NAME,            -- SENSITIVE: J****** (first initial + asterisks)
    MEME_FIRST_NAME,           -- SENSITIVE: pseudonymized
    MEME_DOB,                  -- RESTRICTED: 2001-01-01 (year only, HIPAA §164.514(b))
    MEME_SEX,                  -- SENSITIVE: pseudonymized
    MECD_AID_CD,               -- PII: *** PHI REDACTED ***
    MECD_BIC,                  -- PII: *** PHI REDACTED ***
    MEME_MCTR_TYPE,            -- INTERNAL: visible (this is the row filter column)
    ACTIVE_PCP_NAME            -- SENSITIVE: pseudonymized
FROM MEMBER_PHI
ORDER BY MEME_ID
LIMIT 10;

-- Row count shows MEDCAID is completely hidden from this role
SELECT MEME_MCTR_TYPE, COUNT(*) AS member_count
FROM MEMBER_PHI
GROUP BY MEME_MCTR_TYPE
ORDER BY member_count DESC;
-- Expected: DSNP + COMM visible, MEDCAID absent entirely

-- Analytics Innovator can create their OWN schema for sandbox work
-- (Separation of duties: they own their sandbox, cannot touch PROTECTED)
CREATE SCHEMA IF NOT EXISTS GOVERNANCE_CA_DEMO.ANALYTICS_SANDBOX
    COMMENT = 'Analytics Innovator sandbox — cannot modify PROTECTED schema.';


-- =============================================================================
-- STEP 4: BUSINESS_ANALYST_ROLE — Most Restricted View
-- "The business analyst running commercial HMO reports sees the minimum necessary."
-- =============================================================================

USE ROLE BUSINESS_ANALYST_ROLE;

-- Row policy: only COMM (commercial HMO) rows visible
-- Column masking: all PHI/PII columns fully masked or NULL
SELECT
    MEME_ID,
    MEME_LAST_NAME,            -- SENSITIVE: *** SENSITIVE ***
    MEME_FIRST_NAME,           -- SENSITIVE: *** SENSITIVE ***
    MEME_DOB,                  -- RESTRICTED: NULL (BA cannot see even generalized DOB)
    MEME_SEX,                  -- SENSITIVE: *** SENSITIVE ***
    MECD_AID_CD,               -- PII: *** PHI REDACTED ***
    MECD_BIC,                  -- PII: *** PHI REDACTED ***
    MEME_MCTR_TYPE,            -- INTERNAL: visible (COMM only — row policy enforced)
    ACTIVE_PCP_NAME            -- SENSITIVE: *** SENSITIVE ***
FROM MEMBER_PHI
ORDER BY MEME_ID
LIMIT 10;

-- Only COMM rows visible — DSNP and MEDCAID are completely inaccessible
SELECT MEME_MCTR_TYPE, COUNT(*) AS member_count
FROM MEMBER_PHI
GROUP BY MEME_MCTR_TYPE;
-- Expected: COMM only (~30,593 rows)

-- Business Analyst cannot create objects in PROTECTED — no DDL privileges
-- CREATE TABLE MEMBER_COPY AS SELECT * FROM MEMBER_PHI;
-- → Error: Insufficient privileges


-- =============================================================================
-- STEP 5: REVOKE DEMO — Instant Access Removal
-- "How fast can CalOptima remove access? Let's find out."
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Remove SELECT from BUSINESS_ANALYST_ROLE — immediate effect
REVOKE SELECT ON TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
    FROM ROLE BUSINESS_ANALYST_ROLE;

-- Attempt access — access is revoked instantly, no waiting
USE ROLE BUSINESS_ANALYST_ROLE;
SELECT COUNT(*) FROM MEMBER_PHI;
-- → "Object 'MEMBER_PHI' does not exist or not authorized."
-- Talking point: Access revoked in milliseconds, enforced on next query.
-- No session invalidation needed — Snowflake re-checks grants on every query.

-- Restore access for next demo run
USE ROLE ACCOUNTADMIN;
GRANT SELECT ON TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
    TO ROLE BUSINESS_ANALYST_ROLE;


-- =============================================================================
-- STEP 6: SEPARATION OF DUTIES — Analytics Innovator Cannot Touch Governed Data
-- "The analytics team has full freedom in their sandbox — but zero access to modify Silver."
-- =============================================================================

-- Analytics Innovator: try to CREATE a table in PROTECTED (should fail)
USE ROLE ANALYTICS_INNOVATOR_ROLE;
-- CREATE TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_COPY AS SELECT * FROM MEMBER_PHI;
-- → Error: Insufficient privileges (managed access schema + no CREATE TABLE grant)

-- But they can freely work in their own sandbox
CREATE OR REPLACE TABLE GOVERNANCE_CA_DEMO.ANALYTICS_SANDBOX.MEMBER_COMMERCIAL_SUMMARY AS
SELECT
    MEME_MCTR_TYPE,
    COUNT(*)                    AS member_count,
    COUNT(ACTIVE_PCP_PRPR_ID)   AS members_with_pcp,
    COUNT(DISTINCT MEME_REL_CD) AS relationship_types
FROM GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
GROUP BY MEME_MCTR_TYPE;

SELECT * FROM GOVERNANCE_CA_DEMO.ANALYTICS_SANDBOX.MEMBER_COMMERCIAL_SUMMARY;
-- Note: aggregated result — no individual PHI rows copied, just summary counts


-- =============================================================================
-- STEP 7: AUDIT LOG — Full Access History
-- "Snowflake records every query against MEMBER_PHI — who accessed what and when."
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Query ACCESS_HISTORY for all access to MEMBER_PHI (30-minute lag for ingestion)
SELECT
    QUERY_START_TIME,
    USER_NAME,
    ROLE_NAME,
    -- Truncate long queries for display
    LEFT(QUERY_TEXT, 120)                                       AS query_text,
    DIRECT_OBJECTS_ACCESSED[0]:objectName::STRING               AS table_accessed
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY
WHERE ARRAY_CONTAINS(
    'GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI'::VARIANT,
    DIRECT_OBJECTS_ACCESSED[*].objectName
)
ORDER BY QUERY_START_TIME DESC
LIMIT 20;

-- Role-by-role access summary for the compliance report
SELECT
    ROLE_NAME,
    USER_NAME,
    COUNT(*)                            AS query_count,
    MIN(QUERY_START_TIME)               AS first_access,
    MAX(QUERY_START_TIME)               AS last_access
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY
WHERE ARRAY_CONTAINS(
    'GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI'::VARIANT,
    DIRECT_OBJECTS_ACCESSED[*].objectName
)
GROUP BY ROLE_NAME, USER_NAME
ORDER BY query_count DESC;

-- Talking point: ACCESS_HISTORY captures every query, including those that
-- return zero rows because of row access policies. HIPAA requires audit logs
-- of all PHI access — this gives CalOptima a complete, queryable audit trail.


-- =============================================================================
-- CLEANUP (Run after demo to reset for next run)
-- =============================================================================

-- Uncomment to drop sandbox analytics table before next run:
-- USE ROLE ANALYTICS_INNOVATOR_ROLE;
-- DROP TABLE IF EXISTS GOVERNANCE_CA_DEMO.ANALYTICS_SANDBOX.MEMBER_COMMERCIAL_SUMMARY;

-- Uncomment to drop clone MEMBER_ANALYTICS_COPY (created in 02_discovery_demo.sql):
-- USE ROLE DATA_ENGINEER_ROLE;
-- DROP TABLE IF EXISTS zFACETS_DEV_CLONE.SILVER.MEMBER_ANALYTICS_COPY;

-- =============================================================================
-- END OF DEMO
-- Topic 4 covered: AI auto-classification → 02_discovery_demo.sql
-- Topic 5 covered: RBAC, row-level security, masking, revoke, audit → this file
-- Scenario 5 covered: 4-role walk-through fully demonstrated above
-- =============================================================================
