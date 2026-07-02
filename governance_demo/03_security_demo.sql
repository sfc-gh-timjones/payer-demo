-- =============================================================================
-- FILE: 03_schema_access_demo.sql
-- PURPOSE: CalOptima RFP 26-038 | Topic 5 — Schema Access + Separation of Duties
--          Managed access schema, Analytics Innovator sandbox, instant REVOKE,
--          and ACCESS_HISTORY audit log.
--
-- SETUP REFERENCE: 01_governance_setup.sql
--   Managed access schema:           Section A, lines 35-42
--   Role grants on PROTECTED:        Section I, lines 457-530
--   Analytics Innovator sandbox:     Section I, line 503
-- =============================================================================

USE DATABASE GOVERNANCE_CA_DEMO;
USE SCHEMA PROTECTED;
USE WAREHOUSE WH_XS;


-- =============================================================================
-- PART 1: MANAGED ACCESS SCHEMA — DATA ENGINEERS CANNOT SHARE PHI
-- "The PROTECTED schema uses WITH MANAGED ACCESS. Only the schema owner
--  (ACCOUNTADMIN) can grant access to PHI tables — not the engineers who
--  built or own those tables."
-- =============================================================================

-- Setup reminder: GOVERNANCE_CA_DEMO.PROTECTED was created WITH MANAGED ACCESS
-- (01_governance_setup.sql Section A, line 36)
-- This means the DATA_ENGINEER_ROLE cannot grant SELECT on MEMBER_PHI to anyone,
-- even though they can read it. Privilege grants are centralized through ACCOUNTADMIN.

-- Try as DATA_ENGINEER_ROLE: attempt to grant PHI access to BUSINESS_ANALYST_ROLE
USE ROLE DATA_ENGINEER_ROLE;

-- Uncomment to demonstrate — this WILL fail:
-- GRANT SELECT ON TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
--     TO ROLE BUSINESS_ANALYST_ROLE;
-- → Error: "Insufficient privileges to operate on schema 'PROTECTED'"
-- Talking point: In a standard schema, any object owner can self-grant.
-- Managed access removes that capability — governance team holds the keys.

