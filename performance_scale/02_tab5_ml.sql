-- =============================================================================
-- TAB 5: ML — Data Science Feature Engineering
-- Complex join + percentile calculation on the ML team's Medium warehouse.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;
USE WAREHOUSE CALOPTIMA_ML_WH;
USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF100;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT';

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
;
