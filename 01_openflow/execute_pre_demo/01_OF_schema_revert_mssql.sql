-- =============================================================================
-- FILE: 06.3_schema_revert_mssql.sql
-- PURPOSE: Reset the schema drift demo on Azure SQL Server.
--          Deletes the 5 demo rows (PRTP_ID >= 9001) and reverts schema changes.
--
-- SAFE DELETE STRATEGY:
--   Demo rows were inserted with PRTP_ID 9001-9005.
--   The initial load seeds exactly 15 rows (IDs 1-15), so IDs 9001+ are
--   exclusively demo rows. DELETE WHERE PRTP_ID >= 9001 never touches seeded data.
--
--   CMC_PRTP_PROV_TYPE has ZERO FK dependencies — no FK concerns whatsoever.
--
-- RUN THIS IN: Azure SQL Server (SSMS or Azure Data Studio)
-- DATABASE:    openflow

-- WORKFLOW:
-- SNOWFLAKE FIRST
-- 1. REMOVE FROM OPENFLOW REPLICATION
-- 2. RUN BELOW SCRIPT

--SQL SERVER
-- Run revert script in mssql. 
-- =============================================================================

USE openflow;
GO

-- =============================================================================
-- STEP 1: Confirm current state before reverting
-- =============================================================================

SELECT COUNT(*) AS total_rows FROM raw.CMC_PRTP_PROV_TYPE;  -- expect 20
SELECT * FROM raw.CMC_PRTP_PROV_TYPE WHERE PRTP_ID >= 9001 ORDER BY PRTP_ID;
GO

-- =============================================================================
-- STEP 2: Revert DML changes on seeded rows
-- =============================================================================

-- Restore PRTP_ID 7 description
UPDATE raw.CMC_PRTP_PROV_TYPE
SET    PRTP_DESC = 'Skilled Nursing Facility'
WHERE  PRTP_ID = 7;

SELECT @@ROWCOUNT AS rows_updated;  -- expect 1
GO

-- Re-insert PRTP_ID 2 (DO - Doctor of Osteopathy) that was deleted in the demo
INSERT INTO raw.CMC_PRTP_PROV_TYPE
    (PRTP_ID, PRTP_CODE, PRTP_DESC, PRTP_CATEGORY, PRTP_ACTIVE_FLAG, PRTP_SORT_ORDER)
VALUES
    (2, 'DO', 'Doctor of Osteopathy', 'Physician', 'Y', 2);

SELECT @@ROWCOUNT AS rows_inserted;  -- expect 1
GO

-- =============================================================================
-- STEP 3: Delete the 5 new demo rows (PRTP_IDs 9001–9005)
-- =============================================================================

DELETE FROM raw.CMC_PRTP_PROV_TYPE
WHERE PRTP_ID >= 9001;

SELECT @@ROWCOUNT AS rows_deleted;  -- expect 5
GO

-- =============================================================================
-- STEP 4: Revert schema changes
--   a) Drop PRTP_EFFECTIVE_DT column
--   b) Narrow PRTP_DESC back to VARCHAR(100)
-- =============================================================================

ALTER TABLE raw.CMC_PRTP_PROV_TYPE
    DROP COLUMN PRTP_EFFECTIVE_DT;
GO

ALTER TABLE raw.CMC_PRTP_PROV_TYPE
    ALTER COLUMN PRTP_DESC VARCHAR(100);
GO

-- =============================================================================
-- STEP 5: Confirm restored state
-- =============================================================================

SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'raw' AND TABLE_NAME = 'CMC_PRTP_PROV_TYPE'
ORDER BY ORDINAL_POSITION;

SELECT COUNT(*) AS total_rows FROM raw.CMC_PRTP_PROV_TYPE;  -- expect 15
SELECT * FROM raw.CMC_PRTP_PROV_TYPE WHERE PRTP_ID IN (2, 7) ORDER BY PRTP_ID;  -- confirm restored
GO
