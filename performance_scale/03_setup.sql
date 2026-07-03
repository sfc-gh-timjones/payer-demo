-- =============================================================================
-- FILE: 03_setup.sql
-- PURPOSE: Materialize TPCH_SF100 LINEITEM into a local database so that
--          stored procedures and tasks in 03_multi_cluster_concurrency.sql
--          can reference it (you cannot create procedures/tasks that run
--          against SNOWFLAKE_SAMPLE_DATA — it is a shared/imported database).
--
-- RUN ONCE before running 03_multi_cluster_concurrency.sql.
-- NOTE: The CTAS copies 600M rows. Expect 3-8 minutes on a Medium warehouse.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;
USE WAREHOUSE WH_XS;

-- Create local database and schema matching the sample data layout
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_SAMPLE_DATA2;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100;

-- Use a Medium warehouse for the bulk copy — XSmall is too slow for 600M rows
CREATE OR REPLACE WAREHOUSE CALOPTIMA_SETUP_WH
    WAREHOUSE_SIZE = MEDIUM
    AUTO_SUSPEND   = 30
    AUTO_RESUME    = TRUE;

USE WAREHOUSE CALOPTIMA_SETUP_WH;

-- Materialize LINEITEM (600M rows — this is the primary benchmark table)
CREATE OR REPLACE TABLE SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.LINEITEM
    AS SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM;

-- Confirm row count
SELECT COUNT(*) AS lineitem_rows FROM SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.LINEITEM;
-- Expected: ~600,037,902 rows

-- Drop the setup warehouse — no longer needed
DROP WAREHOUSE IF EXISTS CALOPTIMA_SETUP_WH;

SELECT 'Setup complete — SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.LINEITEM is ready.' AS status;
