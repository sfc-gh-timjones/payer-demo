-- =============================================================================
-- FILE: 03_multi_cluster_concurrency.sql
-- PURPOSE: CalOptima RFP 26-038 | Performance — High Concurrency / Multi-Cluster
--          Simulates N concurrent users via Snowflake Tasks (genuinely async).
--          Shows auto scale-out and scale-in via WAREHOUSE_EVENTS_HISTORY.
--
-- DATA: SNOWFLAKE_SAMPLE_DATA.TPCH_SF100 (600M rows)
--
-- WHY TASKS (NOT A LOOP):
--   EXECUTE TASK is asynchronous — it fires the task and returns immediately.
--   Calling it N times in sequence submits N concurrent executions to the
--   warehouse. A loop inside a stored procedure would serialize queries;
--   tasks run independently on the warehouse and trigger genuine concurrency.
--
-- DEMO FLOW:
--   1. Create multi-cluster warehouse (min=1, max=4)
--   2. Python stored procedure creates N tasks + fires them all concurrently
--   3. Show scale-out events (new clusters coming online)
--   4. Show query distribution across clusters
--   5. Cleanup
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;
USE DATABASE SNOWFLAKE_SAMPLE_DATA2;
USE SCHEMA TPCH_SF100;


-- =============================================================================
-- PART 1: CREATE THE MULTI-CLUSTER WAREHOUSE
-- "One config change — Snowflake handles the rest automatically."
-- =============================================================================

CREATE OR REPLACE WAREHOUSE CALOPTIMA_CONCURRENCY_WH
    WAREHOUSE_SIZE    = SMALL
    GENERATION = '2'
    MIN_CLUSTER_COUNT = 1           -- idles at 1 cluster at rest (cost-efficient)
    MAX_CLUSTER_COUNT = 10           -- scales out to 10 under heavy concurrent load
    SCALING_POLICY    = STANDARD    -- adds clusters when queries start queueing
    AUTO_SUSPEND      = 30
    AUTO_RESUME       = TRUE
    COMMENT           = 'Multi-cluster: auto-scales 1→10 during open enrollment surge';

USE WAREHOUSE WH_XS; 

SHOW WAREHOUSES LIKE 'CALOPTIMA_CONCURRENCY_WH';
-- Key columns: min_cluster_count=1, max_cluster_count=4, scaling_policy=STANDARD
-- No hardware provisioning. No capacity planning. No on-call engineer.


-- =============================================================================
-- PART 2: CONCURRENT LOAD — PYTHON STORED PROCEDURE USING TASKS
--
-- The procedure creates N Snowflake Tasks, resumes them, then fires all N
-- via EXECUTE TASK (which is non-blocking/async). This submits N independent
-- query executions concurrently to CALOPTIMA_CONCURRENCY_WH, building a
-- queue that triggers the STANDARD scaling policy scale-out.
-- =============================================================================

CREATE OR REPLACE PROCEDURE SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.spawn_concurrent_users(user_count INTEGER)
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
            L_RETURNFLAG,
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

    # Step 1: Create one task per simulated concurrent user
    for i in range(1, user_count + 1):
        task_name = f"CONCURRENT_USER_{i:02d}"
        session.sql(f"""
            CREATE OR REPLACE TASK {task_name}
                WAREHOUSE = CALOPTIMA_CONCURRENCY_WH
                SCHEDULE  = 'USING CRON 0 0 31 12 * UTC'
            AS
            {benchmark_sql}
        """).collect()
        session.sql(f"ALTER TASK {task_name} RESUME").collect()

    # Step 2: Fire all tasks concurrently
    # EXECUTE TASK is async — each call returns immediately while the task runs.
    # Calling it N times submits N concurrent executions to the warehouse.
    for i in range(1, user_count + 1):
        task_name = f"CONCURRENT_USER_{i:02d}"
        session.sql(f"EXECUTE TASK {task_name}").collect()

    return f"{user_count} concurrent users submitted to CALOPTIMA_CONCURRENCY_WH"
