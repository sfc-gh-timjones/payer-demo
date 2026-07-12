-- =============================================================================
-- FILE: 01_warehouse_sizing.sql
-- PURPOSE: CalOptima RFP 26-038 | Performance — Elastic Warehouse Sizing
--          Show how query time drops instantly when you scale compute up.
--
-- HOW TO RUN:
--   1. Run SETUP (Part 1) once
--   2. Disable cache (Part 2) — verify it's off
--   3. Uncomment ONE warehouse size in Part 3 and run that line
--   4. Run the benchmark query in Part 4 — note the elapsed time in Snowsight
--   5. Go back to Part 3, switch to the next size, run Part 4 again
--   6. Repeat to compare — same query, different compute, different time
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;

-- =============================================================================
-- PART 1: SETUP
-- =============================================================================

CREATE OR REPLACE WAREHOUSE WH_ENTERPRISE_ANALYTICS
    WAREHOUSE_SIZE = MEDIUM
    AUTO_SUSPEND   = 30
    AUTO_RESUME    = TRUE
    COMMENT        = 'CalOptima performance demo — resize during demo to show elastic scaling';

USE WAREHOUSE WH_ENTERPRISE_ANALYTICS;
-- USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF1; --scale factor of 1
-- USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF10; --scale factor of 10
-- USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF100; --scale factor of 100 
USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000; --scale factor of 1000


-- =============================================================================
-- PART 2: DISABLE RESULT CACHE
-- Run this once. Every subsequent query hits real compute, not a cached result.
-- =============================================================================

ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT';
-- Confirm: value = false


-- =============================================================================
-- PART 3: SET WAREHOUSE SIZE
-- Uncomment ONE line, run it, then run the benchmark query below.
-- Swap sizes to compare performance.
-- =============================================================================

-- ALTER WAREHOUSE WH_ENTERPRISE_ANALYTICS SET WAREHOUSE_SIZE = XSMALL;
-- ALTER WAREHOUSE WH_ENTERPRISE_ANALYTICS SET WAREHOUSE_SIZE = SMALL;
-- ALTER WAREHOUSE WH_ENTERPRISE_ANALYTICS SET WAREHOUSE_SIZE = MEDIUM;
-- ALTER WAREHOUSE WH_ENTERPRISE_ANALYTICS SET WAREHOUSE_SIZE = LARGE;
-- ALTER WAREHOUSE WH_ENTERPRISE_ANALYTICS SET WAREHOUSE_SIZE = XLARGE;

SELECT 'Record Count: ' || TO_VARCHAR(COUNT(*), 'FM999,999,999,999')
FROM LINEITEM;

-- =============================================================================
-- PART 4: BENCHMARK QUERY — RUN AFTER EACH SIZE CHANGE
-- TPC-H Query 1: claims pricing summary by return flag and line status.
-- Equivalent to: monthly claims aggregation across 600M claim lines.
-- Watch the elapsed time in the Snowsight query result header.
-- =============================================================================

SELECT
    L_RETURNFLAG                                              AS return_flag,
    L_LINESTATUS                                              AS line_status,
    SUM(L_QUANTITY)                                           AS sum_qty,
    SUM(L_EXTENDEDPRICE)                                      AS sum_base_price,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT))                   AS sum_disc_price,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT) * (1 + L_TAX))     AS sum_charge,
    AVG(L_QUANTITY)                                           AS avg_qty,
    AVG(L_EXTENDEDPRICE)                                      AS avg_price,
    AVG(L_DISCOUNT)                                           AS avg_disc,
    COUNT(*)                                                  AS count_order
FROM LINEITEM
WHERE L_SHIPDATE <= DATEADD(DAY, -90, TO_DATE('1998-12-01'))
GROUP BY  L_RETURNFLAG, L_LINESTATUS
ORDER BY  L_RETURNFLAG, L_LINESTATUS;


-- =============================================================================
-- PART 5: COMPARE ALL RUNS IN QUERY HISTORY (run at end of demo)
-- Note: ACCOUNT_USAGE.QUERY_HISTORY has ~2-min ingestion lag.
-- =============================================================================

USE WAREHOUSE WH_XS;

SELECT
    WAREHOUSE_SIZE,
    TOTAL_ELAPSED_TIME / 1000.0  AS elapsed_sec,
    BYTES_SCANNED / 1e9          AS gb_scanned,
    START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE WAREHOUSE_NAME = 'WH_ENTERPRISE_ANALYTICS'
  AND QUERY_TEXT ILIKE '%sum_charge%'
  AND START_TIME > DATEADD('hour', -1, CURRENT_TIMESTAMP())
ORDER BY START_TIME;
-- Each row = one run at a different warehouse size
-- Talking point: same query, same data — only compute size changed.
-- No code changes. No data movement. No infrastructure tickets.


-- =============================================================================
-- CLEANUP
-- =============================================================================

DROP WAREHOUSE IF EXISTS WH_ENTERPRISE_ANALYTICS;
ALTER SESSION UNSET USE_CACHED_RESULT;
