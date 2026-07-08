-- =============================================================================
-- FILE: 06.1_openflow_table_list.sql
-- PURPOSE: Explicit comma-separated table list for Openflow "Included Table Names"
--          parameter — replaces the regex pattern so each table is enumerated.
--
-- FORMAT:  database.schema.table  (no quotes needed for these names)
-- PASTE INTO:  Openflow UI → Connector → "Included Table Names" parameter
--
-- NOTE: CMC_NWNW_NETWORK is listed LAST — it is the schema drift demo table.
--
-- PASTE FORMAT: Use the single-line block below (safest for Openflow parsing).
--   Newlines around commas may work but are not guaranteed by the processor.
-- =============================================================================

-- ── SINGLE-LINE (safe to paste directly) ─────────────────────────────────────
/*
openflow.raw.CMC_AGAG_AGREEMENT, openflow.raw.CMC_CSCS_CLASS, openflow.raw.CMC_CSPI_CS_PLAN, openflow.raw.CMC_PRPR_PROV, openflow.raw.CMC_PRAD_ADDRESS, openflow.raw.CMC_PRER_RELATION, openflow.raw.CMC_PRFA_FACILITY, openflow.raw.CMC_PRAF_FAC_AFFIL, openflow.raw.CMC_NWPR_RELATION, openflow.raw.CMC_PRCR_CREDEN, openflow.raw.CMC_PRCF_CERT, openflow.raw.CMC_PRRG_REG, openflow.raw.CMC_PRDS_DATE, openflow.raw.CMC_PRCP_COMM_PRAC, openflow.raw.CMC_PRNP_NPI, openflow.raw.CMC_PRLA_LANG, openflow.raw.CMC_PRHI_HIST, openflow.raw.CMC_PROF_OFF_HRS, openflow.raw.CMC_PRWM_PR_MSG, openflow.raw.CMC_SBSB_SUBSC, openflow.raw.CMC_SBCS_CLASS, openflow.raw.CMC_SBEL_ELIG_ENT, openflow.raw.CMC_MEME_MEMBER, openflow.raw.CMC_MEDD_DEM_DATA, openflow.raw.CMC_MECR_NO_XREF, openflow.raw.CMC_MEPR_PRIM_PROV, openflow.raw.CMC_MECB_COB, openflow.raw.CMC_MERP_RELATION, openflow.raw.CMC_MEIA_ID_ACT, openflow.raw.CMC_MCTR_CD_TRANS, openflow.raw.CMC_MEPE_PRCS_ELIG, openflow.raw.CMC_MEES_EXCHANGE, openflow.raw.CMC_MECD_MEDICAID, openflow.raw.CMC_MESU_SUBSIDY, openflow.raw.CMC_NWNW_NETWORK
*/

-- ── READABLE REFERENCE (one per line — do not paste this format into Openflow) ──
/*
openflow.raw.CMC_AGAG_AGREEMENT,
openflow.raw.CMC_CSCS_CLASS,
openflow.raw.CMC_CSPI_CS_PLAN,
openflow.raw.CMC_PRPR_PROV,
openflow.raw.CMC_PRAD_ADDRESS,
openflow.raw.CMC_PRER_RELATION,
openflow.raw.CMC_PRFA_FACILITY,
openflow.raw.CMC_PRAF_FAC_AFFIL,
openflow.raw.CMC_NWPR_RELATION,
openflow.raw.CMC_PRCR_CREDEN,
openflow.raw.CMC_PRCF_CERT,
openflow.raw.CMC_PRRG_REG,
openflow.raw.CMC_PRDS_DATE,
openflow.raw.CMC_PRCP_COMM_PRAC,
openflow.raw.CMC_PRNP_NPI,
openflow.raw.CMC_PRLA_LANG,
openflow.raw.CMC_PRHI_HIST,
openflow.raw.CMC_PROF_OFF_HRS,
openflow.raw.CMC_PRWM_PR_MSG,
openflow.raw.CMC_SBSB_SUBSC,
openflow.raw.CMC_SBCS_CLASS,
openflow.raw.CMC_SBEL_ELIG_ENT,
openflow.raw.CMC_MEME_MEMBER,
openflow.raw.CMC_MEDD_DEM_DATA,
openflow.raw.CMC_MECR_NO_XREF,
openflow.raw.CMC_MEPR_PRIM_PROV,
openflow.raw.CMC_MECB_COB,
openflow.raw.CMC_MERP_RELATION,
openflow.raw.CMC_MEIA_ID_ACT,
openflow.raw.CMC_MCTR_CD_TRANS,
openflow.raw.CMC_MEPE_PRCS_ELIG,
openflow.raw.CMC_MEES_EXCHANGE,
openflow.raw.CMC_MECD_MEDICAID,
openflow.raw.CMC_MESU_SUBSIDY,
openflow.raw.CMC_NWNW_NETWORK   ← schema drift demo table (last)
*/
