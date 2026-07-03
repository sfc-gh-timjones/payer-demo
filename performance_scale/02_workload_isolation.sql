-- =============================================================================
-- FILE: 02_workload_isolation.sql
-- PURPOSE: CalOptima RFP 26-038 | Performance — Workload Isolation
--          5 independent virtual warehouses, one shared dataset.
--          A heavy overnight ETL job cannot slow down the CEO's morning report.
--
-- DATA: SNOWFLAKE_SAMPLE_DATA.TPCH_SF100 (600M rows)
--
-- DEMO FLOW:
--   1. Create 5 named warehouses — one per CalOptima workload persona
--   2. Run persona-appropriate queries on each warehouse independently
--   3. Show per-warehouse credit consumption to prove isolation
--   4. Cleanup
--
-- KEY TALKING POINT:
--   All 5 warehouses read the same underlying LINEITEM data simultaneously.
--   Snowflake's shared-disk architecture means no data copying, no locking.
--   Each team gets dedicated, isolated compute — zero interference.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;
USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF100;


-- =============================================================================
-- PART 1: CREATE 5 WORKLOAD WAREHOUSES
-- "Every team at CalOptima gets their own compute. One line per warehouse."
-- =============================================================================

CREATE OR REPLACE WAREHOUSE CALOPTIMA_EXEC_WH
    WAREHOUSE_SIZE = SMALL   AUTO_SUSPEND = 60  AUTO_RESUME = TRUE
    COMMENT = 'Executive dashboards and board-level population health reports';

CREATE OR REPLACE WAREHOUSE CALOPTIMA_ENG_WH
    WAREHOUSE_SIZE = LARGE   AUTO_SUSPEND = 60  AUTO_RESUME = TRUE
    COMMENT = 'Data engineering — ETL, CDC, bulk claims transforms';

CREATE OR REPLACE WAREHOUSE CALOPTIMA_ANALYST_WH
    WAREHOUSE_SIZE = MEDIUM  AUTO_SUSPEND = 60  AUTO_RESUME = TRUE
    COMMENT = 'Analytics Innovators — ad-hoc and exploratory analysis';

CREATE OR REPLACE WAREHOUSE CALOPTIMA_BA_WH
    WAREHOUSE_SIZE = SMALL   AUTO_SUSPEND = 60  AUTO_RESUME = TRUE
    COMMENT = 'Business Analysts — standard reporting and dashboards';

CREATE OR REPLACE WAREHOUSE CALOPTIMA_ML_WH
    WAREHOUSE_SIZE = MEDIUM  AUTO_SUSPEND = 60  AUTO_RESUME = TRUE
    COMMENT = 'Data Science — ML feature engineering and model scoring';

-- Show all 5 warehouses — audience sees the full workload picture
SHOW WAREHOUSES LIKE 'CALOPTIMA%';


-- =============================================================================
-- PART 2: RUN WORKLOAD-APPROPRIATE QUERIES ON EACH WAREHOUSE
-- "Same data. Five isolated compute layers. Zero interference."
-- =============================================================================

-- ── EXECUTIVE: lightweight population health summary ─────────────────────────
-- Represents: board-level quality metrics dashboard — fast, simple
USE WAREHOUSE CALOPTIMA_EXEC_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT
    L_RETURNFLAG                     AS claim_status,
    COUNT(*)                         AS claim_count,
    SUM(L_EXTENDEDPRICE)             AS total_billed,
    ROUND(AVG(L_DISCOUNT) * 100, 2)  AS avg_discount_pct
FROM LINEITEM
GROUP BY L_RETURNFLAG
ORDER BY total_billed DESC;
-- Small warehouse — fast. Executive never waits for engineers to finish.

-- ── DATA ENGINEER: heavy bulk aggregation ────────────────────────────────────
-- Represents: nightly claims reconciliation / ETL job — large, slow
-- This runs concurrently with EXEC_WH above — completely isolated
USE WAREHOUSE CALOPTIMA_ENG_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT
    L_SUPPKEY,
    L_RETURNFLAG,
    L_LINESTATUS,
    SUM(L_QUANTITY)                                        AS total_qty,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT) * (1 + L_TAX)) AS total_charge,
    COUNT(DISTINCT L_ORDERKEY)                             AS unique_claims,
    MIN(L_SHIPDATE)                                        AS earliest_ship,
    MAX(L_SHIPDATE)                                        AS latest_ship
