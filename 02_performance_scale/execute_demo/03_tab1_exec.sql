-- =============================================================================
-- TAB 1: EXEC — Executive Dashboard Queries
-- Run this while Tab 2 (ENG heavy job) is still running.
-- Small warehouse. All 5 queries finish well before ENG is done.
-- Key moment: this tab completes BEFORE Tab 2 — that is workload isolation.
-- =============================================================================

USE ROLE CALOPTIMA_EXEC_ROLE;
USE SECONDARY ROLES NONE;
USE WAREHOUSE CALOPTIMA_EXEC_WH;
USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF100;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT';

-- Query 1: Revenue summary by return flag
SELECT
    L_RETURNFLAG                     AS return_flag,
    L_LINESTATUS                     AS line_status,
    COUNT(*)                         AS claim_count,
    SUM(L_EXTENDEDPRICE)             AS total_billed,
    ROUND(AVG(L_DISCOUNT) * 100, 2)  AS avg_discount_pct,
    SUM(L_EXTENDEDPRICE * L_DISCOUNT) AS total_discount_given
FROM LINEITEM
GROUP BY L_RETURNFLAG, L_LINESTATUS
ORDER BY total_billed DESC;

-- Query 2: Monthly revenue trend
SELECT
    YEAR(L_SHIPDATE)                 AS ship_year,
    MONTH(L_SHIPDATE)                AS ship_month,
    COUNT(*)                         AS claim_count,
    SUM(L_EXTENDEDPRICE)             AS gross_revenue,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT)) AS net_revenue
FROM LINEITEM
GROUP BY 1, 2
ORDER BY ship_year, ship_month;

-- Query 3: Top 20 revenue months
SELECT
    YEAR(L_SHIPDATE)                         AS ship_year,
    MONTH(L_SHIPDATE)                        AS ship_month,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT))  AS net_revenue,
    COUNT(*)                                 AS claim_count
FROM LINEITEM
GROUP BY 1, 2
ORDER BY net_revenue DESC
LIMIT 20;

-- Query 4: Discount impact — revenue lost to discounts
SELECT
    L_RETURNFLAG,
    SUM(L_EXTENDEDPRICE)                          AS gross_billed,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT))       AS net_after_discount,
    SUM(L_EXTENDEDPRICE * L_DISCOUNT)             AS discount_value,
    ROUND(SUM(L_EXTENDEDPRICE * L_DISCOUNT) /
          SUM(L_EXTENDEDPRICE) * 100, 2)          AS discount_pct_of_gross
FROM LINEITEM
GROUP BY L_RETURNFLAG
ORDER BY discount_value DESC;

-- Query 5: Annual order volume and average claim size
SELECT
    YEAR(L_SHIPDATE)                         AS claim_year,
    COUNT(*)                                 AS total_claims,
    SUM(L_EXTENDEDPRICE)                     AS total_revenue,
    ROUND(AVG(L_EXTENDEDPRICE), 2)           AS avg_claim_size,
    ROUND(AVG(L_QUANTITY), 2)               AS avg_quantity
FROM LINEITEM
GROUP BY 1
ORDER BY claim_year;
