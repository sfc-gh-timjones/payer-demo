-- =============================================================================
-- FILE: 06_schema_change_mssql.sql
-- PURPOSE: Simulate a source schema change on CMC_PRTP_PROV_TYPE in Azure SQL Server.
--          This is the demo script for Scenario 3 (Schema Drift) in the CalOptima
--          RFP 26-038 demonstration.
--
-- TABLE CHOSEN: CMC_PRTP_PROV_TYPE
--   - Standalone reference/lookup table — ZERO FK dependencies in or out
--   - 15 pre-seeded rows (IDs 1-15), demo rows use IDs 9001-9005
--   - No parent or child tables; inserts and deletes are always clean
--   - DELETE WHERE PRTP_ID >= 9001 will never touch the 15 seeded rows
--
-- WHAT THIS DEMONSTRATES:
--   1. TYPE WIDENING — ALTER COLUMN PRTP_DESC VARCHAR(100) → VARCHAR(200)
--      Both map to TEXT in Snowflake, so the pipeline never breaks.
--   2. ADD COLUMN — PRTP_EFFECTIVE_DT DATE added mid-stream
--   3. OPENFLOW DETECTION — schema change captured via CT DDL FlowFile;
--      Bronze table in Snowflake gains the column via schema evolution
--   4. NEW RECORDS WITH NEW COLUMN — 5 inserts populate PRTP_EFFECTIVE_DT,
--      showing the before/after NULL split in Silver
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
WHERE TABLE_SCHEMA = 'raw' AND TABLE_NAME = 'CMC_PRTP_PROV_TYPE'
ORDER BY ORDINAL_POSITION;

SELECT * FROM raw.CMC_PRTP_PROV_TYPE ORDER BY PRTP_ID;
GO

-- =============================================================================
-- STEP 2: Schema changes
--   a) Widen PRTP_DESC from VARCHAR(100) to VARCHAR(200)
--      Source type change — Snowflake maps both to TEXT so no downstream
--      breakage. Demonstrates the pipeline handles type widening cleanly.
--   b) Add PRTP_EFFECTIVE_DT DATE — new column picked up via schema evolution
-- =============================================================================

ALTER TABLE raw.CMC_PRTP_PROV_TYPE
    ALTER COLUMN PRTP_DESC VARCHAR(200);
GO

ALTER TABLE raw.CMC_PRTP_PROV_TYPE
    ADD PRTP_EFFECTIVE_DT DATE NULL;
GO

-- Confirm both changes applied
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'raw' AND TABLE_NAME = 'CMC_PRTP_PROV_TYPE'
ORDER BY ORDINAL_POSITION;
GO

-- =============================================================================
-- STEP 3: Insert 5 new provider type records
--         PRTP_IDs 9001-9005 are well above the 15 seeded rows.
--         PRTP_EFFECTIVE_DT is populated — these are the "post-change" rows.
-- =============================================================================

INSERT INTO raw.CMC_PRTP_PROV_TYPE
    (PRTP_ID, PRTP_CODE, PRTP_DESC, PRTP_CATEGORY, PRTP_ACTIVE_FLAG, PRTP_SORT_ORDER, PRTP_EFFECTIVE_DT)
VALUES
    (9001, 'ACUP', 'Acupuncturist',           'Ancillary',     'Y', 16, '2024-01-01'),
    (9002, 'CHIR', 'Chiropractor',            'Ancillary',     'Y', 17, '2024-01-01'),
    (9003, 'POD',  'Podiatrist',              'Physician',     'Y', 18, '2024-01-01'),
    (9004, 'OPT',  'Optometrist',             'Dental/Vision', 'Y', 19, '2024-01-01'),
    (9005, 'MTL',  'Mental Health Counselor', 'Behavioral',    'Y', 20, '2024-01-01');
GO

-- =============================================================================
-- STEP 4: Confirm final state
-- =============================================================================

SELECT COUNT(*) AS total_rows FROM raw.CMC_PRTP_PROV_TYPE;  -- expect 20

-- New records with PRTP_EFFECTIVE_DT populated
SELECT PRTP_ID, PRTP_CODE, PRTP_DESC, PRTP_CATEGORY, PRTP_EFFECTIVE_DT
FROM raw.CMC_PRTP_PROV_TYPE
WHERE PRTP_ID >= 9001
ORDER BY PRTP_ID;

-- Before/after split — original 15 rows have NULL for PRTP_EFFECTIVE_DT
SELECT
    CASE WHEN PRTP_EFFECTIVE_DT IS NULL
         THEN 'Pre-change (no effective date)'
         ELSE 'Post-change (' + CAST(PRTP_EFFECTIVE_DT AS VARCHAR) + ')'
    END AS row_origin,
    COUNT(*) AS row_count
FROM raw.CMC_PRTP_PROV_TYPE
GROUP BY CASE WHEN PRTP_EFFECTIVE_DT IS NULL
              THEN 'Pre-change (no effective date)'
              ELSE 'Post-change (' + CAST(PRTP_EFFECTIVE_DT AS VARCHAR) + ')'
         END
ORDER BY 1;
GO
