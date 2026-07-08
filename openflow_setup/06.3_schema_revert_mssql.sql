-- =============================================================================
-- FILE: 06.3_schema_revert_mssql.sql
-- PURPOSE: Reset the schema drift demo on Azure SQL Server.
--          Removes the 5 demo rows and drops the NWNW_REGION column from
--          CMC_NWNW_NETWORK, restoring the table to its pre-demo state.
--
-- APPROACH: DELETE + DROP COLUMN (no need to rebuild the table)
--   - SQL Server Change Tracking handles column drops cleanly — CT continues
--     tracking remaining columns without interruption. No need to disable and
--     re-enable change tracking.
--   - The DROP COLUMN will emit a DDL FlowFile in Openflow (visible in the
--     Observability dashboard) — that is expected and normal.
--   - After this script runs, follow up with 06.4_schema_revert_snow.sql in
--     Snowflake to drop and re-onboard the Bronze table.
--
-- RUN THIS IN: Azure SQL Server (SSMS, Azure Data Studio, or sqlcmd)
-- DATABASE:    openflow
-- =============================================================================

USE openflow;
GO

-- =============================================================================
-- STEP 1: Confirm current state before reverting
-- =============================================================================

SELECT NWNW_ID, NWNW_NAME, NWNW_REGION
FROM raw.CMC_NWNW_NETWORK
ORDER BY NWNW_ID;

SELECT COUNT(*) AS total_rows FROM raw.CMC_NWNW_NETWORK;
GO

-- =============================================================================
-- STEP 2: Delete the 5 demo rows (IDs 101–105)
--
-- CMC_NWPR_RELATION has a FK on NWNW_ID, so the incremental load proc may have
-- inserted NWPR child rows pointing at the new network IDs. Delete children first.
-- =============================================================================

-- Delete any NWPR child rows that reference the demo network IDs
DELETE FROM raw.CMC_NWPR_RELATION
WHERE NWNW_ID >= 101;

SELECT @@ROWCOUNT AS nwpr_rows_deleted;
GO

-- Now safe to delete the parent network rows
DELETE FROM raw.CMC_NWNW_NETWORK
WHERE NWNW_ID >= 101;

SELECT @@ROWCOUNT AS nwnw_rows_deleted;  -- expect 5
GO

-- =============================================================================
-- STEP 3: Drop the NWNW_REGION column
--
-- SQL Server requires any default constraints to be dropped first.
-- NWNW_REGION was added as NULL with no DEFAULT, so a direct DROP COLUMN works.
-- =============================================================================

ALTER TABLE raw.CMC_NWNW_NETWORK
    DROP COLUMN NWNW_REGION;
GO

-- =============================================================================
-- STEP 4: Confirm restored state
-- =============================================================================

-- Column list — NWNW_REGION should be gone
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'raw'
  AND TABLE_NAME   = 'CMC_NWNW_NETWORK'
ORDER BY ORDINAL_POSITION;

-- Row count — should be back to original (~20)
SELECT COUNT(*) AS total_rows FROM raw.CMC_NWNW_NETWORK;

SELECT * FROM raw.CMC_NWNW_NETWORK ORDER BY NWNW_ID;
GO

-- =============================================================================
-- STEP 5: Verify change tracking is still active on the table
-- =============================================================================

SELECT
    t.name                          AS table_name,
    ct.is_track_columns_updated_on,
    ct.min_valid_version,
    CHANGE_TRACKING_CURRENT_VERSION() AS current_ct_version
FROM sys.change_tracking_tables ct
JOIN sys.tables t ON ct.object_id = t.object_id
JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE s.name = 'raw'
  AND t.name = 'CMC_NWNW_NETWORK';
GO