$$;

-- ── Fire concurrent load 
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT';

CALL SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.spawn_concurrent_users(30);
-- Submits concurrent query executions to CALOPTIMA_CONCURRENCY_WH.

SHOW WAREHOUSES LIKE 'CALOPTIMA_CONCURRENCY_WH';
-- =============================================================================
-- PART 3: SHOW SCALE-OUT EVENTS
-- Note: WAREHOUSE_EVENTS_HISTORY has ~2-min ingestion lag.
-- =============================================================================

SELECT
    TIMESTAMP,
    WAREHOUSE_NAME,
    CLUSTER_NUMBER,
    EVENT_NAME,
    EVENT_REASON,
    EVENT_STATE
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_EVENTS_HISTORY
WHERE WAREHOUSE_NAME = 'CALOPTIMA_CONCURRENCY_WH'
  AND TIMESTAMP > DATEADD('hour', -1, CURRENT_TIMESTAMP())
ORDER BY TIMESTAMP;
-- Look for:
--   SCALE_OUT events: Cluster 2 and 3 coming online as queue builds
--   SCALE_IN events:  Clusters suspending after load clears
-- Talking point: zero manual intervention.
-- Snowflake detected the queue, provisioned extra clusters, released them.


-- =============================================================================
-- PART 4: QUERY DISTRIBUTION ACROSS CLUSTERS
-- "Every user got immediate compute. No one sat in a queue."
-- =============================================================================

SELECT
    CLUSTER_NUMBER,
    COUNT(*)                                     AS queries_handled,
    ROUND(AVG(TOTAL_ELAPSED_TIME) / 1000, 1)     AS avg_elapsed_sec,
    ROUND(MIN(TOTAL_ELAPSED_TIME) / 1000, 1)     AS min_elapsed_sec,
    ROUND(MAX(TOTAL_ELAPSED_TIME) / 1000, 1)     AS max_elapsed_sec
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE WAREHOUSE_NAME = 'CALOPTIMA_CONCURRENCY_WH'
  AND START_TIME > DATEADD('hour', -1, CURRENT_TIMESTAMP())
  AND QUERY_TYPE = 'SELECT'
GROUP BY CLUSTER_NUMBER
ORDER BY CLUSTER_NUMBER;
-- Expected: queries spread across clusters 1, 2, 3
-- Avg elapsed time is similar across clusters — load was balanced.
-- Without multi-cluster: all 12 queries serialize on cluster 1,
-- and later queries show much higher elapsed time from queueing.


-- =============================================================================
-- PART 5: TASK EXECUTION HISTORY (available sooner than WAREHOUSE_EVENTS)
-- =============================================================================

SELECT
    NAME                  AS task_name,
    STATE,
    SCHEDULED_TIME,
    QUERY_START_TIME,
    COMPLETED_TIME,
    DATEDIFF('second', QUERY_START_TIME, COMPLETED_TIME) AS elapsed_sec,
    ERROR_MESSAGE
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('hour', -1, CURRENT_TIMESTAMP()),
    RESULT_LIMIT => 50
))
WHERE NAME ILIKE 'CONCURRENT_USER_%'
ORDER BY SCHEDULED_TIME;
-- Shows all 12 tasks fired at roughly the same time — confirming true concurrency.
-- QUERY_START_TIME values will overlap, not be sequential.


-- =============================================================================
-- CLEANUP
-- =============================================================================

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

CALL SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.cleanup_concurrent_users(50);
DROP PROCEDURE IF EXISTS SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.spawn_concurrent_users(INTEGER);
DROP PROCEDURE IF EXISTS SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.cleanup_concurrent_users(INTEGER);
DROP WAREHOUSE IF EXISTS CALOPTIMA_CONCURRENCY_WH;

SELECT 'Multi-cluster concurrency demo complete.' AS status;
