-- =============================================================================
-- TAB 4: BA — Business Analyst Standard Operational Report
-- Standard reporting on the Business Analyst's Small warehouse.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;
USE WAREHOUSE CALOPTIMA_BA_WH;
USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF100;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT';

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
