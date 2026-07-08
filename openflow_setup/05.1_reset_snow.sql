-- =============================================================================
-- FILE: 05.1_reset_snow.sql
-- PURPOSE: Full reset of FACETS_BRONZE.RAW schema so Openflow can re-onboard
--          all tables from scratch with a clean initial snapshot.
--
-- USE WHEN: Starting the demo over, recovering from a bad state, or re-running
--           the initial load after testing.
--
-- !! WARNING !! This drops ALL tables in FACETS_BRONZE.RAW and the schema itself.
--               All Bronze data will be lost. Only run this in the demo account.
--
-- =============================================================================
-- STEP ORDER — follow exactly:
--
--   STEP 1 (Openflow UI)   → Remove all tables from replication
--   STEP 2 (This script)   → Drop FACETS_BRONZE.RAW schema in Snowflake
--   STEP 3 (Openflow UI)   → Add tables back — Openflow re-creates the schema
--                            and runs a fresh initial snapshot for each table
--
-- =============================================================================

-- =============================================================================
-- STEP 1: OPENFLOW UI — Remove all tables from replication FIRST
--
--   Before running the DROP below, go into the Openflow connector and either:
--     a) Clear the "Included Table Names" field entirely, OR
--     b) Suspend/stop the connector
--
--   If you drop the schema while Openflow is still replicating, the connector
--   will error on the next polling cycle. Remove tables from replication first,
--   then come back and run STEP 2.
-- =============================================================================



-- =============================================================================
-- STEP 2: Drop FACETS_BRONZE.RAW schema (run this after STEP 1 is complete)
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE FACETS_BRONZE;

-- Confirm what will be dropped
SHOW TABLES IN SCHEMA FACETS_BRONZE.RAW;

-- Drop the entire RAW schema and all tables within it
DROP SCHEMA IF EXISTS FACETS_BRONZE.RAW CASCADE;

-- Verify it's gone
SHOW SCHEMAS IN DATABASE FACETS_BRONZE;



-- =============================================================================
-- STEP 3: OPENFLOW UI — Add tables back into replication
--
--   Paste the table list below into the Openflow connector's
--   "Included Table Names" parameter, then start/resume the connector.
--   Openflow will re-create FACETS_BRONZE.RAW and run an initial snapshot
--   for each table before switching to incremental CDC.
--
--   CMC_NWNW_NETWORK is listed LAST — it is the schema drift demo table.
-- =============================================================================

-- ── SINGLE-LINE (paste directly into Openflow "Included Table Names") ─────────
/*
"openflow"."raw".CMC_AGAG_AGREEMENT, "openflow"."raw".CMC_CSCS_CLASS, "openflow"."raw".CMC_CSPI_CS_PLAN, "openflow"."raw".CMC_PRPR_PROV, "openflow"."raw".CMC_PRAD_ADDRESS, "openflow"."raw".CMC_PRER_RELATION, "openflow"."raw".CMC_PRFA_FACILITY, "openflow"."raw".CMC_PRAF_FAC_AFFIL, "openflow"."raw".CMC_NWPR_RELATION, "openflow"."raw".CMC_PRCR_CREDEN, "openflow"."raw".CMC_PRCF_CERT, "openflow"."raw".CMC_PRRG_REG, "openflow"."raw".CMC_PRDS_DATE, "openflow"."raw".CMC_PRCP_COMM_PRAC, "openflow"."raw".CMC_PRNP_NPI, "openflow"."raw".CMC_PRLA_LANG, "openflow"."raw".CMC_PRHI_HIST, "openflow"."raw".CMC_PROF_OFF_HRS, "openflow"."raw".CMC_PRWM_PR_MSG, "openflow"."raw".CMC_SBSB_SUBSC, "openflow"."raw".CMC_SBCS_CLASS, "openflow"."raw".CMC_SBEL_ELIG_ENT, "openflow"."raw".CMC_MEME_MEMBER, "openflow"."raw".CMC_MEDD_DEM_DATA, "openflow"."raw".CMC_MECR_NO_XREF, "openflow"."raw".CMC_MEPR_PRIM_PROV, "openflow"."raw".CMC_MECB_COB, "openflow"."raw".CMC_MERP_RELATION, "openflow"."raw".CMC_MEIA_ID_ACT, "openflow"."raw".CMC_MCTR_CD_TRANS, "openflow"."raw".CMC_MEPE_PRCS_ELIG, "openflow"."raw".CMC_MEES_EXCHANGE, "openflow"."raw".CMC_MECD_MEDICAID, "openflow"."raw".CMC_MESU_SUBSIDY, "openflow"."raw".CMC_NWNW_NETWORK
*/

-- ── READABLE REFERENCE (one per line) ────────────────────────────────────────
/*
"openflow"."raw".CMC_AGAG_AGREEMENT,
"openflow"."raw".CMC_CSCS_CLASS,
"openflow"."raw".CMC_CSPI_CS_PLAN,
"openflow"."raw".CMC_PRPR_PROV,
"openflow"."raw".CMC_PRAD_ADDRESS,
"openflow"."raw".CMC_PRER_RELATION,
"openflow"."raw".CMC_PRFA_FACILITY,
"openflow"."raw".CMC_PRAF_FAC_AFFIL,
"openflow"."raw".CMC_NWPR_RELATION,
"openflow"."raw".CMC_PRCR_CREDEN,
"openflow"."raw".CMC_PRCF_CERT,
"openflow"."raw".CMC_PRRG_REG,
"openflow"."raw".CMC_PRDS_DATE,
"openflow"."raw".CMC_PRCP_COMM_PRAC,
"openflow"."raw".CMC_PRNP_NPI,
"openflow"."raw".CMC_PRLA_LANG,
"openflow"."raw".CMC_PRHI_HIST,
"openflow"."raw".CMC_PROF_OFF_HRS,
"openflow"."raw".CMC_PRWM_PR_MSG,
"openflow"."raw".CMC_SBSB_SUBSC,
"openflow"."raw".CMC_SBCS_CLASS,
"openflow"."raw".CMC_SBEL_ELIG_ENT,
"openflow"."raw".CMC_MEME_MEMBER,
"openflow"."raw".CMC_MEDD_DEM_DATA,
"openflow"."raw".CMC_MECR_NO_XREF,
"openflow"."raw".CMC_MEPR_PRIM_PROV,
"openflow"."raw".CMC_MECB_COB,
"openflow"."raw".CMC_MERP_RELATION,
"openflow"."raw".CMC_MEIA_ID_ACT,
"openflow"."raw".CMC_MCTR_CD_TRANS,
"openflow"."raw".CMC_MEPE_PRCS_ELIG,
"openflow"."raw".CMC_MEES_EXCHANGE,
"openflow"."raw".CMC_MECD_MEDICAID,
"openflow"."raw".CMC_MESU_SUBSIDY,
"openflow"."raw".CMC_NWNW_NETWORK
*/
