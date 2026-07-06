-- =============================================================================
-- FILE: 02_sql_server_permissions.sql
-- PURPOSE: Configure the openflow database for Openflow CDC replication and
--          synthetic data generation. Run AFTER 01_sql_server_ddl.sql.
--
-- Reference: https://docs.snowflake.com/en/user-guide/data-integration/openflow/
--            connectors/sql-server/setup#set-up-your-sql-server-instance
--
-- Run as a user with ALTER DATABASE / GRANT permissions (DBA).
-- openflow_user login is assumed to already exist.
-- =============================================================================

USE [openflow];
GO

-- ---------------------------------------------------------------------------
-- Step 1: Enable Change Tracking on the DATABASE
-- ALREADY ENABLED — commented out. Run manually only if needed on a fresh DB.
-- ---------------------------------------------------------------------------
-- MUST BE RUN IN THE MASTER DATABASE

--CREATE LOGIN openflow_user WITH PASSWORD = 'strongpasswordhere';


-- MUST BE RUN IN YOUR SPECIFIC USER DATABASE

--CREATE USER openflow_user FOR LOGIN openflow_user;

-- ---------------------------------------------------------------------------
-- Step 2: Enable Change Tracking on every table to be replicated
-- Must run for each table before Openflow can replicate it.
-- ---------------------------------------------------------------------------
ALTER TABLE raw.CMC_NWNW_NETWORK         ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_AGAG_AGREEMENT       ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_CSCS_CLASS           ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_PRPR_PROV            ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_SBSB_SUBSC           ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_PRAD_ADDRESS         ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_NWPR_RELATION        ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_PRER_RELATION        ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_PRFA_FACILITY        ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_PRAF_FAC_AFFIL       ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_PRCR_CREDEN         ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_PRCF_CERT            ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_PRRG_REG             ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_PRDS_DATE            ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_PRCP_COMM_PRAC       ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_PRNP_NPI             ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_PRHI_HIST            ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_PRLA_LANG            ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_PROF_OFF_HRS         ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_PRWM_PR_MSG          ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_MEME_MEMBER          ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_CSPI_CS_PLAN         ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_SBCS_CLASS           ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_SBEL_ELIG_ENT        ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_MEDD_DEM_DATA        ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_MECR_NO_XREF         ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_MEPR_PRIM_PROV       ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_MECB_COB             ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_MERP_RELATION        ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_MEIA_ID_ACT          ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_MCTR_CD_TRANS        ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_MEPE_PRCS_ELIG       ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_MEES_EXCHANGE        ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_MECD_MEDICAID        ENABLE CHANGE_TRACKING;
ALTER TABLE raw.CMC_MESU_SUBSIDY         ENABLE CHANGE_TRACKING;
GO
-- ---------------------------------------------------------------------------
-- Step 3: Set default schema to raw
-- Allows unqualified table names (e.g. CMC_PRPR_PROV) in the Snowflake
-- Python stored procs to resolve correctly without adding raw. prefix.
-- ---------------------------------------------------------------------------
ALTER USER openflow_user WITH DEFAULT_SCHEMA = raw;
GO

-- ---------------------------------------------------------------------------
-- Step 4: Grant SELECT + VIEW CHANGE TRACKING on each table (Openflow CDC)
-- Both grants are required per the Openflow SQL Server connector docs.
-- ---------------------------------------------------------------------------
GRANT SELECT ON raw.CMC_NWNW_NETWORK          TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_NWNW_NETWORK TO openflow_user;

GRANT SELECT ON raw.CMC_AGAG_AGREEMENT        TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_AGAG_AGREEMENT TO openflow_user;

GRANT SELECT ON raw.CMC_CSCS_CLASS            TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_CSCS_CLASS TO openflow_user;

GRANT SELECT ON raw.CMC_PRPR_PROV             TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_PRPR_PROV TO openflow_user;

GRANT SELECT ON raw.CMC_SBSB_SUBSC            TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_SBSB_SUBSC TO openflow_user;

GRANT SELECT ON raw.CMC_PRAD_ADDRESS          TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_PRAD_ADDRESS TO openflow_user;

GRANT SELECT ON raw.CMC_NWPR_RELATION         TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_NWPR_RELATION TO openflow_user;

GRANT SELECT ON raw.CMC_PRER_RELATION         TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_PRER_RELATION TO openflow_user;

GRANT SELECT ON raw.CMC_PRFA_FACILITY         TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_PRFA_FACILITY TO openflow_user;

GRANT SELECT ON raw.CMC_PRAF_FAC_AFFIL        TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_PRAF_FAC_AFFIL TO openflow_user;

GRANT SELECT ON raw.CMC_PRCR_CREDEN          TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_PRCR_CREDEN TO openflow_user;

