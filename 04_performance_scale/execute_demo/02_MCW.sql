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
-- PART 1: CREATE THE MULTI-CLUSTER WAREHOUSE
-- "One config change — Snowflake handles the rest automatically."
-- =============================================================================

CREATE OR REPLACE WAREHOUSE CALOPTIMA_CONCURRENCY_WH
    WAREHOUSE_SIZE    = MEDIUM
    GENERATION = '2'
    MIN_CLUSTER_COUNT = 1           -- idles at 1 cluster at rest (cost-efficient)
    MAX_CLUSTER_COUNT = 10           -- scales out to 10 under heavy concurrent load
    SCALING_POLICY    = STANDARD    -- adds clusters when queries start queueing
    AUTO_SUSPEND      = 30
    AUTO_RESUME       = TRUE
    COMMENT           = 'Multi-cluster: auto-scales 1→10 during open enrollment surge';

USE WAREHOUSE WH_XS; 

SHOW WAREHOUSES LIKE 'CALOPTIMA_CONCURRENCY_WH';
-- Key columns: min_cluster_count=1, max_cluster_count=4, scaling_policy=STANDARD
-- No hardware provisioning. No capacity planning. No on-call engineer.


-- =============================================================================
-- PART 2: FIRE CONCURRENT LOAD
-- =============================================================================

-- ── Fire concurrent load ──────────────────────────────────────────────────────
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SHOW PARAMETERS LIKE 'USE_CACHED_RESULT';

CALL SNOWFLAKE_SAMPLE_DATA2.TPCH_SF100.spawn_concurrent_users(100);

SHOW WAREHOUSES LIKE 'CALOPTIMA_CONCURRENCY_WH';