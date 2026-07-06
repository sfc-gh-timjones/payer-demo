-- =============================================================================
-- TAB 3: ANALYST — Exploratory Trend Analysis
-- Analytics Innovator ad-hoc queries on a Medium warehouse.
-- =============================================================================

USE ROLE CALOPTIMA_ANALYST_ROLE;
USE SECONDARY ROLES NONE;
USE WAREHOUSE CALOPTIMA_ANALYST_WH;
USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF100;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT';

-- Query 1: Year-over-year monthly revenue comparison
SELECT
    MONTH(L_SHIPDATE)                                      AS month_num,
    YEAR(L_SHIPDATE)                                       AS ship_year,
    COUNT(*)                                               AS claim_count,
    SUM(L_EXTENDEDPRICE)                                   AS total_revenue,
    AVG(L_DISCOUNT)                                        AS avg_discount
FROM LINEITEM
GROUP BY 1, 2
ORDER BY month_num, ship_year;

-- Query 2: Seasonality — revenue by month across all years
SELECT
    MONTH(L_SHIPDATE)                                      AS month_num,
    ROUND(AVG(monthly_revenue), 0)                         AS avg_monthly_revenue,
    MIN(monthly_revenue)                                   AS min_revenue,
    MAX(monthly_revenue)                                   AS max_revenue
FROM (
    SELECT
        YEAR(L_SHIPDATE)  AS yr,
        MONTH(L_SHIPDATE) AS month_num,
        SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT)) AS monthly_revenue
    FROM LINEITEM
    GROUP BY 1, 2
)
GROUP BY month_num
ORDER BY month_num;

-- Query 3: Discount tier distribution — how are discounts being applied?
SELECT
    CASE
        WHEN L_DISCOUNT = 0       THEN '0% (no discount)'
        WHEN L_DISCOUNT <= 0.03   THEN '1-3%'
        WHEN L_DISCOUNT <= 0.06   THEN '4-6%'
        WHEN L_DISCOUNT <= 0.09   THEN '7-9%'
        ELSE '10%+'
    END                                                    AS discount_tier,
    COUNT(*)                                               AS claim_count,
    SUM(L_EXTENDEDPRICE)                                   AS total_billed,
    SUM(L_EXTENDEDPRICE * L_DISCOUNT)                      AS discount_amount
FROM LINEITEM
GROUP BY 1
ORDER BY MIN(L_DISCOUNT);

-- Query 4: Ship mode return rate analysis
SELECT
    L_SHIPMODE,
    COUNT(*)                                               AS total_lines,
    SUM(CASE WHEN L_RETURNFLAG = 'R' THEN 1 ELSE 0 END)   AS returned,
    ROUND(SUM(CASE WHEN L_RETURNFLAG = 'R' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS return_rate_pct,
    AVG(L_EXTENDEDPRICE)                                   AS avg_claim_value
FROM LINEITEM
GROUP BY L_SHIPMODE
ORDER BY return_rate_pct DESC;

-- Query 5: Claim size distribution — percentile buckets
SELECT
    CASE
        WHEN L_EXTENDEDPRICE < 10000    THEN 'Under $10K'
        WHEN L_EXTENDEDPRICE < 25000    THEN '$10K-$25K'
        WHEN L_EXTENDEDPRICE < 50000    THEN '$25K-$50K'
        WHEN L_EXTENDEDPRICE < 75000    THEN '$50K-$75K'
        ELSE 'Over $75K'
    END                                                    AS value_bucket,
    COUNT(*)                                               AS claim_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)    AS pct_of_total,
    SUM(L_EXTENDEDPRICE)                                   AS total_value
FROM LINEITEM
GROUP BY 1
ORDER BY MIN(L_EXTENDEDPRICE);
