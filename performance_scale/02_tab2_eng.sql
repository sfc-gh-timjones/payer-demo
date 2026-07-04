-- =============================================================================
-- TAB 2: ENG — Data Engineering / Claims Reconciliation
-- Start this one FIRST — it's the heavy overnight batch workload.
-- Large warehouse. Runs longest. Other tabs will finish while this is going.
-- The audience sees Tab 1 complete while this is still running = isolation proven.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;
USE WAREHOUSE CALOPTIMA_ENG_WH;
USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF100;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT';

-- Query 1: Full claims reconciliation — high cardinality group by (supplier × status × flag)
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

-- Query 2: Part-level claims volume and pricing metrics
SELECT
    L_PARTKEY,
    COUNT(*)                                               AS line_count,
    SUM(L_QUANTITY)                                        AS total_quantity,
    SUM(L_EXTENDEDPRICE)                                   AS total_extended_price,
    AVG(L_DISCOUNT)                                        AS avg_discount,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT) * (1 + L_TAX)) AS total_charge
FROM LINEITEM
GROUP BY L_PARTKEY
ORDER BY total_charge DESC
LIMIT 500;

-- Query 3: Daily volume reconciliation — row counts and revenue by ship date
SELECT
    L_SHIPDATE,
    COUNT(*)                                               AS claim_lines,
    COUNT(DISTINCT L_ORDERKEY)                             AS distinct_orders,
    SUM(L_EXTENDEDPRICE)                                   AS gross_revenue,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT))                AS net_revenue,
    SUM(L_TAX * L_EXTENDEDPRICE)                           AS estimated_tax
FROM LINEITEM
GROUP BY L_SHIPDATE
ORDER BY L_SHIPDATE;

-- Query 4: Ship mode performance — volume and value by delivery method
SELECT
    L_SHIPMODE,
    L_RETURNFLAG,
    COUNT(*)                                               AS claim_count,
    SUM(L_EXTENDEDPRICE)                                   AS total_billed,
    AVG(DATEDIFF('day', L_SHIPDATE, L_RECEIPTDATE))        AS avg_delivery_days,
    SUM(CASE WHEN L_RETURNFLAG = 'R' THEN 1 ELSE 0 END)   AS returned_count
FROM LINEITEM
GROUP BY L_SHIPMODE, L_RETURNFLAG
ORDER BY L_SHIPMODE, total_billed DESC;

-- Query 5: Commit date vs ship date variance — SLA compliance check
SELECT
    DATEDIFF('day', L_COMMITDATE, L_RECEIPTDATE)           AS days_vs_commit,
    COUNT(*)                                               AS claim_count,
    SUM(L_EXTENDEDPRICE)                                   AS revenue_impacted,
    L_RETURNFLAG
FROM LINEITEM
GROUP BY 1, 4
ORDER BY days_vs_commit, L_RETURNFLAG;
