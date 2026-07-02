-- =============================================================================
-- FILE: 03_schema_access_demo.sql
-- PURPOSE: CalOptima RFP 26-038 | Topic 5 — Governance Architecture + Audit
--          Centralized policy store, Analytics Innovator sandbox, instant REVOKE,
--          and pre-built audit log.
--
-- DATABASE ARCHITECTURE:
--   zFACETS_DEV_CLONE.SILVER.MEMBER  — demo data table (governance applied here)
--   GOVERNANCE_CA_DEMO.POLICY_STORE  — all governance objects (tag, policies, audit)
--
-- SETUP REFERENCE: 01_governance_setup.sql
--   Role grants:        Section H
--   Audit table:        Section I
-- =============================================================================

USE ROLE ACCOUNTADMIN;

USE DATABASE GOVERNANCE_CA_DEMO;
USE SCHEMA POLICY_STORE;
USE WAREHOUSE WH_XS;


-- =============================================================================
-- PART 1: CENTRALIZED GOVERNANCE — POLICY_STORE OWNS EVERYTHING
-- "All governance objects are centralized in GOVERNANCE_CA_DEMO.POLICY_STORE,
--  owned by ACCOUNTADMIN. Engineers and analysts can read the data they're
--  entitled to, but cannot modify the policies that govern it."
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Show all governance objects in one place
SHOW TAGS             IN SCHEMA GOVERNANCE_CA_DEMO.POLICY_STORE;
SHOW MASKING POLICIES IN SCHEMA GOVERNANCE_CA_DEMO.POLICY_STORE;
SHOW ROW ACCESS POLICIES IN SCHEMA GOVERNANCE_CA_DEMO.POLICY_STORE;

-- Engineers can see the entitlement table but cannot alter the policy objects
USE ROLE DATA_ENGINEER_ROLE;
SELECT * FROM GOVERNANCE_CA_DEMO.POLICY_STORE.ROW_POLICY_MAP;

-- Engineers CANNOT change governance objects — try these to demonstrate:
-- USE ROLE DATA_ENGINEER_ROLE;
-- DROP TAG GOVERNANCE_CA_DEMO.POLICY_STORE.DATA_CLASSIFICATION;
-- → Error: Insufficient privileges
-- ALTER ROW ACCESS POLICY GOVERNANCE_CA_DEMO.POLICY_STORE.MEMBER_PLAN_ACCESS_POLICY SET BODY -> TRUE;
-- → Error: Insufficient privileges
-- Talking point: tags and policies are owned by ACCOUNTADMIN.
-- Engineers deploy data, not governance rules.


-- =============================================================================
-- PART 2: SEPARATION OF DUTIES — ANALYTICS INNOVATOR SANDBOX
-- "The analytics team has full creative freedom in their own schema.
--  They can build models, create tables, experiment — but they cannot
--  modify or extract row-level PHI from governed data."
-- =============================================================================

USE ROLE ANALYTICS_INNOVATOR_ROLE;

-- Analytics Innovator CAN create their own schema in GOVERNANCE_CA_DEMO
CREATE SCHEMA IF NOT EXISTS GOVERNANCE_CA_DEMO.ANALYTICS_SANDBOX
    COMMENT = 'Analytics Innovator sandbox. Full DDL freedom here.';

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
FROM zFACETS_DEV_CLONE.SILVER.MEMBER
GROUP BY MEME_MCTR_TYPE;

SELECT * FROM GOVERNANCE_CA_DEMO.ANALYTICS_SANDBOX.PLAN_ENROLLMENT_SUMMARY;
-- Row counts reflect the row policy (MEDCAID hidden from Analytics Innovator)
-- Aggregated result — no individual PHI rows, CalOptima compliance satisfied

-- Analytics Innovator CANNOT modify governance objects
-- Uncomment to demonstrate:
-- ALTER TABLE zFACETS_DEV_CLONE.SILVER.MEMBER DROP ROW ACCESS POLICY
--     GOVERNANCE_CA_DEMO.POLICY_STORE.MEMBER_PLAN_ACCESS_POLICY;
-- → Error: Insufficient privileges


-- =============================================================================
-- PART 3: REVOKE — INSTANT ACCESS REMOVAL
-- "HIPAA requires that access can be revoked when an employee leaves or
--  changes roles. Let's show how Snowflake handles that."
-- =============================================================================

