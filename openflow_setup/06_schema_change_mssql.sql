-- =============================================================================
-- FILE: 06_schema_change_mssql.sql
-- PURPOSE: Simulate a source schema change on CMC_PRFA_FACILITY in Azure SQL Server.
--          This is the demo script for Scenario 3 (Schema Drift) in the CalOptima
--          RFP 26-038 demonstration.
--
-- TABLE CHOSEN: CMC_PRFA_FACILITY
--   - Pure static data (facility records per provider), ~300 rows after re-seed
--   - Never receives inserts/updates/deletes in the incremental load proc
--   - No child tables reference it — deletes are always clean
--   - Demo rows use PRFA_IDs 9001-9005 (well above the ~300 seeded rows)
--     so the revert is simply: DELETE WHERE PRFA_ID >= 9001
--
-- WHAT THIS DEMONSTRATES:
--   1. ADD COLUMN — ALTER TABLE adds PRFA_COUNTY VARCHAR(30) mid-stream
--   2. OPENFLOW DETECTION — Openflow detects the schema change via CT; the
--      Bronze table in Snowflake gains the column via schema evolution
--   3. NEW RECORDS WITH NEW COLUMN — 5 inserts populate the new column,
--      showing the before/after split in Silver
--
-- RUN THIS IN: Azure SQL Server (SSMS or Azure Data Studio)
-- DATABASE:    openflow
-- =============================================================================

USE openflow;
GO

-- =============================================================================
-- STEP 1: Confirm current state before the change
-- =============================================================================

SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'raw' AND TABLE_NAME = 'CMC_PRFA_FACILITY'
ORDER BY ORDINAL_POSITION;

SELECT * FROM raw.CMC_PRFA_FACILITY ORDER BY PRFA_ID;
GO

-- =============================================================================
-- STEP 2: Add the new column (schema change event)
-- =============================================================================

ALTER TABLE raw.CMC_PRFA_FACILITY
    ADD PRFA_COUNTY VARCHAR(30) NULL;
GO

-- Confirm the column was added
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'raw' AND TABLE_NAME = 'CMC_PRFA_FACILITY'
ORDER BY ORDINAL_POSITION;
GO

-- =============================================================================
-- STEP 3: Insert 5 new facility records that include the new column
--         PRFA_IDs 9001-9005 are well above the ~300 seeded rows.
--         PRPR_IDs 1-5 are the first providers seeded by the initial load.
-- =============================================================================

INSERT INTO raw.CMC_PRFA_FACILITY
    (PRFA_ID, PRPR_ID, PRFA_FAC_TYPE, PRFA_BED_CNT, PRFA_LICENSE_NO, PRFA_ACCRED_TYPE, PRFA_COUNTY)
VALUES
    (9001, 1, 'HOSPITAL',  250, 'LIC-OC-9001', 'JCI',  'Orange'),
    (9002, 2, 'HOSPITAL',  180, 'LIC-OC-9002', 'JCI',  'Orange'),
    (9003, 3, 'CLINIC',     40, 'LIC-OC-9003', 'AAAHC','Anaheim'),
    (9004, 4, 'SKILLED_NF', 99, 'LIC-OC-9004', 'CARF', 'Irvine'),
    (9005, 5, 'URGENT',     20, 'LIC-OC-9005', NULL,   'Santa Ana');
GO

-- =============================================================================
-- STEP 4: Confirm final state
-- =============================================================================

SELECT COUNT(*) AS total_rows FROM raw.CMC_PRFA_FACILITY;

-- New records with PRFA_COUNTY populated
SELECT PRFA_ID, PRPR_ID, PRFA_FAC_TYPE, PRFA_BED_CNT, PRFA_ACCRED_TYPE, PRFA_COUNTY
FROM raw.CMC_PRFA_FACILITY
WHERE PRFA_ID >= 9001
ORDER BY PRFA_ID;

-- Before/after split — original rows have NULL for PRFA_COUNTY
SELECT
    CASE WHEN PRFA_COUNTY IS NULL THEN 'Pre-change (no county)' ELSE 'Post-change (' + PRFA_COUNTY + ')' END AS row_origin,
    COUNT(*) AS row_count
FROM raw.CMC_PRFA_FACILITY
GROUP BY CASE WHEN PRFA_COUNTY IS NULL THEN 'Pre-change (no county)' ELSE 'Post-change (' + PRFA_COUNTY + ')' END
ORDER BY 1;
GO
