-- =============================================================================
-- FILE: 01.1_azure_sql_row_counts.sql
-- PURPOSE: Verification queries for the Facets demo Azure SQL database.
--          Run against the openflow database in Azure SQL directly.
--
-- SECTION 1: Single UNION ALL query — row counts for all 35 tables at once.
-- SECTION 2: Individual SELECT * per table — run whichever you need.
-- =============================================================================

USE [openflow];

-- =============================================================================
-- SECTION 1: Row counts — all 35 tables in one shot
-- =============================================================================

SELECT 'CMC_NWNW_NETWORK'      AS table_name, COUNT(*) AS row_count FROM raw.CMC_NWNW_NETWORK      UNION ALL
SELECT 'CMC_AGAG_AGREEMENT'    AS table_name, COUNT(*) AS row_count FROM raw.CMC_AGAG_AGREEMENT    UNION ALL
SELECT 'CMC_CSCS_CLASS'        AS table_name, COUNT(*) AS row_count FROM raw.CMC_CSCS_CLASS        UNION ALL
SELECT 'CMC_CSPI_CS_PLAN'      AS table_name, COUNT(*) AS row_count FROM raw.CMC_CSPI_CS_PLAN      UNION ALL
SELECT 'CMC_PRPR_PROV'         AS table_name, COUNT(*) AS row_count FROM raw.CMC_PRPR_PROV         UNION ALL
SELECT 'CMC_PRAD_ADDRESS'      AS table_name, COUNT(*) AS row_count FROM raw.CMC_PRAD_ADDRESS      UNION ALL
SELECT 'CMC_PRER_RELATION'     AS table_name, COUNT(*) AS row_count FROM raw.CMC_PRER_RELATION     UNION ALL
SELECT 'CMC_PRFA_FACILITY'     AS table_name, COUNT(*) AS row_count FROM raw.CMC_PRFA_FACILITY     UNION ALL
SELECT 'CMC_PRAF_FAC_AFFIL'    AS table_name, COUNT(*) AS row_count FROM raw.CMC_PRAF_FAC_AFFIL    UNION ALL
SELECT 'CMC_NWPR_RELATION'     AS table_name, COUNT(*) AS row_count FROM raw.CMC_NWPR_RELATION     UNION ALL
SELECT 'CMC_PRCR_CREDEN'       AS table_name, COUNT(*) AS row_count FROM raw.CMC_PRCR_CREDEN       UNION ALL
SELECT 'CMC_PRCF_CERT'         AS table_name, COUNT(*) AS row_count FROM raw.CMC_PRCF_CERT         UNION ALL
SELECT 'CMC_PRRG_REG'          AS table_name, COUNT(*) AS row_count FROM raw.CMC_PRRG_REG          UNION ALL
SELECT 'CMC_PRDS_DATE'         AS table_name, COUNT(*) AS row_count FROM raw.CMC_PRDS_DATE         UNION ALL
SELECT 'CMC_PRCP_COMM_PRAC'    AS table_name, COUNT(*) AS row_count FROM raw.CMC_PRCP_COMM_PRAC    UNION ALL
SELECT 'CMC_PRNP_NPI'          AS table_name, COUNT(*) AS row_count FROM raw.CMC_PRNP_NPI          UNION ALL
SELECT 'CMC_PRLA_LANG'         AS table_name, COUNT(*) AS row_count FROM raw.CMC_PRLA_LANG         UNION ALL
SELECT 'CMC_PRHI_HIST'         AS table_name, COUNT(*) AS row_count FROM raw.CMC_PRHI_HIST         UNION ALL
SELECT 'CMC_PROF_OFF_HRS'      AS table_name, COUNT(*) AS row_count FROM raw.CMC_PROF_OFF_HRS      UNION ALL
SELECT 'CMC_PRWM_PR_MSG'       AS table_name, COUNT(*) AS row_count FROM raw.CMC_PRWM_PR_MSG       UNION ALL
SELECT 'CMC_SBSB_SUBSC'        AS table_name, COUNT(*) AS row_count FROM raw.CMC_SBSB_SUBSC        UNION ALL
SELECT 'CMC_SBCS_CLASS'        AS table_name, COUNT(*) AS row_count FROM raw.CMC_SBCS_CLASS        UNION ALL
SELECT 'CMC_SBEL_ELIG_ENT'     AS table_name, COUNT(*) AS row_count FROM raw.CMC_SBEL_ELIG_ENT     UNION ALL
SELECT 'CMC_MEME_MEMBER'       AS table_name, COUNT(*) AS row_count FROM raw.CMC_MEME_MEMBER       UNION ALL
SELECT 'CMC_MEDD_DEM_DATA'     AS table_name, COUNT(*) AS row_count FROM raw.CMC_MEDD_DEM_DATA     UNION ALL
SELECT 'CMC_MECR_NO_XREF'      AS table_name, COUNT(*) AS row_count FROM raw.CMC_MECR_NO_XREF      UNION ALL
SELECT 'CMC_MEPR_PRIM_PROV'    AS table_name, COUNT(*) AS row_count FROM raw.CMC_MEPR_PRIM_PROV    UNION ALL
SELECT 'CMC_MECB_COB'          AS table_name, COUNT(*) AS row_count FROM raw.CMC_MECB_COB          UNION ALL
SELECT 'CMC_MERP_RELATION'     AS table_name, COUNT(*) AS row_count FROM raw.CMC_MERP_RELATION     UNION ALL
SELECT 'CMC_MEIA_ID_ACT'       AS table_name, COUNT(*) AS row_count FROM raw.CMC_MEIA_ID_ACT       UNION ALL
SELECT 'CMC_MCTR_CD_TRANS'     AS table_name, COUNT(*) AS row_count FROM raw.CMC_MCTR_CD_TRANS     UNION ALL
SELECT 'CMC_MEPE_PRCS_ELIG'    AS table_name, COUNT(*) AS row_count FROM raw.CMC_MEPE_PRCS_ELIG    UNION ALL
SELECT 'CMC_MEES_EXCHANGE'     AS table_name, COUNT(*) AS row_count FROM raw.CMC_MEES_EXCHANGE     UNION ALL
SELECT 'CMC_MECD_MEDICAID'     AS table_name, COUNT(*) AS row_count FROM raw.CMC_MECD_MEDICAID     UNION ALL
SELECT 'CMC_MESU_SUBSIDY'      AS table_name, COUNT(*) AS row_count FROM raw.CMC_MESU_SUBSIDY
ORDER BY row_count desc;

