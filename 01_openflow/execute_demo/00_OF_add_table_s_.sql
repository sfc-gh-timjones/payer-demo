-- =============================================================================
-- FILE: 05.2_table_list.sql
-- PURPOSE: Openflow "Included Table Names" reference for re-onboarding all 36
--          Facets demo tables after a reset (05.1_reset_snow.sql).
--
-- USE: Paste the single-line block directly into the Openflow connector's
--      "Included Table Names" field. Openflow will re-create FACETS_BRONZE.RAW
--      and run a fresh initial snapshot for each table.
--
--   CMC_PRTP_PROV_TYPE is listed LAST — it is the schema drift demo table.
-- =============================================================================

-- ── SINGLE-LINE (paste directly into Openflow "Included Table Names") ─────────
/*
"openflow"."raw"."CMC_AGAG_AGREEMENT", "openflow"."raw"."CMC_CSCS_CLASS", "openflow"."raw"."CMC_CSPI_CS_PLAN", "openflow"."raw"."CMC_PRPR_PROV", "openflow"."raw"."CMC_PRAD_ADDRESS", "openflow"."raw"."CMC_PRER_RELATION", "openflow"."raw"."CMC_PRAF_FAC_AFFIL", "openflow"."raw"."CMC_NWPR_RELATION", "openflow"."raw"."CMC_PRCR_CREDEN", "openflow"."raw"."CMC_PRCF_CERT", "openflow"."raw"."CMC_PRRG_REG", "openflow"."raw"."CMC_PRDS_DATE", "openflow"."raw"."CMC_PRCP_COMM_PRAC", "openflow"."raw"."CMC_PRNP_NPI", "openflow"."raw"."CMC_PRLA_LANG", "openflow"."raw"."CMC_PRHI_HIST", "openflow"."raw"."CMC_PROF_OFF_HRS", "openflow"."raw"."CMC_PRWM_PR_MSG", "openflow"."raw"."CMC_SBSB_SUBSC", "openflow"."raw"."CMC_SBCS_CLASS", "openflow"."raw"."CMC_SBEL_ELIG_ENT", "openflow"."raw"."CMC_MEME_MEMBER", "openflow"."raw"."CMC_MEDD_DEM_DATA", "openflow"."raw"."CMC_MECR_NO_XREF", "openflow"."raw"."CMC_MEPR_PRIM_PROV", "openflow"."raw"."CMC_MECB_COB", "openflow"."raw"."CMC_MERP_RELATION", "openflow"."raw"."CMC_MEIA_ID_ACT", "openflow"."raw"."CMC_MCTR_CD_TRANS", "openflow"."raw"."CMC_MEPE_PRCS_ELIG", "openflow"."raw"."CMC_MEES_EXCHANGE", "openflow"."raw"."CMC_MECD_MEDICAID", "openflow"."raw"."CMC_MESU_SUBSIDY", "openflow"."raw"."CMC_NWNW_NETWORK", "openflow"."raw"."CMC_PRFA_FACILITY", "openflow"."raw"."CMC_PRTP_PROV_TYPE"
*/

-- ── READABLE REFERENCE (one per line) ────────────────────────────────────────
/*
"openflow"."raw"."CMC_AGAG_AGREEMENT",
"openflow"."raw"."CMC_CSCS_CLASS",
"openflow"."raw"."CMC_CSPI_CS_PLAN",
"openflow"."raw"."CMC_PRPR_PROV",
"openflow"."raw"."CMC_PRAD_ADDRESS",
"openflow"."raw"."CMC_PRER_RELATION",
"openflow"."raw"."CMC_PRAF_FAC_AFFIL",
"openflow"."raw"."CMC_NWPR_RELATION",
"openflow"."raw"."CMC_PRCR_CREDEN",
"openflow"."raw"."CMC_PRCF_CERT",
"openflow"."raw"."CMC_PRRG_REG",
"openflow"."raw"."CMC_PRDS_DATE",
"openflow"."raw"."CMC_PRCP_COMM_PRAC",
"openflow"."raw"."CMC_PRNP_NPI",
"openflow"."raw"."CMC_PRLA_LANG",
"openflow"."raw"."CMC_PRHI_HIST",
"openflow"."raw"."CMC_PROF_OFF_HRS",
"openflow"."raw"."CMC_PRWM_PR_MSG",
"openflow"."raw"."CMC_SBSB_SUBSC",
"openflow"."raw"."CMC_SBCS_CLASS",
"openflow"."raw"."CMC_SBEL_ELIG_ENT",
"openflow"."raw"."CMC_MEME_MEMBER",
"openflow"."raw"."CMC_MEDD_DEM_DATA",
"openflow"."raw"."CMC_MECR_NO_XREF",
"openflow"."raw"."CMC_MEPR_PRIM_PROV",
"openflow"."raw"."CMC_MECB_COB",
"openflow"."raw"."CMC_MERP_RELATION",
"openflow"."raw"."CMC_MEIA_ID_ACT",
"openflow"."raw"."CMC_MCTR_CD_TRANS",
"openflow"."raw"."CMC_MEPE_PRCS_ELIG",
"openflow"."raw"."CMC_MEES_EXCHANGE",
"openflow"."raw"."CMC_MECD_MEDICAID",
"openflow"."raw"."CMC_MESU_SUBSIDY",
"openflow"."raw"."CMC_NWNW_NETWORK",
"openflow"."raw"."CMC_PRFA_FACILITY",
"openflow"."raw"."CMC_PRTP_PROV_TYPE"
*/


/* TO ADD: 

,"openflow"."raw"."CMC_PRTP_PROV_TYPE"

CMC — ClaimMaster Claims — the system prefix used on all Facets tables in this module
PRTP — PRovider TyPe — the 4-letter entity code for this specific table

*/