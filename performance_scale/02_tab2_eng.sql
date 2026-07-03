-- =============================================================================
-- TAB 2: ENG — Heavy ETL / Claims Reconciliation Job
-- Start this one FIRST — it represents an overnight bulk processing job.
-- Large warehouse. Intentionally slow — let it run while other tabs fire.
-- The audience will see other tabs finish while this one is still going.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;
USE WAREHOUSE CALOPTIMA_ENG_WH;
USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF100;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT';

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
-- Heavy full-table aggregation. Takes longer than the other tabs.
-- This is the point: even with this running, EXEC_WH is completely unaffected.