-- For comparison: show what DATA_ENGINEER_ROLE CAN do
-- (Read data — they're a legitimate pipeline user)
SELECT MEME_MCTR_TYPE, COUNT(*) AS member_count
FROM MEMBER_PHI
GROUP BY MEME_MCTR_TYPE;

-- Explain managed access: show schema properties
USE ROLE ACCOUNTADMIN;
SHOW SCHEMAS IN DATABASE GOVERNANCE_CA_DEMO;
-- Look for: IS_MANAGED_ACCESS = Y on the PROTECTED schema


-- =============================================================================
-- PART 2: SEPARATION OF DUTIES — ANALYTICS INNOVATOR SANDBOX
-- "The analytics team has full creative freedom in their own schema.
--  They can build models, create tables, experiment — but they cannot
--  modify or extract row-level PHI from the governed PROTECTED schema."
-- =============================================================================

USE ROLE ANALYTICS_INNOVATOR_ROLE;

-- Analytics Innovator CAN create their own schema in GOVERNANCE_CA_DEMO
-- (01_governance_setup.sql Section I, line 503: GRANT CREATE SCHEMA ON DATABASE)
CREATE SCHEMA IF NOT EXISTS GOVERNANCE_CA_DEMO.ANALYTICS_SANDBOX
    COMMENT = 'Analytics Innovator sandbox. Full DDL freedom. Cannot access PROTECTED schema DDL.';

-- They can build aggregated summaries from governed data — no individual PHI rows
CREATE OR REPLACE TABLE GOVERNANCE_CA_DEMO.ANALYTICS_SANDBOX.PLAN_ENROLLMENT_SUMMARY AS
SELECT
    MEME_MCTR_TYPE                          AS plan_type,
    COUNT(*)                                AS enrolled_members,
    COUNT(ACTIVE_PCP_PRPR_ID)               AS members_with_pcp,
    ROUND(
        COUNT(ACTIVE_PCP_PRPR_ID) * 100.0 / COUNT(*), 1
    )                                       AS pct_with_pcp,
    COUNT(DISTINCT MEME_REL_CD)             AS relationship_types
FROM GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
GROUP BY MEME_MCTR_TYPE;

SELECT * FROM GOVERNANCE_CA_DEMO.ANALYTICS_SANDBOX.PLAN_ENROLLMENT_SUMMARY;
-- Row counts reflect the row policy (MEDCAID hidden from Analytics Innovator)
-- Aggregated result contains no individual PHI — CalOptima compliance satisfied

-- Analytics Innovator CANNOT create tables in PROTECTED (no CREATE TABLE grant there)
-- Uncomment to demonstrate:
-- CREATE TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_COPY AS SELECT * FROM MEMBER_PHI;
-- → Error: Insufficient privileges

-- Analytics Innovator CANNOT drop or alter policies
-- Uncomment to demonstrate:
-- DROP TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI;
-- → Error: Insufficient privileges


-- =============================================================================
-- PART 3: REVOKE — HOW FAST IS ACCESS REMOVAL?
-- "HIPAA requires that access can be revoked when an employee leaves or
--  changes roles. Let's show how Snowflake handles that."
-- =============================================================================

-- Verify Business Analyst currently has access
USE ROLE BUSINESS_ANALYST_ROLE;

SELECT COUNT(*) AS visible_members FROM MEMBER_PHI;
-- Expected: ~30,593 (COMM plan only)

-- Revoke access as ACCOUNTADMIN — takes effect immediately
USE ROLE ACCOUNTADMIN;

REVOKE SELECT ON TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
    FROM ROLE BUSINESS_ANALYST_ROLE;

-- Verify: next query after revoke is denied instantly
USE ROLE BUSINESS_ANALYST_ROLE;

SELECT COUNT(*) AS visible_members FROM MEMBER_PHI;
-- → Error: "Object 'MEMBER_PHI' does not exist or not authorized."
-- Talking point: zero lag. No session invalidation required. No waiting.
-- Snowflake re-evaluates grants on every query execution.

-- Restore access for next demo run
USE ROLE ACCOUNTADMIN;

GRANT SELECT ON TABLE GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI
    TO ROLE BUSINESS_ANALYST_ROLE;

-- Confirm access restored
USE ROLE BUSINESS_ANALYST_ROLE;

SELECT COUNT(*) AS visible_members FROM MEMBER_PHI;
-- Expected: ~30,593 (back to COMM plan)


-- =============================================================================
-- PART 4: AUDIT LOG — COMPLETE ACCESS HISTORY
-- "Snowflake records every query against MEMBER_PHI — including queries
--  that returned zero rows because of row access policies."
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Full query history against MEMBER_PHI (note: ACCESS_HISTORY has ~30-min lag)
SELECT
    QUERY_START_TIME,
    USER_NAME,
    ROLE_NAME,
    LEFT(QUERY_TEXT, 120)                                       AS query_preview,
    DIRECT_OBJECTS_ACCESSED[0]:objectName::STRING               AS table_accessed
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY
WHERE ARRAY_CONTAINS(
    'GOVERNANCE_CA_DEMO.PROTECTED.MEMBER_PHI'::VARIANT,
    DIRECT_OBJECTS_ACCESSED[*].objectName
)
ORDER BY QUERY_START_TIME DESC
LIMIT 30;

-- Role-by-role access summary — compliance report view
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

-- Talking points:
-- • ACCESS_HISTORY captures every query, including those returning 0 rows (row policy denied)
-- • CalOptima auditors can query this directly — no log export pipeline required
-- • HIPAA requires audit logs of all PHI access: Snowflake provides this natively
-- • When the REVOKE fired and returned "not authorized" — that's in ACCESS_HISTORY too


-- =============================================================================
-- CLEANUP (uncomment before next demo run)
-- =============================================================================

-- Drop Analytics Innovator sandbox summary table (recreated in demo)
-- USE ROLE ANALYTICS_INNOVATOR_ROLE;
-- DROP TABLE IF EXISTS GOVERNANCE_CA_DEMO.ANALYTICS_SANDBOX.PLAN_ENROLLMENT_SUMMARY;

-- Drop clone copy created in 02_discovery_demo.sql
-- USE ROLE DATA_ENGINEER_ROLE;
-- DROP TABLE IF EXISTS zFACETS_DEV_CLONE.SILVER.MEMBER_ANALYTICS_COPY;

-- =============================================================================
-- END OF DEMO
-- Topic 4 (Discovery + Classification): 02_discovery_demo.sql — Parts 1
-- Topic 5 (Security Enforcement):       02_discovery_demo.sql — Parts 2-3
--                                        03_schema_access_demo.sql — Parts 1-4
-- Scenario 5 (Role walk-through):       Both demo scripts combined
-- =============================================================================
