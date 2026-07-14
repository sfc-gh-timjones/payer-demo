-- =============================================================================
-- FILE: 06_schema_change_mssql.sql
-- PURPOSE: Simulate a source schema change on CMC_PRTP_PROV_TYPE in Azure SQL Server.
--          This is the demo script for Scenario 3 (Schema Drift) in the CalOptima
--          RFP 26-038 demonstration.
--
-- FACETS NAMING CONVENTION:
--   CMC  = ClaimMaster Claims — TriZetto FACETS system prefix on every table
--   PRTP = PRovider TyPe     — 4-letter entity code; all columns in this table
--                              are prefixed PRTP_ to show table ownership
--   Common column suffixes:  _ID = surrogate key, _CD = code, _DESC = description,
--                            _DT = date, _DTM = datetime, _AMT = amount,
--                            _FLAG / _IND = boolean indicator
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
GO

-- =============================================================================
-- STEP 2: Schema changes
-- =============================================================================

-- Change Data Type
ALTER TABLE raw.CMC_PRTP_PROV_TYPE
    ALTER COLUMN PRTP_DESC VARCHAR(200);  -- PRTP_DESC: provider type description (was 100 chars)
GO


-- Add a column
ALTER TABLE raw.CMC_PRTP_PROV_TYPE
    ADD PRTP_EFFECTIVE_DT DATE NULL;      -- PRTP_EFFECTIVE_DT: date this provider type became active in CalOptima's system
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
-- STEP 4: DML changes on existing seeded rows (PRTP_ID 1–15)
-- =============================================================================

-- UPDATE: PRTP_ID 7 — rename to reflect rehabilitation services CalOptima covers
UPDATE raw.CMC_PRTP_PROV_TYPE
SET    PRTP_DESC = 'Skilled Nursing & Rehabilitation Facility'
WHERE  PRTP_ID = 7;

SELECT @@ROWCOUNT AS rows_updated;  -- expect 1
GO

-- DELETE: PRTP_ID 2 (DO - Doctor of Osteopathy) — consolidated into MD category
DELETE FROM raw.CMC_PRTP_PROV_TYPE
WHERE  PRTP_ID = 2;

SELECT @@ROWCOUNT AS rows_deleted;  -- expect 1
GO

-- =============================================================================
-- STEP 5: Confirm final state
-- =============================================================================

SELECT * FROM raw.CMC_PRTP_PROV_TYPE ORDER BY PRTP_ID;  -- expect 19 rows (20 - 1 delete)
