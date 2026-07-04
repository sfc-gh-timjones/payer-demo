-- =============================================================================
-- FILE: 02_workload_isolation_setup.sql  (COORDINATOR — run this first)
-- PURPOSE: CalOptima RFP 26-038 | Performance — Workload Isolation
--          Setup, proof, and cleanup for the 5-worksheet demo.
--
-- HOW TO RUN:
--   1. Run PART 1 here to create the cost center tag, roles, warehouses, and grants
--   2. Open the 5 tab worksheets and run them simultaneously:
--        02_tab1_exec.sql    → Tab 1
--        02_tab2_eng.sql     → Tab 2  (start this one first — it's the heavy job)
--        02_tab3_analyst.sql → Tab 3
--        02_tab4_finance.sql → Tab 4
--        02_tab5_ml.sql      → Tab 5
--   3. Come back here and run PART 2 (proof) after queries complete
--   4. Run PART 3 (cleanup) to drop all objects after the demo
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;


-- =============================================================================
-- PART 1: COST CENTER TAG + ROLES + WAREHOUSES + GRANTS
-- =============================================================================

-- ── Step 1: Create cost center tag ───────────────────────────────────────────
-- Following Snowflake's cost attribution pattern:
-- docs.snowflake.com/en/user-guide/cost-attributing
--
-- Tag is applied to warehouses. TAG_REFERENCES joins to WAREHOUSE_METERING_HISTORY
-- to show credit spend broken down by cost center — chargeback / showback reporting.
--
-- Three cost centers map the 5 workload teams into CalOptima departments:
--   OPERATIONS   → EXEC_WH + FINANCE_WH  (executive dashboards + financial reports)
--   DATA_PLATFORM → ENG_WH               (data engineering and infrastructure)
--   ANALYTICS    → ANALYST_WH + ML_WH    (ad-hoc analysis + data science / ML)
--
CREATE DATABASE IF NOT EXISTS COST_MANAGEMENT;
CREATE SCHEMA IF NOT EXISTS COST_MANAGEMENT.TAGS;

CREATE OR REPLACE TAG COST_MANAGEMENT.TAGS.COST_CENTER
    ALLOWED_VALUES 'OPERATIONS', 'DATA_PLATFORM', 'ANALYTICS'
    COMMENT = 'CalOptima cost center for warehouse chargeback / showback reporting.';

-- ── Step 2: Create dedicated roles — one per workload persona ─────────────────
CREATE ROLE IF NOT EXISTS CALOPTIMA_EXEC_ROLE
    COMMENT = 'Executive team — read-only access to reporting warehouses';
CREATE ROLE IF NOT EXISTS CALOPTIMA_ENG_ROLE
    COMMENT = 'Data engineering team — ETL, CDC, bulk transforms';
CREATE ROLE IF NOT EXISTS CALOPTIMA_ANALYST_ROLE
    COMMENT = 'Analytics Innovators — ad-hoc exploration and analysis';
CREATE ROLE IF NOT EXISTS CALOPTIMA_FINANCE_ROLE
    COMMENT = 'Finance team — standard financial reporting and reconciliation';
CREATE ROLE IF NOT EXISTS CALOPTIMA_ML_ROLE
    COMMENT = 'Data Science / ML — feature engineering and model scoring';

-- ── Step 3: Create dedicated warehouses — one per role ───────────────────────
CREATE OR REPLACE WAREHOUSE CALOPTIMA_EXEC_WH
    WAREHOUSE_SIZE = XSMALL  AUTO_SUSPEND = 30  AUTO_RESUME = TRUE
    COMMENT = 'Executive dashboards and board-level population health reports';

CREATE OR REPLACE WAREHOUSE CALOPTIMA_ENG_WH
    WAREHOUSE_SIZE = LARGE   AUTO_SUSPEND = 30  AUTO_RESUME = TRUE
    COMMENT = 'Data engineering — ETL, CDC, bulk claims transforms';

CREATE OR REPLACE WAREHOUSE CALOPTIMA_ANALYST_WH
    WAREHOUSE_SIZE = MEDIUM  AUTO_SUSPEND = 30  AUTO_RESUME = TRUE
    COMMENT = 'Analytics Innovators — ad-hoc and exploratory analysis';

CREATE OR REPLACE WAREHOUSE CALOPTIMA_FINANCE_WH
    WAREHOUSE_SIZE = SMALL   AUTO_SUSPEND = 30  AUTO_RESUME = TRUE
    COMMENT = 'Finance Team — standard reporting and financial reconciliation';

CREATE OR REPLACE WAREHOUSE CALOPTIMA_ML_WH
    WAREHOUSE_SIZE = MEDIUM  AUTO_SUSPEND = 30  AUTO_RESUME = TRUE
    COMMENT = 'Data Science — ML feature engineering and model scoring';

-- ── Step 4: Apply COST_CENTER tag to each warehouse ──────────────────────────
-- EXEC + FINANCE → OPERATIONS (business reporting)
ALTER WAREHOUSE CALOPTIMA_EXEC_WH    SET TAG COST_MANAGEMENT.TAGS.COST_CENTER = 'OPERATIONS';
ALTER WAREHOUSE CALOPTIMA_FINANCE_WH SET TAG COST_MANAGEMENT.TAGS.COST_CENTER = 'OPERATIONS';

-- ENG → DATA_PLATFORM (data engineering and infrastructure)
ALTER WAREHOUSE CALOPTIMA_ENG_WH     SET TAG COST_MANAGEMENT.TAGS.COST_CENTER = 'DATA_PLATFORM';

-- ANALYST + ML → ANALYTICS (analytics and data science)
ALTER WAREHOUSE CALOPTIMA_ANALYST_WH SET TAG COST_MANAGEMENT.TAGS.COST_CENTER = 'ANALYTICS';
ALTER WAREHOUSE CALOPTIMA_ML_WH      SET TAG COST_MANAGEMENT.TAGS.COST_CENTER = 'ANALYTICS';

-- Confirm tags are applied
SELECT OBJECT_NAME, TAG_VALUE AS cost_center
FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
WHERE TAG_NAME = 'COST_CENTER'
  AND DOMAIN = 'WAREHOUSE'
  AND OBJECT_NAME ILIKE 'CALOPTIMA%';

-- ── Step 5: Warehouse access — each role uses only its own warehouse ──────────
GRANT USAGE ON WAREHOUSE CALOPTIMA_EXEC_WH    TO ROLE CALOPTIMA_EXEC_ROLE;
GRANT USAGE ON WAREHOUSE CALOPTIMA_ENG_WH     TO ROLE CALOPTIMA_ENG_ROLE;
GRANT USAGE ON WAREHOUSE CALOPTIMA_ANALYST_WH TO ROLE CALOPTIMA_ANALYST_ROLE;
GRANT USAGE ON WAREHOUSE CALOPTIMA_FINANCE_WH TO ROLE CALOPTIMA_FINANCE_ROLE;
GRANT USAGE ON WAREHOUSE CALOPTIMA_ML_WH      TO ROLE CALOPTIMA_ML_ROLE;

-- ── Step 6: Data access — each role can query the benchmark dataset ───────────
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE CALOPTIMA_EXEC_ROLE;
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE CALOPTIMA_ENG_ROLE;
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE CALOPTIMA_ANALYST_ROLE;
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE CALOPTIMA_FINANCE_ROLE;
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE CALOPTIMA_ML_ROLE;

-- ── Step 7: Assign roles to ADMIN user for demo USE ROLE switching ────────────
GRANT ROLE CALOPTIMA_EXEC_ROLE    TO USER ADMIN;
GRANT ROLE CALOPTIMA_ENG_ROLE     TO USER ADMIN;
GRANT ROLE CALOPTIMA_ANALYST_ROLE TO USER ADMIN;
GRANT ROLE CALOPTIMA_FINANCE_ROLE TO USER ADMIN;
GRANT ROLE CALOPTIMA_ML_ROLE      TO USER ADMIN;

GRANT ROLE CALOPTIMA_EXEC_ROLE    TO ROLE ACCOUNTADMIN;
GRANT ROLE CALOPTIMA_ENG_ROLE     TO ROLE ACCOUNTADMIN;
GRANT ROLE CALOPTIMA_ANALYST_ROLE TO ROLE ACCOUNTADMIN;
GRANT ROLE CALOPTIMA_FINANCE_ROLE TO ROLE ACCOUNTADMIN;
GRANT ROLE CALOPTIMA_ML_ROLE      TO ROLE ACCOUNTADMIN;

-- Show all 5 warehouses with their cost center tags
SHOW WAREHOUSES LIKE 'CALOPTIMA%';
SHOW ROLES LIKE 'CALOPTIMA%';









-- =============================================================================
-- PART 2: ISOLATION PROOF (run after all 5 tabs have finished)
-- =============================================================================

-- ── Proof A: Credit spend per warehouse ──────────────────────────────────────
-- Note: WAREHOUSE_METERING_HISTORY has ~2-min ingestion lag.
SELECT
    WAREHOUSE_NAME,
    SUM(CREDITS_USED_COMPUTE)  AS compute_credits,
    SUM(CREDITS_USED)          AS total_credits,
    MIN(START_TIME)            AS first_activity,
    MAX(END_TIME)              AS last_activity
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE WAREHOUSE_NAME ILIKE 'CALOPTIMA%'
  AND START_TIME > DATEADD('hour', -1, CURRENT_TIMESTAMP())
GROUP BY WAREHOUSE_NAME
ORDER BY compute_credits DESC;

-- ── Proof B: Credit spend rolled up by COST_CENTER tag ───────────────────────
-- This is the chargeback / showback view — each department's actual compute bill.
-- Joins TAG_REFERENCES (which warehouse belongs to which cost center)
-- with WAREHOUSE_METERING_HISTORY (how many credits each warehouse used).
SELECT
    COALESCE(tr.TAG_VALUE, 'UNTAGGED')     AS cost_center,
    SUM(wmh.CREDITS_USED_COMPUTE)          AS compute_credits,
    SUM(wmh.CREDITS_USED)                  AS total_credits,
    COUNT(DISTINCT wmh.WAREHOUSE_NAME)     AS warehouse_count
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY wmh
LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES tr
    ON wmh.WAREHOUSE_ID = tr.OBJECT_ID
    AND tr.DOMAIN = 'WAREHOUSE'
    AND tr.TAG_NAME = 'COST_CENTER'
WHERE wmh.START_TIME > DATEADD('hour', -1, CURRENT_TIMESTAMP())
  AND wmh.WAREHOUSE_NAME ILIKE 'CALOPTIMA%'
GROUP BY cost_center
ORDER BY compute_credits DESC;
-- Expected:
--   DATA_PLATFORM → highest (ENG_WH alone, Large WH, heaviest workload)
--   ANALYTICS     → medium  (ANALYST_WH + ML_WH combined)
--   OPERATIONS    → lowest  (EXEC_WH + FINANCE_WH, lighter queries)
-- Talking point: CalOptima can run a chargeback report by department.
-- No manual time-tracking. Tag the warehouse once, Snowflake does the accounting.
-- In Snowsight: Admin → Cost Management → Consumption → filter by COST_CENTER tag.


-- =============================================================================
-- PART 3: CLEANUP
-- =============================================================================
/*
DROP WAREHOUSE IF EXISTS CALOPTIMA_EXEC_WH;
DROP WAREHOUSE IF EXISTS CALOPTIMA_ENG_WH;
DROP WAREHOUSE IF EXISTS CALOPTIMA_ANALYST_WH;
DROP WAREHOUSE IF EXISTS CALOPTIMA_FINANCE_WH;
DROP WAREHOUSE IF EXISTS CALOPTIMA_ML_WH;

DROP ROLE IF EXISTS CALOPTIMA_EXEC_ROLE;
DROP ROLE IF EXISTS CALOPTIMA_ENG_ROLE;
DROP ROLE IF EXISTS CALOPTIMA_ANALYST_ROLE;
DROP ROLE IF EXISTS CALOPTIMA_FINANCE_ROLE;
DROP ROLE IF EXISTS CALOPTIMA_ML_ROLE;

DROP TAG IF EXISTS COST_MANAGEMENT.TAGS.COST_CENTER;
DROP DATABASE IF EXISTS COST_MANAGEMENT;
*/

SELECT 'Workload isolation demo complete.' AS status;
