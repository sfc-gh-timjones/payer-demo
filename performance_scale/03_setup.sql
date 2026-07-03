-- =============================================================================
-- FILE: 03_setup.sql
-- PURPOSE: Run before EVERY demo run of 03_multi_cluster_concurrency.sql.
--   1. Drops leftover tasks from any previous run (clean slate)
--   2. Materializes TPCH_SF100 LINEITEM into a local database on first run
--      (stored procedures and tasks cannot reference the shared SNOWFLAKE_SAMPLE_DATA)
--
-- NOTE: The CTAS (step 2) copies 600M rows and takes 3-8 min — only runs
--       on first execution. CREATE TABLE IF NOT EXISTS skips it on repeat runs.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_XS;


-- =============================================================================
-- STEP 1: CLEANUP — drop any tasks left over from a previous demo run
-- Safe to run even if no tasks exist (IF EXISTS guards every DROP).
-- =============================================================================


DROP PROCEDURE IF EXISTS SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.spawn_concurrent_users(INTEGER);
DROP PROCEDURE IF EXISTS SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.cleanup_concurrent_users(INTEGER);
DROP WAREHOUSE IF EXISTS CALOPTIMA_CONCURRENCY_WH;

SELECT 'Cleanup complete — ready for demo.' AS status;


-- =============================================================================
-- STEP 2: MATERIALIZE DATA (first run only — skipped if table already exists)
-- =============================================================================
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_SAMPLE_DATA2;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100;

-- Use a Medium warehouse for the bulk copy — XSmall is too slow for 600M rows
CREATE OR REPLACE WAREHOUSE CALOPTIMA_SETUP_WH
    WAREHOUSE_SIZE = SMALL 
    AUTO_SUSPEND   = 30
    AUTO_RESUME    = TRUE;

USE WAREHOUSE CALOPTIMA_SETUP_WH;

-- Materialize LINEITEM (600M rows — this is the primary benchmark table)
CREATE TABLE IF NOT EXISTS SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.LINEITEM
    AS SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM;

-- Confirm row count
SELECT COUNT(*) AS lineitem_rows FROM SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.LINEITEM;
-- Expected: ~600,037,902 rows

-- Drop the setup warehouse — no longer needed
DROP WAREHOUSE IF EXISTS CALOPTIMA_SETUP_WH;

SELECT 'Setup complete — SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.LINEITEM is ready.' AS status;


-- =============================================================================
-- STEP 3: CREATE CLEANUP PROCEDURE
-- =============================================================================

USE WAREHOUSE WH_XS; 

CREATE OR REPLACE PROCEDURE SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.cleanup_concurrent_users(user_count INTEGER)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'handler'
AS
$$
def handler(session, user_count):
    for i in range(1, user_count + 1):
        task_name = f"CONCURRENT_USER_{i:02d}"
        session.sql(f"DROP TASK IF EXISTS {task_name}").collect()
    return f"{user_count} tasks dropped"
$$;

SELECT 'Cleanup procedure ready.' AS status;

CALL SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.cleanup_concurrent_users(50);
