-- =============================================================================
-- FILE: 03_OF_force_error.sql
-- PURPOSE: Force a change tracking permission error to demonstrate Openflow
--          error handling and recovery in the Payer RFP 26-038 demo.
--
-- DEMO FLOW:
--   1. REVOKE VIEW CHANGE TRACKING → Openflow throws a permission error
--   2. INSERT 5 new rows (PRTP_IDs 9006–9010) → changes pile up, untracked
--   3. Show the error in the Openflow UI
--   4. Run STEP 3 (commented out) to restore the grant → Openflow recovers
--
-- RUN THIS IN: Azure SQL Server (SSMS or Azure Data Studio)
-- DATABASE:    openflow
-- =============================================================================

USE openflow;
GO

-- =============================================================================
-- STEP 1: Revoke change tracking view permission from openflow_user
--         This causes Openflow to fail on its next CDC poll for this table.
-- =============================================================================

REVOKE VIEW CHANGE TRACKING ON raw.CMC_PRTP_PROV_TYPE FROM openflow_user;
GO

-- =============================================================================
-- STEP 2: Insert 5 more provider type records (PRTP_IDs 9006–9010)
--         These changes will not be captured while the grant is revoked.
--         They demonstrate data accumulating while the pipeline is broken.
-- =============================================================================

INSERT INTO raw.CMC_PRTP_PROV_TYPE
    (PRTP_ID, PRTP_CODE, PRTP_DESC, PRTP_CATEGORY, PRTP_ACTIVE_FLAG, PRTP_SORT_ORDER, PRTP_EFFECTIVE_DT)
VALUES
    (9006, 'AUDIO', 'Audiologist',               'Ancillary',     'Y', 21, '2024-01-01'),
    (9007, 'RESP',  'Respiratory Therapist',      'Ancillary',     'Y', 22, '2024-01-01'),
    (9008, 'DIET',  'Registered Dietitian',       'Ancillary',     'Y', 23, '2024-01-01'),
    (9009, 'GENE',  'Genetic Counselor',          'Specialist',    'Y', 24, '2024-01-01'),
    (9010, 'PALC',  'Palliative Care Specialist', 'Specialist',    'Y', 25, '2024-01-01');

SELECT @@ROWCOUNT AS rows_inserted;  -- expect 5
GO

-- =============================================================================
-- STEP 3: Restore the grant — run this after showing the error in Openflow
--         Uncomment and execute to let Openflow resume CDC on this table.
-- =============================================================================

-- GRANT VIEW CHANGE TRACKING ON raw.CMC_PRTP_PROV_TYPE TO openflow_user;
-- GO

SELECT
  CHANGE_TRACKING_CURRENT_VERSION() AS current_version,
  CHANGE_TRACKING_MIN_VALID_VERSION(OBJECT_ID('raw.CMC_PRTP_PROV_TYPE')) AS min_valid_version;

