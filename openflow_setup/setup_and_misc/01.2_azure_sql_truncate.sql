-- =============================================================================
-- FILE: 01.2_azure_sql_truncate_all.sql
-- PURPOSE: Clear all 35 Facets demo tables in FK-safe deletion order.
--          Run in Azure SQL (openflow database) before re-seeding.
--
-- NOTE: SQL Server cannot TRUNCATE tables referenced by FK constraints even
--       if those constraints are disabled. Use DELETE instead (shown below),
--       or run the sp_MSforeachtable version at the bottom which disables all
--       constraints first.
-- =============================================================================

USE [openflow];

-- =============================================================================
-- OPTION A: DELETE in FK-safe order (safest, no constraint changes needed)
-- =============================================================================

-- Leaf tables first (most dependent)
DELETE FROM raw.CMC_MESU_SUBSIDY;
DELETE FROM raw.CMC_MECD_MEDICAID;
DELETE FROM raw.CMC_MEES_EXCHANGE;
DELETE FROM raw.CMC_MEPE_PRCS_ELIG;
DELETE FROM raw.CMC_MCTR_CD_TRANS;
DELETE FROM raw.CMC_MEIA_ID_ACT;
DELETE FROM raw.CMC_MERP_RELATION;
DELETE FROM raw.CMC_MECB_COB;
DELETE FROM raw.CMC_MEPR_PRIM_PROV;
DELETE FROM raw.CMC_MECR_NO_XREF;
DELETE FROM raw.CMC_MEDD_DEM_DATA;

-- Mid-level subscriber/plan tables
DELETE FROM raw.CMC_SBCS_CLASS;
DELETE FROM raw.CMC_SBEL_ELIG_ENT;
DELETE FROM raw.CMC_CSPI_CS_PLAN;
DELETE FROM raw.CMC_MEME_MEMBER;

-- Provider detail tables
DELETE FROM raw.CMC_PRWM_PR_MSG;
DELETE FROM raw.CMC_PRHI_HIST;
DELETE FROM raw.CMC_PROF_OFF_HRS;
DELETE FROM raw.CMC_PRLA_LANG;
DELETE FROM raw.CMC_PRNP_NPI;
DELETE FROM raw.CMC_PRCP_COMM_PRAC;
DELETE FROM raw.CMC_PRDS_DATE;
DELETE FROM raw.CMC_PRRG_REG;
DELETE FROM raw.CMC_PRCF_CERT;
DELETE FROM raw.CMC_PRCR_CREDEN;
DELETE FROM raw.CMC_PRAF_FAC_AFFIL;
DELETE FROM raw.CMC_PRFA_FACILITY;
DELETE FROM raw.CMC_PRER_RELATION;
DELETE FROM raw.CMC_NWPR_RELATION;
DELETE FROM raw.CMC_PRAD_ADDRESS;

-- Root / parent tables last
DELETE FROM raw.CMC_PRPR_PROV;
DELETE FROM raw.CMC_SBSB_SUBSC;
DELETE FROM raw.CMC_CSCS_CLASS;
DELETE FROM raw.CMC_AGAG_AGREEMENT;
DELETE FROM raw.CMC_NWNW_NETWORK;

-- Verify everything is empty
SELECT 'CMC_NWNW_NETWORK'      AS table_name, COUNT(*) AS row_count FROM raw.CMC_NWNW_NETWORK      UNION ALL
SELECT 'CMC_AGAG_AGREEMENT'    AS table_name, COUNT(*) AS row_count FROM raw.CMC_AGAG_AGREEMENT    UNION ALL
SELECT 'CMC_CSCS_CLASS'        AS table_name, COUNT(*) AS row_count FROM raw.CMC_CSCS_CLASS        UNION ALL
SELECT 'CMC_CSPI_CS_PLAN'      AS table_name, COUNT(*) AS row_count FROM raw.CMC_CSPI_CS_PLAN      UNION ALL
SELECT 'CMC_PRPR_PROV'         AS table_name, COUNT(*) AS row_count FROM raw.CMC_PRPR_PROV         UNION ALL
SELECT 'CMC_SBSB_SUBSC'        AS table_name, COUNT(*) AS row_count FROM raw.CMC_SBSB_SUBSC        UNION ALL
SELECT 'CMC_MEME_MEMBER'       AS table_name, COUNT(*) AS row_count FROM raw.CMC_MEME_MEMBER       UNION ALL
SELECT 'CMC_MEPE_PRCS_ELIG'    AS table_name, COUNT(*) AS row_count FROM raw.CMC_MEPE_PRCS_ELIG    UNION ALL
SELECT 'CMC_MESU_SUBSIDY'      AS table_name, COUNT(*) AS row_count FROM raw.CMC_MESU_SUBSIDY
ORDER BY table_name;

-- =============================================================================
-- OPTION B: Disable all FK constraints → TRUNCATE → re-enable (fastest reset)
-- Use if you want TRUNCATE instead of DELETE (same result for our tables
-- since we don't use IDENTITY columns, but TRUNCATE is instant for large tables)
-- =============================================================================

/*
EXEC sp_MSforeachtable
    @command1 = 'IF OBJECT_SCHEMA_NAME(OBJECT_ID(''?'')) = ''raw'' ALTER TABLE ? NOCHECK CONSTRAINT ALL',
    @whereand = 'AND OBJECT_SCHEMA_NAME(o.id) = ''raw''';

EXEC sp_MSforeachtable
    @command1 = 'IF OBJECT_SCHEMA_NAME(OBJECT_ID(''?'')) = ''raw'' DELETE FROM ?',
    @whereand = 'AND OBJECT_SCHEMA_NAME(o.id) = ''raw''';

EXEC sp_MSforeachtable
    @command1 = 'IF OBJECT_SCHEMA_NAME(OBJECT_ID(''?'')) = ''raw'' ALTER TABLE ? WITH CHECK CHECK CONSTRAINT ALL',
    @whereand = 'AND OBJECT_SCHEMA_NAME(o.id) = ''raw''';
*/
