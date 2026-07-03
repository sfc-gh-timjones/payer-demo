-- =============================================================================
-- TAB 3: ANALYST — Exploratory Trend Analysis
-- Ad-hoc population trend analysis on the Analytics Innovator's Medium warehouse.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;
USE WAREHOUSE CALOPTIMA_ANALYST_WH;
USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF100;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT';

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
