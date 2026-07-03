-- =============================================================================
-- FILE: 02_workload_isolation.sql
-- PURPOSE: CalOptima RFP 26-038 | Performance — Workload Isolation
--          5 independent virtual warehouses, one shared dataset.
--          A heavy overnight ETL job cannot slow down the CEO's morning report.
--
-- DATA: SNOWFLAKE_SAMPLE_DATA.TPCH_SF100 (600M rows)
--
-- HOW TO RUN FOR MAXIMUM IMPACT:
--   Run PART 1 (setup) in any single worksheet first.
--   Then open 5 Snowsight worksheet tabs — one per workload section below.
--   Start the heavy ENG query (Tab 2) FIRST. While it's still running,
--   immediately fire the EXEC query (Tab 1). Tab 1 finishes in seconds.
--   The audience sees isolation proven visually: Tab 2 is still spinning.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;
USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF100;


-- =============================================================================
-- PART 1: SETUP — RUN ONCE IN ANY WORKSHEET
-- Creates all 5 warehouses. Run this before opening the parallel tabs.
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

-- Confirm all 5 warehouses are ready
SHOW WAREHOUSES LIKE 'CALOPTIMA%';


-- =============================================================================
-- PART 2: PARALLEL ISOLATION DEMO
-- Open a separate Snowsight worksheet tab for each section below.
-- Start Tab 2 (ENG heavy job) first, then immediately run Tab 1 (EXEC).
-- Key moment: Tab 1 finishes in seconds while Tab 2 is still running.
-- That is workload isolation.
-- =============================================================================

-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ TAB 1 — EXEC: Executive dashboard query (run WHILE Tab 2 is running)   │
-- │ Small warehouse. Should finish in ~3-5 seconds.                         │
-- └─────────────────────────────────────────────────────────────────────────┘
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
-- Finishes fast on its own Small warehouse — unaffected by whatever else is running.


-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ TAB 2 — ENG: Heavy ETL/reconciliation job (start this one FIRST)        │
-- │ Large warehouse. Intentionally slow — represents overnight batch work.  │
-- └─────────────────────────────────────────────────────────────────────────┘
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


-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ TAB 3 — ANALYST: Exploratory trend analysis                             │
-- └─────────────────────────────────────────────────────────────────────────┘
USE WAREHOUSE CALOPTIMA_ANALYST_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT
    YEAR(L_SHIPDATE)     AS claim_year,
    MONTH(L_SHIPDATE)    AS claim_month,
    L_RETURNFLAG         AS claim_status,
    COUNT(*)             AS claim_count,
    SUM(L_EXTENDEDPRICE) AS total_revenue,
    AVG(L_DISCOUNT)      AS avg_discount
FROM LINEITEM
GROUP BY 1, 2, 3
ORDER BY claim_year, claim_month, claim_status;


-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ TAB 4 — BUSINESS ANALYST: Standard operational report                   │
-- └─────────────────────────────────────────────────────────────────────────┘
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


-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ TAB 5 — ML / DATA SCIENCE: Feature engineering with joins               │
-- └─────────────────────────────────────────────────────────────────────────┘
USE WAREHOUSE CALOPTIMA_ML_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT
    O.O_CUSTKEY,
    COUNT(L.L_LINENUMBER)                              AS claim_line_count,
    SUM(L.L_EXTENDEDPRICE)                             AS total_billed,
    AVG(L.L_DISCOUNT)                                  AS avg_discount,
    PERCENTILE_CONT(0.5) WITHIN GROUP
        (ORDER BY L.L_EXTENDEDPRICE)                   AS median_claim_amt
FROM ORDERS   O
JOIN LINEITEM  L ON O.O_ORDERKEY = L.L_ORDERKEY
GROUP BY O.O_CUSTKEY
ORDER BY total_billed DESC
LIMIT 500;


-- =============================================================================
-- PART 3: ISOLATION PROOF — PER-WAREHOUSE CREDIT USAGE
-- Run in any tab after all queries complete.
-- Note: WAREHOUSE_METERING_HISTORY has ~2-min ingestion lag.
-- "The heavy ENG job consumed its own budget. EXEC_WH was completely unaffected."
-- =============================================================================

USE WAREHOUSE WH_XS;
ALTER SESSION UNSET USE_CACHED_RESULT;

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
--   CALOPTIMA_ENG_WH     → highest credits (Large WH, heaviest query)
--   CALOPTIMA_ANALYST_WH / ML_WH → medium
--   CALOPTIMA_EXEC_WH / BA_WH    → lowest (Small WH, lightweight queries)
-- Talking point: 5 teams ran simultaneously on the same data.
-- No locking. No contention. No one waited for anyone else.


-- =============================================================================
-- CLEANUP — Run in any tab after the demo
-- =============================================================================

DROP WAREHOUSE IF EXISTS CALOPTIMA_EXEC_WH;
DROP WAREHOUSE IF EXISTS CALOPTIMA_ENG_WH;
DROP WAREHOUSE IF EXISTS CALOPTIMA_ANALYST_WH;
DROP WAREHOUSE IF EXISTS CALOPTIMA_BA_WH;
DROP WAREHOUSE IF EXISTS CALOPTIMA_ML_WH;

SELECT 'Workload isolation demo complete.' AS status;