GRANT SELECT ON raw.CMC_PRCF_CERT             TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_PRCF_CERT TO openflow_user;

GRANT SELECT ON raw.CMC_PRRG_REG              TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_PRRG_REG TO openflow_user;

GRANT SELECT ON raw.CMC_PRDS_DATE             TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_PRDS_DATE TO openflow_user;

GRANT SELECT ON raw.CMC_PRCP_COMM_PRAC        TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_PRCP_COMM_PRAC TO openflow_user;

GRANT SELECT ON raw.CMC_PRNP_NPI              TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_PRNP_NPI TO openflow_user;

GRANT SELECT ON raw.CMC_PRHI_HIST             TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_PRHI_HIST TO openflow_user;

GRANT SELECT ON raw.CMC_PRLA_LANG             TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_PRLA_LANG TO openflow_user;

GRANT SELECT ON raw.CMC_PROF_OFF_HRS          TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_PROF_OFF_HRS TO openflow_user;

GRANT SELECT ON raw.CMC_PRWM_PR_MSG           TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_PRWM_PR_MSG TO openflow_user;

GRANT SELECT ON raw.CMC_MEME_MEMBER           TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_MEME_MEMBER TO openflow_user;

GRANT SELECT ON raw.CMC_CSPI_CS_PLAN          TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_CSPI_CS_PLAN TO openflow_user;

GRANT SELECT ON raw.CMC_SBCS_CLASS            TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_SBCS_CLASS TO openflow_user;

GRANT SELECT ON raw.CMC_SBEL_ELIG_ENT         TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_SBEL_ELIG_ENT TO openflow_user;

GRANT SELECT ON raw.CMC_MEDD_DEM_DATA         TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_MEDD_DEM_DATA TO openflow_user;

GRANT SELECT ON raw.CMC_MECR_NO_XREF          TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_MECR_NO_XREF TO openflow_user;

GRANT SELECT ON raw.CMC_MEPR_PRIM_PROV        TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_MEPR_PRIM_PROV TO openflow_user;

GRANT SELECT ON raw.CMC_MECB_COB              TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_MECB_COB TO openflow_user;

GRANT SELECT ON raw.CMC_MERP_RELATION         TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_MERP_RELATION TO openflow_user;

GRANT SELECT ON raw.CMC_MEIA_ID_ACT           TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_MEIA_ID_ACT TO openflow_user;

GRANT SELECT ON raw.CMC_MCTR_CD_TRANS         TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_MCTR_CD_TRANS TO openflow_user;

GRANT SELECT ON raw.CMC_MEPE_PRCS_ELIG        TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_MEPE_PRCS_ELIG TO openflow_user;

GRANT SELECT ON raw.CMC_MEES_EXCHANGE         TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_MEES_EXCHANGE TO openflow_user;

GRANT SELECT ON raw.CMC_MECD_MEDICAID         TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_MECD_MEDICAID TO openflow_user;

GRANT SELECT ON raw.CMC_MESU_SUBSIDY          TO openflow_user;
GRANT VIEW CHANGE TRACKING ON raw.CMC_MESU_SUBSIDY TO openflow_user;
GO

-- ---------------------------------------------------------------------------
-- Step 6: Grant INSERT / UPDATE / DELETE on the raw schema
-- Required for the Snowflake Python stored procs that generate synthetic data.
-- openflow_user's DEFAULT_SCHEMA = raw (set above), so unqualified table
-- names in the sproc INSERT statements resolve to raw.CMC_* automatically.
-- ---------------------------------------------------------------------------
GRANT INSERT ON SCHEMA::raw TO openflow_user;
GRANT UPDATE ON SCHEMA::raw TO openflow_user;
GRANT DELETE ON SCHEMA::raw TO openflow_user;
GO

-- ---------------------------------------------------------------------------
-- Step 7 (Optional): Grant VIEW DEFINITION for User Defined Data Type support
-- Without this, any UDDT columns are silently excluded from replication.
-- ---------------------------------------------------------------------------
GRANT VIEW DEFINITION TO openflow_user;
GO

-- ---------------------------------------------------------------------------
-- VERIFICATION: Confirm Change Tracking is active on all 35 tables
-- Expected: 35 rows returned, one per table in raw schema
-- ---------------------------------------------------------------------------
SELECT
    s.name          AS schema_name,
    t.name          AS table_name,
    ct.is_track_columns_updated_on
FROM sys.change_tracking_tables ct
JOIN sys.tables  t ON ct.object_id = t.object_id
JOIN sys.schemas s ON t.schema_id  = s.schema_id
WHERE s.name = 'raw'
ORDER BY t.name;
GO
