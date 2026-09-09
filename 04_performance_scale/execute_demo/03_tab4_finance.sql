-- =============================================================================
-- TAB 4: FINANCE — Financial Reporting and Reconciliation
-- Finance team standard reports on a Small warehouse.
-- =============================================================================

USE ROLE PAYER_FINANCE_ROLE;
USE SECONDARY ROLES NONE;
USE WAREHOUSE PAYER_FINANCE_WH;
USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF100;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT';

-- Query 1: Gross vs net revenue reconciliation
SELECT
    L_LINESTATUS,
    L_RETURNFLAG,
    COUNT(*)                                               AS line_count,
    SUM(L_EXTENDEDPRICE)                                   AS gross_billed,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT))                AS net_after_discount,
    SUM(L_EXTENDEDPRICE * L_DISCOUNT)                      AS total_discount,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT) * L_TAX)        AS tax_amount
FROM LINEITEM
GROUP BY L_LINESTATUS, L_RETURNFLAG
ORDER BY gross_billed DESC;

-- Query 2: Annual financial summary — revenue, discounts, and tax burden
SELECT
    YEAR(L_SHIPDATE)                                       AS fiscal_year,
    COUNT(*)                                               AS total_lines,
    SUM(L_EXTENDEDPRICE)                                   AS gross_revenue,
    SUM(L_EXTENDEDPRICE * L_DISCOUNT)                      AS total_discounts,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT))                AS net_revenue,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT) * L_TAX)        AS total_tax,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT) * (1 + L_TAX)) AS total_with_tax
FROM LINEITEM
GROUP BY 1
ORDER BY fiscal_year;

-- Query 3: High-value claims — top 1000 by extended price
SELECT
    L_ORDERKEY,
    L_LINENUMBER,
    L_PARTKEY,
    L_SUPPKEY,
    L_EXTENDEDPRICE                                        AS gross_billed,
    L_DISCOUNT,
    L_EXTENDEDPRICE * (1 - L_DISCOUNT)                     AS net_billed,
    L_RETURNFLAG,
    L_SHIPDATE
FROM LINEITEM
ORDER BY L_EXTENDEDPRICE DESC
LIMIT 1000;

-- Query 4: Quarterly revenue with period-over-period delta
SELECT
    YEAR(L_SHIPDATE)                                       AS yr,
    QUARTER(L_SHIPDATE)                                    AS qtr,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT))                AS net_revenue,
    LAG(SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT))) OVER
        (ORDER BY YEAR(L_SHIPDATE), QUARTER(L_SHIPDATE))   AS prior_qtr_revenue,
    ROUND(
        (SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT)) -
         LAG(SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT))) OVER
             (ORDER BY YEAR(L_SHIPDATE), QUARTER(L_SHIPDATE))) /
        NULLIF(LAG(SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT))) OVER
             (ORDER BY YEAR(L_SHIPDATE), QUARTER(L_SHIPDATE)), 0) * 100, 2
    )                                                      AS qoq_growth_pct
FROM LINEITEM
GROUP BY 1, 2
ORDER BY yr, qtr;

-- Query 5: Tax analysis — effective tax rate by return flag and line status
SELECT
    L_RETURNFLAG,
    L_LINESTATUS,
    AVG(L_TAX)                                             AS avg_tax_rate,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT) * L_TAX)        AS total_tax_collected,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT))                AS total_net_revenue,
    ROUND(
        SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT) * L_TAX) /
        SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT)) * 100, 4
    )                                                      AS effective_tax_pct
FROM LINEITEM
GROUP BY L_RETURNFLAG, L_LINESTATUS
ORDER BY effective_tax_pct DESC;
