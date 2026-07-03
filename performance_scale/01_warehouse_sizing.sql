-- =============================================================================
-- FILE: 01_warehouse_sizing.sql
-- PURPOSE: CalOptima RFP 26-038 | Performance — Elastic Warehouse Sizing
--          Show how compute scales instantly and how query time drops with size.
--
-- DATA: SNOWFLAKE_SAMPLE_DATA.TPCH_SF100
--   The TPC-H dataset is a standard benchmark for analytical query engines.
--   SF100 = 600M rows in LINEITEM — comparable to years of CalOptima claims data.
--   Shared by default to all Snowflake accounts, no setup required.
--
-- DEMO FLOW:
--   1. Create demo warehouse at XSmall
--   2. Disable result cache — every run hits real compute
--   3. Run count + claims aggregation at XSmall (baseline)
--   4. Scale up to Small, then Medium — rerun same queries
--   5. Compare execution times from QUERY_HISTORY
--   6. Cleanup
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;

-- =============================================================================
-- PART 1: CREATE DEMO WAREHOUSE
-- =============================================================================

CREATE OR REPLACE WAREHOUSE CALOPTIMA_PERF_WH
    WAREHOUSE_SIZE = XSMALL
    AUTO_SUSPEND   = 60
    AUTO_RESUME    = TRUE
    COMMENT        = 'CalOptima performance demo — resize during demo to show elastic scaling';

USE WAREHOUSE CALOPTIMA_PERF_WH;
USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF100;

-- Disable result cache — forces every query to hit real compute, not cached results
ALTER SESSION SET USE_CACHED_RESULT = FALSE;


-- =============================================================================
-- PART 2: BASELINE — XSMALL
-- "Let's start with our smallest compute size and run a real analytical query."
-- =============================================================================

-- Simple scale check: how many line items are in the dataset?
-- Equivalent to: how many claim lines does CalOptima process?
SELECT COUNT(*) AS total_claim_lines FROM LINEITEM;
-- XSmall: ~20-40 seconds on 600M rows

-- TPC-H Query 1 — claims pricing summary by status flag
-- Equivalent to: monthly claims aggregation (sum billed, average discount, count by status)
SELECT
    L_RETURNFLAG                                              AS return_flag,
    L_LINESTATUS                                              AS line_status,
    SUM(L_QUANTITY)                                           AS sum_qty,
    SUM(L_EXTENDEDPRICE)                                      AS sum_base_price,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT))                   AS sum_disc_price,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT) * (1 + L_TAX))    AS sum_charge,
    AVG(L_QUANTITY)                                           AS avg_qty,
    AVG(L_EXTENDEDPRICE)                                      AS avg_price,
    AVG(L_DISCOUNT)                                           AS avg_disc,
    COUNT(*)                                                  AS count_order
FROM LINEITEM
WHERE L_SHIPDATE <= DATEADD(DAY, -90, TO_DATE('1998-12-01'))
GROUP BY  L_RETURNFLAG, L_LINESTATUS
ORDER BY  L_RETURNFLAG, L_LINESTATUS;
-- XSmall: note the elapsed time in Snowsight — this is your baseline


-- =============================================================================
-- PART 3: SCALE UP — ONE ALTER, INSTANT RESIZE
-- "No migration. No downtime. One command."
-- =============================================================================

-- Scale to Small — warehouse resizes in seconds while running
ALTER WAREHOUSE CALOPTIMA_PERF_WH SET WAREHOUSE_SIZE = SMALL;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT COUNT(*) AS total_claim_lines FROM LINEITEM;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT
    L_RETURNFLAG                                              AS return_flag,
    L_LINESTATUS                                              AS line_status,
    SUM(L_QUANTITY)                                           AS sum_qty,
    SUM(L_EXTENDEDPRICE)                                      AS sum_base_price,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT))                   AS sum_disc_price,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT) * (1 + L_TAX))    AS sum_charge,
    AVG(L_QUANTITY)                                           AS avg_qty,
    AVG(L_EXTENDEDPRICE)                                      AS avg_price,
    AVG(L_DISCOUNT)                                           AS avg_disc,
    COUNT(*)                                                  AS count_order
FROM LINEITEM
WHERE L_SHIPDATE <= DATEADD(DAY, -90, TO_DATE('1998-12-01'))
GROUP BY  L_RETURNFLAG, L_LINESTATUS
ORDER BY  L_RETURNFLAG, L_LINESTATUS;

-- Scale to Medium
ALTER WAREHOUSE CALOPTIMA_PERF_WH SET WAREHOUSE_SIZE = MEDIUM;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT COUNT(*) AS total_claim_lines FROM LINEITEM;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT
    L_RETURNFLAG                                              AS return_flag,
    L_LINESTATUS                                              AS line_status,
    SUM(L_QUANTITY)                                           AS sum_qty,
    SUM(L_EXTENDEDPRICE)                                      AS sum_base_price,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT))                   AS sum_disc_price,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT) * (1 + L_TAX))    AS sum_charge,
    AVG(L_QUANTITY)                                           AS avg_qty,
    AVG(L_EXTENDEDPRICE)                                      AS avg_price,
    AVG(L_DISCOUNT)                                           AS avg_disc,
    COUNT(*)                                                  AS count_order
FROM LINEITEM
WHERE L_SHIPDATE <= DATEADD(DAY, -90, TO_DATE('1998-12-01'))
GROUP BY  L_RETURNFLAG, L_LINESTATUS
ORDER BY  L_RETURNFLAG, L_LINESTATUS;
-- Talking point: same query, same data, dramatically different time.
-- No code changes. No data movement. No infrastructure tickets.


-- =============================================================================
-- PART 4: COMPARE EXECUTION TIMES FROM QUERY HISTORY
-- Note: ACCOUNT_USAGE.QUERY_HISTORY has ~2-min ingestion lag.
-- Run this after queries complete to show the side-by-side timing.
-- =============================================================================

USE WAREHOUSE WH_XS;

SELECT
    WAREHOUSE_SIZE,
    LEFT(QUERY_TEXT, 60)            AS query_preview,
    TOTAL_ELAPSED_TIME / 1000.0     AS elapsed_sec,
    BYTES_SCANNED / 1e9             AS gb_scanned,
    START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE WAREHOUSE_NAME = 'CALOPTIMA_PERF_WH'
  AND QUERY_TEXT ILIKE '%total_claim_lines%'
  AND START_TIME > DATEADD('hour', -1, CURRENT_TIMESTAMP())
ORDER BY START_TIME;
-- Expected: XSmall ~30s → Small ~15s → Medium ~8s (roughly halving each time)
-- Same data, same query — only the compute size changed.


-- =============================================================================
-- CLEANUP
-- =============================================================================

DROP WAREHOUSE IF EXISTS CALOPTIMA_PERF_WH;
ALTER SESSION UNSET USE_CACHED_RESULT;

SELECT 'Warehouse sizing demo complete.' AS status;
