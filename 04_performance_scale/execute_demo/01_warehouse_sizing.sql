-- =============================================================================
-- FILE: 01_warehouse_sizing.sql
-- PURPOSE: Scale Up
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;

-- =============================================================================
-- PART 1: SETUP
-- =============================================================================

CREATE OR REPLACE WAREHOUSE WH_ENTERPRISE_ANALYTICS
    WAREHOUSE_SIZE = MEDIUM
    AUTO_SUSPEND   = 30
    AUTO_RESUME    = TRUE
    COMMENT        = 'Payer performance demo — resize during demo to show elastic scaling';

USE WAREHOUSE WH_ENTERPRISE_ANALYTICS;
-- USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF1; --scale factor of 1
-- USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF10; --scale factor of 10
-- USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF100; --scale factor of 100 
USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000; --scale factor of 1000


-- =============================================================================
-- PART 2: DISABLE RESULT CACHE
-- Run this once. Every subsequent query hits real compute, not a cached result.
-- =============================================================================

ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT';
-- Confirm: value = false


-- =============================================================================
-- PART 3: SET WAREHOUSE SIZE
-- Uncomment ONE line, run it, then run the benchmark query below.
-- Swap sizes to compare performance.
-- =============================================================================

-- ALTER WAREHOUSE WH_ENTERPRISE_ANALYTICS SET WAREHOUSE_SIZE = XSMALL;
-- ALTER WAREHOUSE WH_ENTERPRISE_ANALYTICS SET WAREHOUSE_SIZE = SMALL;
-- ALTER WAREHOUSE WH_ENTERPRISE_ANALYTICS SET WAREHOUSE_SIZE = MEDIUM;
-- ALTER WAREHOUSE WH_ENTERPRISE_ANALYTICS SET WAREHOUSE_SIZE = LARGE;
-- ALTER WAREHOUSE WH_ENTERPRISE_ANALYTICS SET WAREHOUSE_SIZE = XLARGE;

SELECT 'Record Count: ' || TO_VARCHAR(COUNT(*), 'FM999,999,999,999')
FROM LINEITEM;

-- =============================================================================
-- PART 4: BENCHMARK QUERY — RUN AFTER EACH SIZE CHANGE
-- TPC-H Query 1: claims pricing summary by return flag and line status.
-- Equivalent to: monthly claims aggregation across 600M claim lines.
-- Watch the elapsed time in the Snowsight query result header.
-- =============================================================================

SELECT
    L_RETURNFLAG                                              AS return_flag,
    L_LINESTATUS                                              AS line_status,
    SUM(L_QUANTITY)                                           AS sum_qty,
    SUM(L_EXTENDEDPRICE)                                      AS sum_base_price,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT))                   AS sum_disc_price,
    SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT) * (1 + L_TAX))     AS sum_charge,
    AVG(L_QUANTITY)                                           AS avg_qty,
    AVG(L_EXTENDEDPRICE)                                      AS avg_price,
    AVG(L_DISCOUNT)                                           AS avg_disc,
    COUNT(*)                                                  AS count_order
FROM LINEITEM
WHERE L_SHIPDATE <= DATEADD(DAY, -90, TO_DATE('1998-12-01'))
GROUP BY  L_RETURNFLAG, L_LINESTATUS
ORDER BY  L_RETURNFLAG, L_LINESTATUS;


-- =============================================================================
-- CLEANUP
-- =============================================================================

DROP WAREHOUSE IF EXISTS WH_ENTERPRISE_ANALYTICS;
ALTER SESSION UNSET USE_CACHED_RESULT;
