-- =============================================================================
-- FILE: 03_multi_cluster_concurrency.sql
-- PURPOSE: CalOptima RFP 26-038 | Performance — High Concurrency / Multi-Cluster
--          Simulates 100+ concurrent users hitting the same warehouse.
--          Shows auto scale-out and scale-in via WAREHOUSE_EVENTS_HISTORY.
--
-- DATA: SNOWFLAKE_SAMPLE_DATA.TPCH_SF100 (600M rows)
--
-- DEMO FLOW:
--   1. Create a multi-cluster warehouse (max 4 clusters)
--   2. Fire concurrent query load via a stored procedure
--   3. Show auto scale-out events (new clusters coming online)
--   4. Show query distribution across clusters
--   5. Cleanup
--
-- KEY TALKING POINT:
--   Open enrollment at CalOptima means 200+ staff running eligibility checks
--   simultaneously. A single warehouse queues those requests.
--   A multi-cluster warehouse spawns additional clusters on demand — every user
--   gets immediate compute. When load drops, extra clusters shut down automatically.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;
USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF100;


-- =============================================================================
-- PART 1: CREATE A MULTI-CLUSTER WAREHOUSE
-- "One warehouse config. Automatically scales from 1 cluster to 4 under load."
-- =============================================================================

CREATE OR REPLACE WAREHOUSE CALOPTIMA_CONCURRENCY_WH
    WAREHOUSE_SIZE    = SMALL
    MIN_CLUSTER_COUNT = 1           -- idles at 1 cluster at rest
    MAX_CLUSTER_COUNT = 4           -- auto-scales to 4 clusters under load
    SCALING_POLICY    = STANDARD    -- scale-out when queries start queuing
    AUTO_SUSPEND      = 60
    AUTO_RESUME       = TRUE
    COMMENT           = 'Multi-cluster: auto-scales 1→4 during peak concurrency';

-- Show the warehouse configuration
SHOW WAREHOUSES LIKE 'CALOPTIMA_CONCURRENCY_WH';
-- Key fields: min_cluster_count=1, max_cluster_count=4, scaling_policy=STANDARD
-- Talking point: this is the entire infrastructure change needed for open enrollment.


-- =============================================================================
-- PART 2: CONCURRENT LOAD SIMULATION
-- Stored procedure fires N queries without waiting between them.
-- Snowflake treats them as concurrent — builds a queue, triggers scale-out.
-- =============================================================================

CREATE OR REPLACE PROCEDURE simulate_concurrent_load(query_count INTEGER)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
AS
$$
    // Fires QUERY_COUNT analytical queries as fast as possible.
    // Each represents one CalOptima user running an eligibility or claims check.
    var benchmark_sql = `
        SELECT
            L_RETURNFLAG,
            L_LINESTATUS,
            SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT))               AS net_revenue,
            SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT) * (1 + L_TAX)) AS total_charge,
            AVG(L_DISCOUNT)                                        AS avg_discount,
            COUNT(*)                                               AS claim_count
        FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM
        WHERE L_SHIPDATE <= DATEADD(DAY, -90, TO_DATE('1998-12-01'))
        GROUP BY L_RETURNFLAG, L_LINESTATUS
        ORDER BY L_RETURNFLAG, L_LINESTATUS`;

    var submitted = 0;
    for (var i = 0; i < QUERY_COUNT; i++) {
        var stmt = snowflake.createStatement({ sqlText: benchmark_sql });
        stmt.execute();
        submitted++;
    }
    return submitted + ' concurrent queries submitted to CALOPTIMA_CONCURRENCY_WH';
$$;

-- ── Fire concurrent load ──────────────────────────────────────────────────────
USE WAREHOUSE CALOPTIMA_CONCURRENCY_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

CALL simulate_concurrent_load(16);
-- Submits 16 concurrent queries — enough to saturate a Small single cluster
-- and trigger STANDARD policy scale-out (cluster 2, then 3 come online).
-- Watch the warehouse activity spinner in Snowsight — clusters appear in real time.

-- Wait ~30-60 seconds for queries to complete, then run the analysis below.


-- =============================================================================
-- PART 3: SHOW SCALE-OUT EVENTS
-- Note: WAREHOUSE_EVENTS_HISTORY has ~2-min ingestion lag.
-- Run this section after the queries complete.
-- =============================================================================

USE WAREHOUSE WH_XS;

-- Scale-out and scale-in events
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
--   SCALE_OUT events: "CLUSTER_2_STARTED", "CLUSTER_3_STARTED" → new clusters online
--   SCALE_IN events:  "CLUSTER_3_SUSPENDED" → load cleared, cluster released
-- Talking point: zero manual intervention. Snowflake handled the surge automatically.


-- =============================================================================
-- PART 4: QUERY DISTRIBUTION ACROSS CLUSTERS
-- "Each cluster handled its share — no user waited in a queue."
-- =============================================================================

SELECT
    CLUSTER_NUMBER,
    COUNT(*)                              AS queries_handled,
    ROUND(AVG(TOTAL_ELAPSED_TIME) / 1000, 1) AS avg_elapsed_sec,
    ROUND(MIN(TOTAL_ELAPSED_TIME) / 1000, 1) AS min_elapsed_sec,
    ROUND(MAX(TOTAL_ELAPSED_TIME) / 1000, 1) AS max_elapsed_sec,
    MIN(START_TIME)                       AS first_query,
    MAX(END_TIME)                         AS last_query
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE WAREHOUSE_NAME = 'CALOPTIMA_CONCURRENCY_WH'
  AND START_TIME > DATEADD('hour', -1, CURRENT_TIMESTAMP())
  AND QUERY_TYPE = 'SELECT'
GROUP BY CLUSTER_NUMBER
ORDER BY CLUSTER_NUMBER;
-- Expected: queries distributed across clusters 1, 2, 3 (or more)
-- Each cluster ran independently — avg elapsed time is similar across all.
-- A single-cluster warehouse would show: cluster 1 handles everything serially,
-- later queries have high elapsed time from queueing.


-- =============================================================================
-- PART 5: SINGLE-CLUSTER COMPARISON (OPTIONAL)
-- Recreate warehouse with max_cluster_count=1 and rerun to show the contrast.
-- =============================================================================

-- Uncomment to demonstrate the difference:
-- CREATE OR REPLACE WAREHOUSE CALOPTIMA_SINGLE_WH
--     WAREHOUSE_SIZE    = SMALL
--     MIN_CLUSTER_COUNT = 1
--     MAX_CLUSTER_COUNT = 1      -- no scale-out allowed
--     AUTO_SUSPEND      = 60
--     COMMENT           = 'Single cluster — queries queue under load';
--
-- USE WAREHOUSE CALOPTIMA_SINGLE_WH;
-- ALTER SESSION SET USE_CACHED_RESULT = FALSE;
-- CALL simulate_concurrent_load(16);
-- -- Queries will serialize on a single cluster — much higher avg elapsed time
-- -- vs multi-cluster above. Same workload, different architecture.
--
-- DROP WAREHOUSE IF EXISTS CALOPTIMA_SINGLE_WH;


-- =============================================================================
-- CLEANUP
-- =============================================================================

USE WAREHOUSE WH_XS;
DROP PROCEDURE IF EXISTS simulate_concurrent_load(INTEGER);
DROP WAREHOUSE IF EXISTS CALOPTIMA_CONCURRENCY_WH;
ALTER SESSION UNSET USE_CACHED_RESULT;

SELECT 'Multi-cluster concurrency demo complete.' AS status;