-- =============================================================================
-- SECTION 2: SELECT * per table — highlight and run whichever you need
-- =============================================================================
/*
-- Networks & Agreements
SELECT * FROM raw.CMC_NWNW_NETWORK;
SELECT * FROM raw.CMC_AGAG_AGREEMENT;

-- Coverage Structure
SELECT * FROM raw.CMC_CSCS_CLASS;
SELECT * FROM raw.CMC_CSPI_CS_PLAN;

-- Providers
SELECT * FROM raw.CMC_PRPR_PROV;
SELECT * FROM raw.CMC_PRAD_ADDRESS;
SELECT * FROM raw.CMC_PRER_RELATION;
SELECT * FROM raw.CMC_PRFA_FACILITY;
SELECT * FROM raw.CMC_PRAF_FAC_AFFIL;
SELECT * FROM raw.CMC_NWPR_RELATION;
SELECT * FROM raw.CMC_PRCR_CREDEN;
SELECT * FROM raw.CMC_PRCF_CERT;
SELECT * FROM raw.CMC_PRRG_REG;
SELECT * FROM raw.CMC_PRDS_DATE;
SELECT * FROM raw.CMC_PRCP_COMM_PRAC;
SELECT * FROM raw.CMC_PRNP_NPI;
SELECT * FROM raw.CMC_PRLA_LANG;
SELECT * FROM raw.CMC_PRHI_HIST;
SELECT * FROM raw.CMC_PROF_OFF_HRS;
SELECT * FROM raw.CMC_PRWM_PR_MSG;

-- Subscribers
SELECT * FROM raw.CMC_SBSB_SUBSC;
SELECT * FROM raw.CMC_SBCS_CLASS;
SELECT * FROM raw.CMC_SBEL_ELIG_ENT;

-- Members
SELECT * FROM raw.CMC_MEME_MEMBER;
SELECT * FROM raw.CMC_MEDD_DEM_DATA;
SELECT * FROM raw.CMC_MECR_NO_XREF;
SELECT * FROM raw.CMC_MEPR_PRIM_PROV;
SELECT * FROM raw.CMC_MECB_COB;
SELECT * FROM raw.CMC_MERP_RELATION;
SELECT * FROM raw.CMC_MEIA_ID_ACT;
SELECT * FROM raw.CMC_MCTR_CD_TRANS;

-- Eligibility
SELECT * FROM raw.CMC_MEPE_PRCS_ELIG;
SELECT * FROM raw.CMC_MEES_EXCHANGE;
SELECT * FROM raw.CMC_MECD_MEDICAID;
SELECT * FROM raw.CMC_MESU_SUBSIDY;
*/
