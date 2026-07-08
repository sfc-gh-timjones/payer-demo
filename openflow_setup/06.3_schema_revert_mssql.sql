-- =============================================================================
-- FILE: 06.3_schema_revert_mssql.sql
-- PURPOSE: Reset the schema drift demo on Azure SQL Server.
--          Deletes the 5 demo rows (PRFA_ID >= 9001) and drops PRFA_COUNTY.
--
-- SAFE DELETE STRATEGY:
--   Demo rows were inserted with PRFA_ID 9001-9005.
--   The initial load seeds ~300 rows, so IDs 9001+ are exclusively demo rows.
--   DELETE WHERE PRFA_ID >= 9001 will never touch seeded data.
--
--   CMC_PRFA_FACILITY has NO child tables referencing it — no FK issue.
--
-- RUN THIS IN: Azure SQL Server (SSMS or Azure Data Studio)
-- DATABASE:    openflow
-- =============================================================================

USE openflow;
GO

-- =============================================================================
-- STEP 1: Confirm current state before reverting
-- =============================================================================

SELECT COUNT(*) AS total_rows FROM raw.CMC_PRFA_FACILITY;
SELECT * FROM raw.CMC_PRFA_FACILITY WHERE PRFA_ID >= 9001 ORDER BY PRFA_ID;
GO

-- =============================================================================
-- STEP 2: Delete the 5 demo rows
-- =============================================================================

DELETE FROM raw.CMC_PRFA_FACILITY
WHERE PRFA_ID >= 9001;

SELECT @@ROWCOUNT AS rows_deleted;  -- expect 5
GO

-- =============================================================================
-- STEP 3: Revert schema changes
--   a) Drop PRFA_COUNTY column
--   b) Narrow PRFA_FAC_TYPE back to VARCHAR(10)
-- =============================================================================

ALTER TABLE raw.CMC_PRFA_FACILITY
    DROP COLUMN PRFA_COUNTY;
GO

ALTER TABLE raw.CMC_PRFA_FACILITY
    ALTER COLUMN PRFA_FAC_TYPE VARCHAR(10);
GO

-- =============================================================================
-- STEP 4: Confirm restored state
-- =============================================================================

SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'raw' AND TABLE_NAME = 'CMC_PRFA_FACILITY'
ORDER BY ORDINAL_POSITION;

SELECT COUNT(*) AS total_rows FROM raw.CMC_PRFA_FACILITY;  -- expect ~300
GO
