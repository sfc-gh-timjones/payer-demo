-- =============================================================================
-- FILE: 02_workload_isolation_setup.sql  (COORDINATOR — run this first)
-- PURPOSE: Payer RFP 26-038 | Performance — Workload Isolation
--          Setup, proof, and cleanup for the 4-worksheet demo.
--
-- HOW TO RUN:
--   1. Run PART 1 here to create the cost center tag, roles, warehouses, and grants
--   2. Open the 4 tab worksheets and run them simultaneously:
--        02_tab1_exec.sql    → Tab 1
--        02_tab3_analyst.sql → Tab 2
--        02_tab4_finance.sql → Tab 3
--        02_tab5_ml.sql      → Tab 4
--   3. Come back here and run PART 2 (proof) after queries complete
--   4. Run PART 3 (cleanup) to drop all objects after the demo
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;


-- =============================================================================
-- PART 1: COST CENTER TAG + ROLES + WAREHOUSES + GRANTS
-- =============================================================================

-- ── Step 1: Create cost center tag ───────────────────────────────────────────
-- Tag is applied to warehouses. TAG_REFERENCES joins to WAREHOUSE_METERING_HISTORY
-- to show credit spend broken down by cost center — chargeback / showback reporting.
--
-- Two cost centers map the 4 workload teams into Payer departments:
--   OPERATIONS → EXEC_WH + FINANCE_WH  (executive dashboards + financial reports)
--   ANALYTICS  → ANALYST_WH + ML_WH    (ad-hoc analysis + data science / ML)
--
CREATE DATABASE IF NOT EXISTS COST_MANAGEMENT;
CREATE SCHEMA IF NOT EXISTS COST_MANAGEMENT.TAGS;

CREATE OR REPLACE TAG COST_MANAGEMENT.TAGS.COST_CENTER
    ALLOWED_VALUES 'OPERATIONS', 'ANALYTICS'
    COMMENT = 'Payer cost center for warehouse chargeback / showback reporting.';

-- ── Step 2: Create dedicated roles — one per workload persona ─────────────────
CREATE ROLE IF NOT EXISTS PAYER_EXEC_ROLE
    COMMENT = 'Executive team — read-only access to reporting warehouses';
CREATE ROLE IF NOT EXISTS PAYER_ANALYST_ROLE
    COMMENT = 'Analytics Innovators — ad-hoc exploration and analysis';
CREATE ROLE IF NOT EXISTS PAYER_FINANCE_ROLE
    COMMENT = 'Finance team — standard financial reporting and reconciliation';
CREATE ROLE IF NOT EXISTS PAYER_ML_ROLE
    COMMENT = 'Data Science / ML — feature engineering and model scoring';

-- ── Step 3: Create dedicated warehouses — one per role ────────────────────────
CREATE OR REPLACE WAREHOUSE PAYER_EXEC_WH
    WAREHOUSE_SIZE = XSMALL  AUTO_SUSPEND = 30  AUTO_RESUME = TRUE
    COMMENT = 'Executive dashboards and board-level population health reports';

CREATE OR REPLACE WAREHOUSE PAYER_ANALYST_WH
    WAREHOUSE_SIZE = MEDIUM  AUTO_SUSPEND = 30  AUTO_RESUME = TRUE
    COMMENT = 'Analytics Innovators — ad-hoc and exploratory analysis';

CREATE OR REPLACE WAREHOUSE PAYER_FINANCE_WH
    WAREHOUSE_SIZE = SMALL   AUTO_SUSPEND = 30  AUTO_RESUME = TRUE
    COMMENT = 'Finance Team — standard reporting and financial reconciliation';

CREATE OR REPLACE WAREHOUSE PAYER_ML_WH
    WAREHOUSE_SIZE = MEDIUM  AUTO_SUSPEND = 30  AUTO_RESUME = TRUE
    COMMENT = 'Data Science — ML feature engineering and model scoring';

