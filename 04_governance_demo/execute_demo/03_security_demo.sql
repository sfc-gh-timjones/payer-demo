-- =============================================================================
-- FILE: 03_schema_access_demo.sql
-- PURPOSE: CalOptima RFP 26-038 | Topic 5 — Separation of Duties + REVOKE + Audit
--
-- SETUP REFERENCES (01_governance_setup.sql):
--   BA CREATE SCHEMA grant:  Section H (GRANT CREATE SCHEMA ON DATABASE zFACETS_DEV_CLONE)
--   Role grants:             Section H (line 481)
--   Audit table:             Section I (line 508)
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;

USE DATABASE zFACETS_DEV_CLONE;
USE SCHEMA SILVER;
USE WAREHOUSE WH_XS;


-- =============================================================================
-- PART 1: SEPARATION OF DUTIES — ANALYST SANDBOX + BLOCKED DDL
-- "The Business Analyst has their own sandbox schema for analysis work.
--  They cannot touch the governed SILVER tables."
-- =============================================================================

USE ROLE BUSINESS_ANALYST_ROLE;

-- BA creates their own schema in the clone database
CREATE SCHEMA IF NOT EXISTS ANALYST
    COMMENT = 'Business Analyst sandbox — read/write here, read-only on SILVER.';

-- CTAS: BA builds a working table from COMM members
-- (row policy enforces they only see COMM rows — even in their own sandbox)
CREATE OR REPLACE TABLE COMM_MEMBERS AS
SELECT
    MEME_ID,
    MEME_MCTR_TYPE,
    MEME_REL_CD,
    RELATIONSHIP_DESC,
    MEMBER_STATUS,
    ACTIVE_PCP_NAME
FROM SILVER.MEMBER;

SELECT * FROM COMM_MEMBERS LIMIT 10;
-- Note: only COMM rows — row access policy followed the data into the CTAS

-- BA creates a view for reporting
CREATE OR REPLACE VIEW COMM_ACTIVE_MEMBERS AS
SELECT MEME_ID, MEME_MCTR_TYPE, MEME_REL_CD, MEMBER_STATUS
FROM SILVER.MEMBER
WHERE MEMBER_STATUS = 'Active';

SELECT COUNT(*) AS active_commercial_members FROM COMM_ACTIVE_MEMBERS;

-- ── Now try to break out of the sandbox ──────────────────────────────────────
-- Uncomment either line to demonstrate — both will fail

INSERT INTO SILVER.MEMBER (MEME_ID, SBSB_ID, MEME_LAST_NAME, MEME_FIRST_NAME, MEME_MCTR_TYPE)
VALUES (99999, 99999, 'TEST', 'RECORD', 'COMM');
-- → Error: Insufficient privileges to INSERT

DROP TABLE SILVER.MEMBER;
-- → Error: Insufficient privileges to DROP

-- Talking point: BA owns everything in ANALYST schema, but SILVER.MEMBER is
-- owned by ACCOUNTADMIN. SELECT was explicitly granted; INSERT and DDL were not.


-- =============================================================================
-- PART 2: REVOKE — INSTANT ACCESS REMOVAL
-- "HIPAA requires that access can be removed immediately. Let's show that."
-- =============================================================================

-- Verify BA currently has access
USE ROLE BUSINESS_ANALYST_ROLE;

SELECT COUNT(*) AS visible_members FROM SILVER.MEMBER;
-- Expected: ~30,593 (COMM only — row policy enforced)

-- Revoke all access levels (table + schema + database)
USE ROLE ACCOUNTADMIN;

REVOKE SELECT ON TABLE zFACETS_DEV_CLONE.SILVER.MEMBER  FROM ROLE BUSINESS_ANALYST_ROLE;
REVOKE USAGE ON SCHEMA zFACETS_DEV_CLONE.SILVER          FROM ROLE BUSINESS_ANALYST_ROLE;
REVOKE USAGE ON DATABASE zFACETS_DEV_CLONE               FROM ROLE BUSINESS_ANALYST_ROLE;

-- Verify grants are gone
SHOW GRANTS TO ROLE BUSINESS_ANALYST_ROLE;

-- Attempt access — denied instantly, no lag
USE ROLE BUSINESS_ANALYST_ROLE;

SELECT COUNT(*) AS visible_members FROM SILVER.MEMBER;
-- → Error: "Database 'ZFACETS_DEV_CLONE' does not exist or not authorized."
-- Talking point: zero lag. No session invalidation. Re-checked on every query.

-- ⚠ After this demo: run execute_pre_demo/restore_ba_access.sql to restore access
--   before the next session.


-- =============================================================================
-- PART 3: AUDIT LOG — PRE-BUILT ACCESS HISTORY
-- "Snowflake captures every query — including those that returned 0 rows
--  because of row access policies."
--
-- Table pre-built in 01_governance_setup.sql Section I as a 90-day snapshot.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE GOVERNANCE_CA_DEMO;
USE SCHEMA POLICY_STORE;

-- No-op if already built by setup
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

-- Last 30 queries
SELECT * FROM ACCOUNT_ACCESS_HISTORY
WHERE USER_NAME IS NOT NULL 
ORDER BY QUERY_START_TIME DESC
LIMIT 30;

-- Role-by-role access summary
SELECT
    ROLE_NAME,
    USER_NAME,
    COUNT(*)                 AS query_count,
    MIN(QUERY_START_TIME)    AS first_access,
    MAX(QUERY_START_TIME)    AS last_access
FROM ACCOUNT_ACCESS_HISTORY
GROUP BY ROLE_NAME, USER_NAME
ORDER BY query_count DESC;

-- Talking points:
-- • Every query captured — including 0-row results from row access policies
-- • CalOptima auditors query this directly — no log export pipeline needed
-- • HIPAA requires audit logs of all PHI access: Snowflake provides this natively
-- • The REVOKE and "not authorized" error from Part 2 will appear here (after lag)

-- =============================================================================
-- END OF DEMO
-- Topic 4: Tags + classification        → 02_discovery_demo.sql Part 1
-- Topic 5: Column masking               → 02_discovery_demo.sql Part 2
--          Row-level security           → 02_discovery_demo.sql Part 3
--          Separation of duties         → 03_schema_access_demo.sql Part 1
--          Instant REVOKE               → 03_schema_access_demo.sql Part 2
--          Audit log                    → 03_schema_access_demo.sql Part 3
-- =============================================================================