FROM LINEITEM
GROUP BY L_SUPPKEY, L_RETURNFLAG, L_LINESTATUS
ORDER BY total_charge DESC
LIMIT 200;
-- Large warehouse — uses more credits, but that cost stays on ENG_WH.
-- EXEC_WH credit counter is untouched.

-- ── ANALYTICS INNOVATOR: exploratory trend analysis ──────────────────────────
-- Represents: ad-hoc population trend analysis
USE WAREHOUSE CALOPTIMA_ANALYST_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT
    YEAR(L_SHIPDATE)    AS claim_year,
    MONTH(L_SHIPDATE)   AS claim_month,
    L_RETURNFLAG        AS claim_status,
    COUNT(*)            AS claim_count,
    SUM(L_EXTENDEDPRICE) AS total_revenue,
    AVG(L_DISCOUNT)     AS avg_discount
FROM LINEITEM
GROUP BY 1, 2, 3
ORDER BY claim_year, claim_month, claim_status;

-- ── BUSINESS ANALYST: standard operational report ────────────────────────────
USE WAREHOUSE CALOPTIMA_BA_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT
    L_LINESTATUS,
    COUNT(*)                                    AS line_count,
    SUM(L_EXTENDEDPRICE)                        AS gross_billed,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT))     AS net_billed,
    SUM(L_EXTENDEDPRICE * L_DISCOUNT)           AS total_discount
FROM LINEITEM
WHERE L_SHIPDATE BETWEEN '1996-01-01' AND '1998-12-31'
GROUP BY L_LINESTATUS
ORDER BY gross_billed DESC;

-- ── ML / DATA SCIENCE: feature engineering (joins, percentiles) ──────────────
USE WAREHOUSE CALOPTIMA_ML_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT
    O.O_CUSTKEY,
    COUNT(L.L_LINENUMBER)                              AS claim_line_count,
    SUM(L.L_EXTENDEDPRICE)                             AS total_billed,
    AVG(L.L_DISCOUNT)                                  AS avg_discount,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY L.L_EXTENDEDPRICE) AS median_claim_amt
FROM ORDERS   O
JOIN LINEITEM  L ON O.O_ORDERKEY = L.L_ORDERKEY
GROUP BY O.O_CUSTKEY
ORDER BY total_billed DESC
LIMIT 500;


-- =============================================================================
-- PART 3: WORKLOAD ISOLATION PROOF — PER-WAREHOUSE CREDIT USAGE
-- Note: WAREHOUSE_METERING_HISTORY has ~2-min lag. Run this after queries complete.
-- "The heavy engineering job consumed its own credits. Executive was unaffected."
-- =============================================================================

USE WAREHOUSE WH_XS;

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
-- Expected:
--   CALOPTIMA_ENG_WH    → highest credits (Large WH, heavy query)
--   CALOPTIMA_ANALYST_WH/ML_WH → medium (Medium WH)
--   CALOPTIMA_EXEC_WH/BA_WH    → lowest (Small WH, light queries)
-- Talking point: 5 teams worked simultaneously on the same data.
-- No locks. No queuing. No one waiting for anyone else.


-- =============================================================================
-- CLEANUP
-- =============================================================================

DROP WAREHOUSE IF EXISTS CALOPTIMA_EXEC_WH;
DROP WAREHOUSE IF EXISTS CALOPTIMA_ENG_WH;
DROP WAREHOUSE IF EXISTS CALOPTIMA_ANALYST_WH;
DROP WAREHOUSE IF EXISTS CALOPTIMA_BA_WH;
DROP WAREHOUSE IF EXISTS CALOPTIMA_ML_WH;
ALTER SESSION UNSET USE_CACHED_RESULT;

SELECT 'Workload isolation demo complete.' AS status;
