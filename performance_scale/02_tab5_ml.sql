-- =============================================================================
-- TAB 5: ML — Data Science Feature Engineering
-- Complex joins and statistical aggregations on a Medium warehouse.
-- =============================================================================

USE ROLE CALOPTIMA_ML_ROLE;
USE SECONDARY ROLES NONE;
USE WAREHOUSE CALOPTIMA_ML_WH;
USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF100;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT';

-- Query 1: Customer-level features (join ORDERS + LINEITEM)
SELECT
    O.O_CUSTKEY,
    COUNT(L.L_LINENUMBER)                                  AS claim_line_count,
    COUNT(DISTINCT O.O_ORDERKEY)                           AS order_count,
    SUM(L.L_EXTENDEDPRICE)                                 AS total_billed,
    AVG(L.L_DISCOUNT)                                      AS avg_discount,
    PERCENTILE_CONT(0.5) WITHIN GROUP
        (ORDER BY L.L_EXTENDEDPRICE)                       AS median_claim_amt,
    MAX(L.L_EXTENDEDPRICE)                                 AS max_claim_amt
FROM ORDERS   O
JOIN LINEITEM  L ON O.O_ORDERKEY = L.L_ORDERKEY
GROUP BY O.O_CUSTKEY
ORDER BY total_billed DESC
LIMIT 500;

-- Query 2: Supplier features — volume, pricing, and reliability metrics
SELECT
    S.S_SUPPKEY,
    S.S_NAME,
    COUNT(L.L_LINENUMBER)                                  AS line_count,
    SUM(L.L_EXTENDEDPRICE)                                 AS total_supplied_value,
    AVG(L.L_DISCOUNT)                                      AS avg_discount_granted,
    STDDEV(L.L_EXTENDEDPRICE)                              AS price_stddev,
    SUM(CASE WHEN L.L_RETURNFLAG = 'R' THEN 1 ELSE 0 END) AS returns,
    ROUND(AVG(DATEDIFF('day', L.L_COMMITDATE, L.L_RECEIPTDATE)), 1) AS avg_delivery_days
FROM SUPPLIER S
JOIN LINEITEM  L ON S.S_SUPPKEY = L.L_SUPPKEY
GROUP BY S.S_SUPPKEY, S.S_NAME
ORDER BY total_supplied_value DESC
LIMIT 200;

-- Query 3: Temporal purchase patterns — monthly averages per customer
SELECT
    O.O_CUSTKEY,
    YEAR(L.L_SHIPDATE)                                     AS ship_year,
    MONTH(L.L_SHIPDATE)                                    AS ship_month,
    COUNT(L.L_LINENUMBER)                                  AS monthly_claim_count,
    SUM(L.L_EXTENDEDPRICE)                                 AS monthly_spend,
    AVG(L.L_DISCOUNT)                                      AS monthly_avg_discount
FROM ORDERS   O
JOIN LINEITEM  L ON O.O_ORDERKEY = L.L_ORDERKEY
GROUP BY O.O_CUSTKEY, YEAR(L.L_SHIPDATE), MONTH(L.L_SHIPDATE)
ORDER BY O.O_CUSTKEY, ship_year, ship_month
LIMIT 1000;

-- Query 4: Derived ratio features — quantity vs price correlation proxies
SELECT
    L_PARTKEY,
    COUNT(*)                                               AS observation_count,
    AVG(L_QUANTITY)                                        AS avg_quantity,
    AVG(L_EXTENDEDPRICE / NULLIF(L_QUANTITY, 0))           AS avg_unit_price,
    STDDEV(L_EXTENDEDPRICE / NULLIF(L_QUANTITY, 0))        AS unit_price_stddev,
    CORR(L_QUANTITY, L_EXTENDEDPRICE)                      AS qty_price_correlation,
    CORR(L_DISCOUNT, L_EXTENDEDPRICE)                      AS discount_price_correlation
FROM LINEITEM
GROUP BY L_PARTKEY
HAVING COUNT(*) > 10
ORDER BY qty_price_correlation DESC
LIMIT 500;

-- Query 5: Percentile buckets for behavioral segmentation
SELECT
    O.O_CUSTKEY,
    SUM(L.L_EXTENDEDPRICE * (1 - L.L_DISCOUNT))           AS total_net_spend,
    NTILE(10) OVER (ORDER BY SUM(L.L_EXTENDEDPRICE * (1 - L.L_DISCOUNT)) DESC) AS spend_decile,
    COUNT(DISTINCT O.O_ORDERKEY)                           AS order_frequency,
    NTILE(5) OVER (ORDER BY COUNT(DISTINCT O.O_ORDERKEY) DESC) AS frequency_quintile,
    AVG(L.L_DISCOUNT)                                      AS avg_discount_received
FROM ORDERS   O
JOIN LINEITEM  L ON O.O_ORDERKEY = L.L_ORDERKEY
GROUP BY O.O_CUSTKEY
ORDER BY total_net_spend DESC
LIMIT 500;