-- Verify Business Analyst currently has access
USE ROLE BUSINESS_ANALYST_ROLE;

SELECT COUNT(*) AS visible_members FROM zFACETS_DEV_CLONE.SILVER.MEMBER;
-- Expected: ~30,593 (COMM plan only — row policy enforced)

-- Revoke all access levels from BUSINESS_ANALYST_ROLE (table + schema + database)
USE ROLE ACCOUNTADMIN;

REVOKE SELECT ON TABLE zFACETS_DEV_CLONE.SILVER.MEMBER FROM ROLE BUSINESS_ANALYST_ROLE;
REVOKE USAGE ON SCHEMA zFACETS_DEV_CLONE.SILVER FROM ROLE BUSINESS_ANALYST_ROLE;
REVOKE USAGE ON DATABASE zFACETS_DEV_CLONE FROM ROLE BUSINESS_ANALYST_ROLE;

-- Verify grants are gone
SHOW GRANTS TO ROLE BUSINESS_ANALYST_ROLE;

-- Attempt access — all three levels revoked, no secondary path
USE ROLE BUSINESS_ANALYST_ROLE;

SELECT COUNT(*) AS visible_members FROM zFACETS_DEV_CLONE.SILVER.MEMBER;
-- → Error: "Database 'ZFACETS_DEV_CLONE' does not exist or not authorized."
-- Talking point: zero lag. No session invalidation. Snowflake re-checks on every query.

-- Restore all three levels for next demo run
USE ROLE ACCOUNTADMIN;

GRANT USAGE ON DATABASE zFACETS_DEV_CLONE TO ROLE BUSINESS_ANALYST_ROLE;
GRANT USAGE ON SCHEMA zFACETS_DEV_CLONE.SILVER TO ROLE BUSINESS_ANALYST_ROLE;
GRANT SELECT ON TABLE zFACETS_DEV_CLONE.SILVER.MEMBER TO ROLE BUSINESS_ANALYST_ROLE;

USE ROLE BUSINESS_ANALYST_ROLE;
SELECT COUNT(*) AS visible_members FROM zFACETS_DEV_CLONE.SILVER.MEMBER;
-- Expected: ~30,593 — access restored instantly


-- =============================================================================
-- PART 4: AUDIT LOG — PRE-BUILT ACCESS HISTORY
-- "Snowflake records every query against every object — including queries that
--  returned zero rows because of row access policies."
--
-- Table pre-built in 01_governance_setup.sql Section I as a 90-day snapshot
-- (ACCESS_HISTORY has ~30-min lag; built at setup so demo SELECTs are instant).
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE GOVERNANCE_CA_DEMO;
USE SCHEMA POLICY_STORE;

-- No-op if already built by setup — ensures table exists for demo
CREATE TABLE IF NOT EXISTS ACCOUNT_ACCESS_HISTORY AS
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

-- Last 30 queries across the account
SELECT *
FROM ACCOUNT_ACCESS_HISTORY
ORDER BY QUERY_START_TIME DESC
LIMIT 30;

-- Role-by-role access summary — compliance report view
SELECT
    ROLE_NAME,
    USER_NAME,
    COUNT(*)                            AS query_count,
    MIN(QUERY_START_TIME)               AS first_access,
    MAX(QUERY_START_TIME)               AS last_access
FROM ACCOUNT_ACCESS_HISTORY
GROUP BY ROLE_NAME, USER_NAME
ORDER BY query_count DESC;

-- Talking points:
-- • Every query is captured — including those that returned 0 rows (row policy denied)
-- • CalOptima auditors query this table directly — no log export pipeline needed
-- • HIPAA requires audit logs of all PHI access: Snowflake provides this natively
-- • The REVOKE and "not authorized" error from Part 3 will appear here (after lag)


-- =============================================================================
-- END OF DEMO
-- Topic 4: Tags + auto-classification   → 02_discovery_demo.sql Part 1
-- Topic 5: Column masking               → 02_discovery_demo.sql Part 2
--          Row-level security           → 02_discovery_demo.sql Part 3
--          Governance centralization    → 03_schema_access_demo.sql Part 1
--          Sandbox + separation duties  → 03_schema_access_demo.sql Part 2
--          Instant REVOKE               → 03_schema_access_demo.sql Part 3
--          Audit log                    → 03_schema_access_demo.sql Part 4
-- =============================================================================
