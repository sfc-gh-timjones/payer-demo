-- =============================================================================
-- FILE: 06_schema_change_mssql.sql
-- PURPOSE: Simulate a source schema change on CMC_NWNW_NETWORK in Azure SQL Server.
--          This is the demo script for Scenario 3 (Schema Drift) and Scenario 6
--          (Failure and Recovery) in the CalOptima RFP 26-038 demonstration.
--
-- TABLE CHOSEN: CMC_NWNW_NETWORK
--   - Pure static reference data (networks like HMO-OC, PPO-OC, DSNP)
--   - Never receives inserts/updates/deletes in the incremental load proc —
--     any CDC activity on this table is 100% attributable to this script
--   - Currently ~20 rows; Openflow tracks all changes via change tracking
--
-- WHAT THIS DEMONSTRATES:
--   1. ADD COLUMN — ALTER TABLE adds NWNW_REGION VARCHAR(30) to a live CDC'd table
--   2. OPENFLOW DETECTION — Openflow detects the schema change automatically via
--      change tracking; the Bronze table in Snowflake gains the column via
--      schema evolution (ENABLE_SCHEMA_EVOLUTION)
--   3. NEW RECORDS WITH NEW COLUMN — 5 inserts include the new column populated,
--      showing the before/after split in Silver
--
-- RUN THIS IN: Azure SQL Server (Management Studio, Azure Data Studio, or sqlcmd)
-- DATABASE:    openflow
-- =============================================================================

USE openflow;
GO

-- =============================================================================
-- STEP 1: Confirm current state before the change
-- =============================================================================

-- Current columns on the table
SELECT
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'raw'
  AND TABLE_NAME   = 'CMC_NWNW_NETWORK'
ORDER BY ORDINAL_POSITION;

-- Current row count and data
SELECT * FROM raw.CMC_NWNW_NETWORK ORDER BY NWNW_ID;
GO

-- =============================================================================
-- STEP 2: Add the new column (schema change event)
--
-- This ALTER TABLE will be captured by SQL Server Change Tracking and delivered
-- to Openflow on the next polling cycle (~15 minutes).
-- =============================================================================

ALTER TABLE raw.CMC_NWNW_NETWORK
    ADD NWNW_REGION VARCHAR(30) NULL;
GO

-- Confirm the column was added
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'raw'
  AND TABLE_NAME   = 'CMC_NWNW_NETWORK'
ORDER BY ORDINAL_POSITION;
GO

-- =============================================================================
-- STEP 3: Insert 5 new network records that include the new column
--
-- These records represent CalOptima expanding its network footprint into
-- new geographic service areas in Orange County.
-- =============================================================================

INSERT INTO raw.CMC_NWNW_NETWORK
    (NWNW_ID, NWNW_NAME,                        NWNW_ABBR,   NWNW_STS, NWNW_EFF_DT,  NWNW_TERM_DT, NWNW_TYPE, NWNW_REGION,   SYS_LAST_UPD_DTM)
VALUES
    (101, 'CalOptima North OC Network',          'HMO-NOC',   'AC',     '2026-01-01', NULL,         'HMO',     'North OC',    GETDATE()),
    (102, 'CalOptima South OC Network',          'HMO-SOC',   'AC',     '2026-01-01', NULL,         'HMO',     'South OC',    GETDATE()),
    (103, 'CalOptima Coastal Network',           'PPO-CST',   'AC',     '2026-04-01', NULL,         'PPO',     'Coastal OC',  GETDATE()),
    (104, 'CalOptima East OC DSNP Network',      'DSNP-EOC',  'AC',     '2026-04-01', NULL,         'DSNP',    'East OC',     GETDATE()),
    (105, 'CalOptima Central Access Network',    'EPO-CTR',   'AC',     '2026-07-01', NULL,         'EPO',     'Central OC',  GETDATE());
GO

-- =============================================================================
-- STEP 4: Confirm final state
-- =============================================================================

-- Total rows (should now be original ~20 + 5 = ~25)
SELECT COUNT(*) AS total_rows FROM raw.CMC_NWNW_NETWORK;

-- New records with the NWNW_REGION column populated
SELECT NWNW_ID, NWNW_NAME, NWNW_ABBR, NWNW_STS, NWNW_TYPE, NWNW_REGION, NWNW_EFF_DT
FROM raw.CMC_NWNW_NETWORK
WHERE NWNW_ID >= 101
ORDER BY NWNW_ID;

-- Before/after split — original rows have NULL for NWNW_REGION
SELECT
    CASE WHEN NWNW_REGION IS NULL THEN 'Pre-change (no region)' ELSE 'Post-change (' + NWNW_REGION + ')' END AS row_origin,
    COUNT(*) AS row_count
FROM raw.CMC_NWNW_NETWORK
GROUP BY CASE WHEN NWNW_REGION IS NULL THEN 'Pre-change (no region)' ELSE 'Post-change (' + NWNW_REGION + ')' END
ORDER BY 1;
GO

-- =============================================================================
-- CLEANUP / ROLLBACK (run if you want to reset the demo)
-- =============================================================================

-- To undo: remove the new records and drop the column
-- DELETE FROM raw.CMC_NWNW_NETWORK WHERE NWNW_ID >= 101;
-- ALTER TABLE raw.CMC_NWNW_NETWORK DROP COLUMN NWNW_REGION;
