-- =============================================================================
-- FILE: 02_workload_isolation.sql  (COORDINATOR — run this first)
-- PURPOSE: CalOptima RFP 26-038 | Performance — Workload Isolation
--          Setup, proof, and cleanup for the 5-worksheet demo.
--
-- HOW TO RUN:
--   1. Run PART 1 here to create all 5 warehouses
--   2. Open the 5 tab worksheets and run them simultaneously:
--        02_tab1_exec.sql    → Tab 1
--        02_tab2_eng.sql     → Tab 2  (start this one first — it's the heavy job)
--        02_tab3_analyst.sql → Tab 3
--        02_tab4_ba.sql      → Tab 4
--        02_tab5_ml.sql      → Tab 5
--   3. Come back here and run PART 2 (proof) after queries complete
--   4. Run PART 3 (cleanup) to drop warehouses after the demo
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;


-- =============================================================================
-- PART 1: CREATE 5 WORKLOAD WAREHOUSES
-- "Every team at CalOptima gets their own dedicated compute."
-- =============================================================================

CREATE OR REPLACE WAREHOUSE CALOPTIMA_EXEC_WH
    WAREHOUSE_SIZE = XSMALL   AUTO_SUSPEND = 30  AUTO_RESUME = TRUE
    COMMENT = 'Executive dashboards and board-level population health reports';

CREATE OR REPLACE WAREHOUSE CALOPTIMA_ENG_WH
    WAREHOUSE_SIZE = LARGE   AUTO_SUSPEND = 30  AUTO_RESUME = TRUE
    COMMENT = 'Data engineering — ETL, CDC, bulk claims transforms';

CREATE OR REPLACE WAREHOUSE CALOPTIMA_ANALYST_WH
    WAREHOUSE_SIZE = MEDIUM  AUTO_SUSPEND = 30  AUTO_RESUME = TRUE
    COMMENT = 'Analytics Innovators — ad-hoc and exploratory analysis';

CREATE OR REPLACE WAREHOUSE CALOPTIMA_BA_WH
    WAREHOUSE_SIZE = SMALL   AUTO_SUSPEND = 30  AUTO_RESUME = TRUE
    COMMENT = 'Business Analysts — standard reporting and dashboards';

CREATE OR REPLACE WAREHOUSE CALOPTIMA_ML_WH
    WAREHOUSE_SIZE = MEDIUM  AUTO_SUSPEND = 30  AUTO_RESUME = TRUE
    COMMENT = 'Data Science — ML feature engineering and model scoring';

SHOW WAREHOUSES LIKE 'CALOPTIMA%';

-- =============================================================================
-- PART 2: ISOLATION PROOF (run after all 5 tabs have finished)
-- Note: WAREHOUSE_METERING_HISTORY has ~2-min ingestion lag.
-- "The heavy ENG job consumed its own budget. EXEC_WH was unaffected."
-- =============================================================================

SELECT
    WAREHOUSE_NAME,
    SUM(CREDITS_USED_COMPUTE)  AS compute_credits,
    SUM(CREDITS_USED)          AS total_credits,
    MIN(START_TIME)            AS first_activity,
    MAX(END_TIME)              AS last_activity
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE WAREHOUSE_NAME ILIKE 'CALOPTIMA%'
  AND START_TIME > DATEADD('hour', -1, CURRENT_TIMESTAMP())
GROUP BY WAREHOUSE_NAME
ORDER BY compute_credits DESC;
-- Expected:
--   CALOPTIMA_ENG_WH     → highest credits (Large WH, heaviest query)
--   CALOPTIMA_ANALYST_WH / ML_WH → medium
--   CALOPTIMA_EXEC_WH / BA_WH    → lowest (Small WH, light queries)
-- Talking point: 5 teams ran simultaneously on the same data.
-- No locking. No contention. No one waited for anyone else.


-- =============================================================================
-- PART 3: CLEANUP
-- =============================================================================

DROP WAREHOUSE IF EXISTS CALOPTIMA_EXEC_WH;
DROP WAREHOUSE IF EXISTS CALOPTIMA_ENG_WH;
DROP WAREHOUSE IF EXISTS CALOPTIMA_ANALYST_WH;
DROP WAREHOUSE IF EXISTS CALOPTIMA_BA_WH;
DROP WAREHOUSE IF EXISTS CALOPTIMA_ML_WH;

SELECT 'Workload isolation demo complete.' AS status;
