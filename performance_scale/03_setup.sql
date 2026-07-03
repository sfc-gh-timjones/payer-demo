-- =============================================================================
-- FILE: 03_setup.sql
-- PURPOSE: Run before EVERY demo run of 03_multi_cluster_concurrency.sql.
--   1. Drops leftover tasks and procedures from any previous run (clean slate)
--   2. Materializes TPCH_SF100 LINEITEM into a local database (first run only)
--   3. Creates the cleanup procedure
--   4. Pre-creates all 100 concurrent user tasks and resumes them
--      → spawn_concurrent_users only calls EXECUTE TASK at demo time (~15 sec)
--      → WITHOUT pre-creation, the proc creates+resumes+executes = ~1 min
--
-- NOTE: Step 2 CTAS copies 600M rows and takes 3-8 min — only runs once.
--       CREATE TABLE IF NOT EXISTS skips it on all subsequent runs.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_XS;


-- =============================================================================
-- STEP 1: CLEANUP — drop everything from any previous demo run
-- =============================================================================

CALL SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.cleanup_concurrent_users(100);
DROP PROCEDURE IF EXISTS SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.spawn_concurrent_users(INTEGER);
DROP PROCEDURE IF EXISTS SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.cleanup_concurrent_users(INTEGER);
DROP WAREHOUSE IF EXISTS CALOPTIMA_CONCURRENCY_WH;

SELECT 'Cleanup complete — ready to rebuild.' AS status;


-- =============================================================================
-- STEP 2: MATERIALIZE DATA (first run only — skipped if table already exists)
-- =============================================================================

CREATE DATABASE IF NOT EXISTS SNOWFLAKE_SAMPLE_DATA2;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100;

CREATE OR REPLACE WAREHOUSE CALOPTIMA_SETUP_WH
    WAREHOUSE_SIZE = SMALL
    AUTO_SUSPEND   = 30
    AUTO_RESUME    = TRUE;

USE WAREHOUSE CALOPTIMA_SETUP_WH;

CREATE TABLE IF NOT EXISTS SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.LINEITEM
    AS SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM;

SELECT COUNT(*) AS lineitem_rows FROM SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.LINEITEM;

DROP WAREHOUSE IF EXISTS CALOPTIMA_SETUP_WH;
USE WAREHOUSE WH_XS;

SELECT 'Data ready — SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.LINEITEM.' AS status;


-- =============================================================================
-- STEP 3: CREATE PROCEDURES
-- =============================================================================

-- Cleanup procedure (drops all tasks by count)
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

-- Spawn procedure — EXECUTE TASK only (tasks pre-created below, ~15 sec kickoff)
CREATE OR REPLACE PROCEDURE SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.spawn_concurrent_users(user_count INTEGER)
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
        session.sql(f"EXECUTE TASK SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.{task_name}").collect()
    return f"{user_count} concurrent users submitted to CALOPTIMA_CONCURRENCY_WH"
$$;

SELECT 'Procedures ready.' AS status;


-- =============================================================================
-- STEP 4: PRE-CREATE ALL 100 TASKS (runs once here so demo kickoff is fast)
-- Tasks stay RESUMED and ready — EXECUTE TASK re-fires them on every demo run.
-- Re-running spawn_concurrent_users after a batch finishes works cleanly:
-- tasks remain RESUMED and each EXECUTE TASK fires a fresh independent execution.
-- =============================================================================

CREATE OR REPLACE WAREHOUSE CALOPTIMA_CONCURRENCY_WH
    WAREHOUSE_SIZE    = SMALL
    GENERATION        = '2'
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 10
    SCALING_POLICY    = STANDARD
    AUTO_SUSPEND      = 30
    AUTO_RESUME       = TRUE
    COMMENT           = 'Multi-cluster: auto-scales 1→10 during open enrollment surge';

CREATE OR REPLACE PROCEDURE SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.precreate_tasks(user_count INTEGER)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'handler'
AS
$$
def handler(session, user_count):
    benchmark_sql = """
        SELECT
            RANDOM()                                               AS run_id,
            /* CALOPTIMA_CONCURRENCY_DEMO */ L_RETURNFLAG,
            L_LINESTATUS,
            SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT))               AS net_revenue,
            SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT) * (1 + L_TAX)) AS total_charge,
            AVG(L_DISCOUNT)                                        AS avg_discount,
            COUNT(*)                                               AS claim_count
        FROM SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.LINEITEM
        WHERE L_SHIPDATE <= DATEADD(DAY, -90, TO_DATE('1998-12-01'))
        GROUP BY L_RETURNFLAG, L_LINESTATUS
        ORDER BY L_RETURNFLAG, L_LINESTATUS
    """
    for i in range(1, user_count + 1):
        task_name = f"CONCURRENT_USER_{i:02d}"
        session.sql(f"""
            CREATE OR REPLACE TASK SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.{task_name}
                WAREHOUSE = CALOPTIMA_CONCURRENCY_WH
                SCHEDULE  = 'USING CRON 0 0 31 12 * UTC'
            AS
            {benchmark_sql}
        """).collect()
        session.sql(f"ALTER TASK SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.{task_name} RESUME").collect()
    return f"{user_count} tasks created and resumed"
$$;

CALL SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.precreate_tasks(100);
DROP PROCEDURE IF EXISTS SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.precreate_tasks(INTEGER);

SELECT 'Setup complete — run 03_multi_cluster_concurrency.sql to start the demo.' AS status;
