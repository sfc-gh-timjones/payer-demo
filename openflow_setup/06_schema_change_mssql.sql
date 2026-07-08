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
-- STEP 2: Schema changes
--   a) Widen PRFA_FAC_TYPE from VARCHAR(10) to VARCHAR(50)
--      Source type change — Snowflake maps both to TEXT so no downstream
--      breakage. This demonstrates the pipeline handles type widening cleanly.
--   b) Add PRFA_COUNTY VARCHAR(30) — new column picked up via schema evolution
-- =============================================================================

ALTER TABLE raw.CMC_PRFA_FACILITY
    ALTER COLUMN PRFA_FAC_TYPE VARCHAR(50);
GO

ALTER TABLE raw.CMC_PRFA_FACILITY
    ADD PRFA_COUNTY VARCHAR(30) NULL;
GO

-- Confirm both changes applied
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'raw' AND TABLE_NAME = 'CMC_PRFA_FACILITY'
ORDER BY ORDINAL_POSITION;
GO

-- =============================================================================
-- STEP 3: Insert 5 new facility records
--         PRFA_IDs 9001-9005 are well above the ~300 seeded rows.
--         PRPR_IDs pulled from the actual table to avoid FK violations
--         (hardcoding 1-5 fails if the re-seed doesn't start at 1).
--         PRFA_FAC_TYPE values kept <= 10 chars (original column width).
-- =============================================================================

INSERT INTO raw.CMC_PRFA_FACILITY
    (PRFA_ID, PRPR_ID, PRFA_FAC_TYPE, PRFA_BED_CNT, PRFA_LICENSE_NO, PRFA_ACCRED_TYPE, PRFA_COUNTY)
SELECT
    9000 + ROW_NUMBER() OVER (ORDER BY PRPR_ID) AS PRFA_ID,
    PRPR_ID,
    CASE ROW_NUMBER() OVER (ORDER BY PRPR_ID)
        WHEN 1 THEN 'HOSPITAL'
        WHEN 2 THEN 'HOSPITAL'
        WHEN 3 THEN 'CLINIC'
        WHEN 4 THEN 'SKILLED_NF'
        ELSE        'URGENT'
    END AS PRFA_FAC_TYPE,
    CASE ROW_NUMBER() OVER (ORDER BY PRPR_ID)
        WHEN 1 THEN 250
        WHEN 2 THEN 180
        WHEN 3 THEN  40
        WHEN 4 THEN  99
        ELSE          20
    END AS PRFA_BED_CNT,
    'LIC-OC-900' + CAST(ROW_NUMBER() OVER (ORDER BY PRPR_ID) AS VARCHAR(1)) AS PRFA_LICENSE_NO,
    CASE ROW_NUMBER() OVER (ORDER BY PRPR_ID)
        WHEN 1 THEN 'JCI'
        WHEN 2 THEN 'JCI'
        WHEN 3 THEN 'AAAHC'
        WHEN 4 THEN 'CARF'
        ELSE        NULL
    END AS PRFA_ACCRED_TYPE,
    CASE ROW_NUMBER() OVER (ORDER BY PRPR_ID)
        WHEN 1 THEN 'Orange'
        WHEN 2 THEN 'Orange'
        WHEN 3 THEN 'Anaheim'
        WHEN 4 THEN 'Irvine'
        ELSE        'Santa Ana'
    END AS PRFA_COUNTY
FROM (SELECT TOP 5 PRPR_ID FROM raw.CMC_PRPR_PROV ORDER BY PRPR_ID) t;
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