-- ── Step 4: Apply COST_CENTER tag to each warehouse ───────────────────────────
-- EXEC + FINANCE → OPERATIONS (business reporting)
ALTER WAREHOUSE PAYER_EXEC_WH    SET TAG COST_MANAGEMENT.TAGS.COST_CENTER = 'OPERATIONS';
ALTER WAREHOUSE PAYER_FINANCE_WH SET TAG COST_MANAGEMENT.TAGS.COST_CENTER = 'OPERATIONS';

-- ANALYST + ML → ANALYTICS (analytics and data science)
ALTER WAREHOUSE PAYER_ANALYST_WH SET TAG COST_MANAGEMENT.TAGS.COST_CENTER = 'ANALYTICS';
ALTER WAREHOUSE PAYER_ML_WH      SET TAG COST_MANAGEMENT.TAGS.COST_CENTER = 'ANALYTICS';

-- Confirm tags are applied
SELECT OBJECT_NAME, TAG_VALUE AS cost_center
FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
WHERE TAG_NAME = 'COST_CENTER'
  AND DOMAIN = 'WAREHOUSE'
  AND OBJECT_NAME ILIKE 'PAYER%';

-- ── Step 5: Warehouse access — each role uses only its own warehouse ───────────
GRANT USAGE ON WAREHOUSE PAYER_EXEC_WH    TO ROLE PAYER_EXEC_ROLE;
GRANT USAGE ON WAREHOUSE PAYER_ANALYST_WH TO ROLE PAYER_ANALYST_ROLE;
GRANT USAGE ON WAREHOUSE PAYER_FINANCE_WH TO ROLE PAYER_FINANCE_ROLE;
GRANT USAGE ON WAREHOUSE PAYER_ML_WH      TO ROLE PAYER_ML_ROLE;

-- ── Step 6: Data access — each role can query the benchmark dataset ────────────
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE PAYER_EXEC_ROLE;
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE PAYER_ANALYST_ROLE;
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE PAYER_FINANCE_ROLE;
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE PAYER_ML_ROLE;

-- ── Step 7: Assign roles to ADMIN user for demo USE ROLE switching ─────────────
GRANT ROLE PAYER_EXEC_ROLE    TO USER ADMIN;
GRANT ROLE PAYER_ANALYST_ROLE TO USER ADMIN;
GRANT ROLE PAYER_FINANCE_ROLE TO USER ADMIN;
GRANT ROLE PAYER_ML_ROLE      TO USER ADMIN;

GRANT ROLE PAYER_EXEC_ROLE    TO ROLE ACCOUNTADMIN;
GRANT ROLE PAYER_ANALYST_ROLE TO ROLE ACCOUNTADMIN;
GRANT ROLE PAYER_FINANCE_ROLE TO ROLE ACCOUNTADMIN;
GRANT ROLE PAYER_ML_ROLE      TO ROLE ACCOUNTADMIN;

-- Show all 4 warehouses with their cost center tags
SHOW WAREHOUSES LIKE 'PAYER%';
SHOW ROLES LIKE 'PAYER%';

-- =============================================================================
-- PART 3: CLEANUP
-- =============================================================================
/*
DROP WAREHOUSE IF EXISTS PAYER_EXEC_WH;
DROP WAREHOUSE IF EXISTS PAYER_ANALYST_WH;
DROP WAREHOUSE IF EXISTS PAYER_FINANCE_WH;
DROP WAREHOUSE IF EXISTS PAYER_ML_WH;

DROP ROLE IF EXISTS PAYER_EXEC_ROLE;
DROP ROLE IF EXISTS PAYER_ANALYST_ROLE;
DROP ROLE IF EXISTS PAYER_FINANCE_ROLE;
DROP ROLE IF EXISTS PAYER_ML_ROLE;

DROP TAG IF EXISTS COST_MANAGEMENT.TAGS.COST_CENTER;
DROP DATABASE IF EXISTS COST_MANAGEMENT;
*/

SELECT 'Workload isolation demo complete.' AS status;
