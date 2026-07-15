-- =============================================================================
-- FILE: 03_multi_cluster_concurrency.sql
--
-- DATA: SNOWFLAKE_SAMPLE_DATA.TPCH_SF100 (600M rows)
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;
USE DATABASE SNOWFLAKE_SAMPLE_DATA2;
USE SCHEMA TPCH_SF100;

-- =============================================================================
-- PART 2: FIRE CONCURRENT LOAD
-- =============================================================================

-- ── Fire concurrent load ──────────────────────────────────────────────────────
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT';

CALL SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.spawn_concurrent_users(100);

