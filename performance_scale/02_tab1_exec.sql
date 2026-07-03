-- =============================================================================
-- TAB 1: EXEC — Executive Dashboard Query
-- Run this while Tab 2 (ENG heavy job) is still running.
-- Small warehouse. Should finish in ~3-5 seconds.
-- Key moment: this completes BEFORE Tab 2 — that is workload isolation.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;
USE WAREHOUSE CALOPTIMA_EXEC_WH;
USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF100;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT';

SELECT
    L_RETURNFLAG                     AS claim_status,
    COUNT(*)                         AS claim_count,
    SUM(L_EXTENDEDPRICE)             AS total_billed,
    ROUND(AVG(L_DISCOUNT) * 100, 2)  AS avg_discount_pct
FROM LINEITEM
GROUP BY L_RETURNFLAG
ORDER BY total_billed DESC;
-- Finishes fast on its own Small warehouse.
-- The ENG Large warehouse running concurrently has zero impact here.
