-- =============================================================================
-- FILE: 01_sql_server_ddl.sql
-- PURPOSE: Create all 33 Facets demo tables in Azure SQL Server
--          Tables are ordered parent-before-child to satisfy FK constraints
--
-- EXECUTION: Run against the Azure SQL Server 'openflow' database.
--            Tables land in the 'raw' schema, matching the Openflow landing zone.
--
-- TABLE ORDER (dependency-safe):
--   Group 1 — Root reference tables (no FK dependencies in our set)
--   Group 2 — Provider domain parents
--   Group 3 — Provider domain children
--   Group 4 — Member/Subscriber domain parents
--   Group 5 — Coverage/Plan domain
--   Group 6 — Member domain children
--   Group 7 — Enrollment/Eligibility
-- =============================================================================

USE [openflow];
GO

-- Create schema if it doesn't already exist
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'raw')
    EXEC('CREATE SCHEMA raw');
GO

-- =============================================================================
-- GROUP 1: ROOT REFERENCE TABLES
-- =============================================================================

-- Networks (no FK dependencies)
CREATE TABLE raw.CMC_NWNW_NETWORK (
    NWNW_ID             INT           NOT NULL PRIMARY KEY,
    NWNW_NAME           VARCHAR(60)   NOT NULL,
    NWNW_ABBR           VARCHAR(20)   NULL,
    NWNW_STS            CHAR(2)       NOT NULL DEFAULT 'AC',   -- AC=Active, IN=Inactive
    NWNW_EFF_DT         DATE          NOT NULL,
    NWNW_TERM_DT        DATE          NULL,
    NWNW_TYPE           VARCHAR(10)   NULL,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE()
);

-- Agreements / Provider contracts (no FK dependencies in our set)
CREATE TABLE raw.CMC_AGAG_AGREEMENT (
    AGAG_ID             INT           NOT NULL PRIMARY KEY,
    AGAG_DESC           VARCHAR(80)   NOT NULL,
    AGAG_EFF_DT         DATE          NOT NULL,
    AGAG_TERM_DT        DATE          NULL,
    AGAG_MCTR_TYPE      VARCHAR(10)   NULL,
    AGAG_CAT            CHAR(2)       NULL,
    AGAG_OPTS           VARCHAR(10)   NULL,
    AGAG_VIS_TYPE       CHAR(2)       NULL,
    AGAG_LOCK_TOKEN     INT           NOT NULL DEFAULT 0,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE()
);

-- Coverage structure class (group/employer hierarchy)
CREATE TABLE raw.CMC_CSCS_CLASS (
    CSCS_ID             INT           NOT NULL PRIMARY KEY,
    CSCS_NAME           VARCHAR(60)   NOT NULL,
    CSCS_ABBR           VARCHAR(20)   NULL,
    CSCS_STS            CHAR(2)       NOT NULL DEFAULT 'AC',
    CSCS_EFF_DT         DATE          NOT NULL,
    CSCS_TERM_DT        DATE          NULL,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE()
);

-- =============================================================================
-- GROUP 2: PROVIDER DOMAIN PARENTS
-- =============================================================================

-- Core provider record — PRPR_ENTITY distinguishes Type 1 (I) vs Type 2 (O)
CREATE TABLE raw.CMC_PRPR_PROV (
    PRPR_ID             INT           NOT NULL PRIMARY KEY,
    PRPR_ENTITY         CHAR(1)       NOT NULL,               -- I=Individual(Type1), O=Organization(Type2)
    PRPR_NAME           VARCHAR(80)   NOT NULL,
    PRPR_NPI            VARCHAR(10)   NULL,
    PRPR_TAXONOMY_CD    VARCHAR(20)   NULL,
    PRPR_STS            CHAR(2)       NOT NULL DEFAULT 'AC',   -- AC, IN, SU=Suspended
    PRPR_MCTR_TYPE      VARCHAR(10)   NULL,
    PRPR_MCTR_VAL1      VARCHAR(20)   NULL,
    PRPR_OPTS           VARCHAR(20)   NULL,
    PRPR_PAY_CL_METH    CHAR(2)       NULL,
    PRPR_PREAUTH_IND    CHAR(1)       NULL DEFAULT 'N',
    PRPR_TERM_DT        DATE          NULL,
    PRPR_LOCK_TOKEN     INT           NOT NULL DEFAULT 0,
    PRAD_ID             INT           NULL,
    PRCR_ID             INT           NULL,
    PRCP_ID             INT           NULL,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE(),
    SYS_USUS_ID         VARCHAR(20)   NOT NULL DEFAULT 'SYSTEM',
    ETL_PROCESS_EXECUTION_ID  BIGINT  NULL,
    ROW_HASH_VALUE      VARBINARY(32) NULL
);

-- Subscribers (policyholders)
CREATE TABLE raw.CMC_SBSB_SUBSC (
    SBSB_ID             INT           NOT NULL PRIMARY KEY,
    SBSB_LAST_NAME      VARCHAR(40)   NOT NULL,
    SBSB_FIRST_NAME     VARCHAR(30)   NOT NULL,
    SBSB_DOB            DATE          NOT NULL,
    SBSB_SEX            CHAR(1)       NOT NULL DEFAULT 'U',   -- M, F, U
    SBSB_STS            CHAR(2)       NOT NULL DEFAULT 'AC',
    SBSB_MCTR_TYPE      VARCHAR(10)   NULL,
    SBSB_LOCK_TOKEN     INT           NOT NULL DEFAULT 0,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE(),
    SYS_USUS_ID         VARCHAR(20)   NOT NULL DEFAULT 'SYSTEM',
    ETL_PROCESS_EXECUTION_ID  BIGINT  NULL,
    ROW_HASH_VALUE      VARBINARY(32) NULL
);

-- =============================================================================
-- GROUP 3: PROVIDER DOMAIN CHILDREN
-- =============================================================================

-- Provider addresses
CREATE TABLE raw.CMC_PRAD_ADDRESS (
    PRAD_ID             INT           NOT NULL PRIMARY KEY,
    PRPR_ID             INT           NOT NULL REFERENCES raw.CMC_PRPR_PROV(PRPR_ID),
    PRAD_ADDR1          VARCHAR(55)   NULL,
    PRAD_ADDR2          VARCHAR(55)   NULL,
    PRAD_CITY           VARCHAR(30)   NULL,
    PRAD_ST             CHAR(2)       NULL,
    PRAD_ZIP            VARCHAR(10)   NULL,
    PRAD_TYPE           CHAR(2)       NULL DEFAULT 'PR',       -- PR=Primary, MA=Mailing, BL=Billing
    PRAD_LOCK_TOKEN     INT           NOT NULL DEFAULT 0,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE()
);

-- Network-to-provider participation
CREATE TABLE raw.CMC_NWPR_RELATION (
    NWPR_ID             INT           NOT NULL PRIMARY KEY,
    NWNW_ID             INT           NOT NULL REFERENCES raw.CMC_NWNW_NETWORK(NWNW_ID),
    PRPR_ID             INT           NOT NULL REFERENCES raw.CMC_PRPR_PROV(PRPR_ID),
    AGAG_ID             INT           NOT NULL REFERENCES raw.CMC_AGAG_AGREEMENT(AGAG_ID),
    NWPR_EFF_DT         DATE          NOT NULL,
    NWPR_TERM_DT        DATE          NULL,
    NWPR_PCP_IND        CHAR(1)       NOT NULL DEFAULT 'N',
    NWPR_DIRECTORY_IND  CHAR(1)       NOT NULL DEFAULT 'Y',
    NWPR_ACC_PAT_IND    CHAR(1)       NOT NULL DEFAULT 'Y',
    NWPR_ACC_MEDCD_IND  CHAR(1)       NOT NULL DEFAULT 'Y',
    NWPR_MAX_PATIENT    INT           NULL,
    NWPR_PAT_CTR        INT           NOT NULL DEFAULT 0,
    NWPR_SEX            CHAR(1)       NULL,
    NWPR_MIN_AGE        INT           NULL,
    NWPR_MAX_AGE        INT           NULL,
    NWPR_LOCK_TOKEN     INT           NOT NULL DEFAULT 0,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE(),
    ETL_PROCESS_EXECUTION_ID  BIGINT  NULL,
    ROW_HASH_VALUE      VARBINARY(32) NULL
);

-- Provider-to-entity organization links
CREATE TABLE raw.CMC_PRER_RELATION (
    PRER_ID             INT           NOT NULL PRIMARY KEY,
    PRPR_ID             INT           NOT NULL REFERENCES raw.CMC_PRPR_PROV(PRPR_ID),   -- the individual
    PRER_PRPR_ID        INT           NOT NULL REFERENCES raw.CMC_PRPR_PROV(PRPR_ID),   -- the org they belong to
    PRER_EFF_DT         DATE          NOT NULL,
    PRER_TERM_DT        DATE          NULL,
    PRER_PRPR_ENTITY    CHAR(1)       NULL,
    PRER_REL_VAL_IND    CHAR(1)       NULL,
    PRER_LOCK_TOKEN     INT           NOT NULL DEFAULT 0,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE(),
    ETL_PROCESS_EXECUTION_ID  BIGINT  NULL,
    ROW_HASH_VALUE      VARBINARY(32) NULL
);

-- Provider facility attributes (for Type 2 orgs)
CREATE TABLE raw.CMC_PRFA_FACILITY (
    PRFA_ID             INT           NOT NULL PRIMARY KEY,
    PRPR_ID             INT           NOT NULL REFERENCES raw.CMC_PRPR_PROV(PRPR_ID),
    PRFA_FAC_TYPE       VARCHAR(10)   NULL,
    PRFA_BED_CNT        INT           NULL,
    PRFA_LICENSE_NO     VARCHAR(30)   NULL,
    PRFA_ACCRED_TYPE    VARCHAR(10)   NULL,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE()
);

-- Provider-to-facility affiliations
CREATE TABLE raw.CMC_PRAF_FAC_AFFIL (
    PRAF_ID             INT           NOT NULL PRIMARY KEY,
    PRPR_ID             INT           NOT NULL REFERENCES raw.CMC_PRPR_PROV(PRPR_ID),
    PRAF_FAC_PRPR_ID    INT           NOT NULL REFERENCES raw.CMC_PRPR_PROV(PRPR_ID),
    PRAF_EFF_DT         DATE          NOT NULL,
    PRAF_TERM_DT        DATE          NULL,
    PRAF_AFFIL_TYPE     CHAR(2)       NULL,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE()
);

-- Provider credentials
CREATE TABLE raw.CMC_PRCR_CREDEN (
    PRCR_ID             INT           NOT NULL PRIMARY KEY,
    PRPR_ID             INT           NOT NULL REFERENCES raw.CMC_PRPR_PROV(PRPR_ID),
    PRCR_TYPE           VARCHAR(10)   NULL,
    PRCR_STATUS         CHAR(2)       NULL DEFAULT 'AC',
    PRCR_EFF_DT         DATE          NULL,
    PRCR_TERM_DT        DATE          NULL,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE()
);

-- Board certifications
CREATE TABLE raw.CMC_PRCF_CERT (
    PRCF_ID             INT           NOT NULL PRIMARY KEY,
    PRPR_ID             INT           NOT NULL REFERENCES raw.CMC_PRPR_PROV(PRPR_ID),
    PRCF_BOARD_TYPE     VARCHAR(20)   NULL,
    PRCF_CERT_NO        VARCHAR(30)   NULL,
    PRCF_EFF_DT         DATE          NULL,
    PRCF_TERM_DT        DATE          NULL,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE()
);

-- State registrations and licenses
CREATE TABLE raw.CMC_PRRG_REG (
    PRRG_ID             INT           NOT NULL PRIMARY KEY,
    PRPR_ID             INT           NOT NULL REFERENCES raw.CMC_PRPR_PROV(PRPR_ID),
    PRRG_STATE          CHAR(2)       NOT NULL,
    PRRG_LIC_NO         VARCHAR(30)   NULL,
    PRRG_TYPE           VARCHAR(10)   NULL,
    PRRG_EFF_DT         DATE          NULL,
    PRRG_TERM_DT        DATE          NULL,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE()
);

-- Provider effective dates (effective/termination date tracking per attribute)
CREATE TABLE raw.CMC_PRDS_DATE (
    PRDS_ID             INT           NOT NULL PRIMARY KEY,
    PRPR_ID             INT           NOT NULL REFERENCES raw.CMC_PRPR_PROV(PRPR_ID),
    PRDS_TYPE           VARCHAR(10)   NOT NULL,
    PRDS_EFF_DT         DATE          NOT NULL,
    PRDS_TERM_DT        DATE          NULL,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE()
);

-- Provider commercial practice info
CREATE TABLE raw.CMC_PRCP_COMM_PRAC (
    PRCP_ID             INT           NOT NULL PRIMARY KEY,
    PRPR_ID             INT           NOT NULL REFERENCES raw.CMC_PRPR_PROV(PRPR_ID),
    PRCP_GRP_NAME       VARCHAR(60)   NULL,
    PRCP_SOLO_IND       CHAR(1)       NULL DEFAULT 'N',
    PRCP_HOSP_AFFIL     VARCHAR(60)   NULL,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE()
);

-- NPI identifier cross-reference
CREATE TABLE raw.CMC_PRNP_NPI (
    PRNP_ID             INT           NOT NULL PRIMARY KEY,
    PRPR_ID             INT           NOT NULL REFERENCES raw.CMC_PRPR_PROV(PRPR_ID),
    PRNP_NPI            VARCHAR(10)   NOT NULL,
    PRNP_NPI_TYPE       CHAR(1)       NULL,
    PRNP_EFF_DT         DATE          NULL,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE()
);

-- Provider attribute change history (audit trail)
CREATE TABLE raw.CMC_PRHI_HIST (
    PRHI_ID             INT           NOT NULL PRIMARY KEY,
    PRPR_ID             INT           NOT NULL REFERENCES raw.CMC_PRPR_PROV(PRPR_ID),
    PRHI_FIELD_NM       VARCHAR(30)   NULL,
    PRHI_OLD_VAL        VARCHAR(100)  NULL,
    PRHI_NEW_VAL        VARCHAR(100)  NULL,
    PRHI_CHG_DTM        DATETIME2     NOT NULL DEFAULT GETDATE(),
    PRHI_USUS_ID        VARCHAR(20)   NULL
);

-- Languages spoken by provider
CREATE TABLE raw.CMC_PRLA_LANG (
    PRLA_ID             INT           NOT NULL PRIMARY KEY,
    PRPR_ID             INT           NOT NULL REFERENCES raw.CMC_PRPR_PROV(PRPR_ID),
    PRLA_LANG_CD        VARCHAR(10)   NOT NULL,
    PRLA_FLUENT_IND     CHAR(1)       NULL DEFAULT 'Y',
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE()
);

-- Provider office hours
CREATE TABLE raw.CMC_PROF_OFF_HRS (
    PROF_ID             INT           NOT NULL PRIMARY KEY,
    PRPR_ID             INT           NOT NULL REFERENCES raw.CMC_PRPR_PROV(PRPR_ID),
    PROF_DAY_OF_WK      CHAR(3)       NOT NULL,   -- MON, TUE, WED, THU, FRI, SAT, SUN
    PROF_OPEN_TM        TIME          NULL,
    PROF_CLOSE_TM       TIME          NULL,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE()
);

-- Provider workflow audit messages (leaf table — safe to delete old records)
CREATE TABLE raw.CMC_PRWM_PR_MSG (
    PRWM_ID             INT           NOT NULL PRIMARY KEY,
    PRPR_ID             INT           NOT NULL REFERENCES raw.CMC_PRPR_PROV(PRPR_ID),
    PRWM_MSG_TYPE       VARCHAR(10)   NULL,
    PRWM_MSG_TEXT       VARCHAR(255)  NULL,
    PRWM_MSG_DTM        DATETIME2     NOT NULL DEFAULT GETDATE(),
    PRWM_USUS_ID        VARCHAR(20)   NULL
);

-- =============================================================================
-- GROUP 4: MEMBER/SUBSCRIBER DOMAIN PARENTS
-- =============================================================================

-- Members (Facets grain — one row per enrollment instance)
CREATE TABLE raw.CMC_MEME_MEMBER (
    MEME_ID             INT           NOT NULL PRIMARY KEY,
    SBSB_ID             INT           NOT NULL REFERENCES raw.CMC_SBSB_SUBSC(SBSB_ID),
    MEME_REL_CD         CHAR(2)       NOT NULL DEFAULT '01',   -- 01=Self, 02=Spouse, 03=Child
    MEME_LAST_NAME      VARCHAR(40)   NOT NULL,
    MEME_FIRST_NAME     VARCHAR(30)   NOT NULL,
    MEME_DOB            DATE          NOT NULL,
    MEME_SEX            CHAR(1)       NOT NULL DEFAULT 'U',
    MEME_STS            CHAR(2)       NOT NULL DEFAULT 'AC',
    MEME_MCTR_TYPE      VARCHAR(10)   NULL,
    MEME_LOCK_TOKEN     INT           NOT NULL DEFAULT 0,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE(),
    SYS_USUS_ID         VARCHAR(20)   NOT NULL DEFAULT 'SYSTEM',
    ETL_PROCESS_EXECUTION_ID  BIGINT  NULL,
    ROW_HASH_VALUE      VARBINARY(32) NULL
);

-- =============================================================================
-- GROUP 5: COVERAGE STRUCTURE DOMAIN
-- =============================================================================

-- Coverage structure plan instances (plan enrollment assignments)
CREATE TABLE raw.CMC_CSPI_CS_PLAN (
    CSPI_ID             INT           NOT NULL PRIMARY KEY,
    CSCS_ID             INT           NOT NULL REFERENCES raw.CMC_CSCS_CLASS(CSCS_ID),
    CSPI_NAME           VARCHAR(60)   NOT NULL,
    CSPI_PLAN_TYPE      VARCHAR(10)   NULL,
    CSPI_EFF_DT         DATE          NOT NULL,
    CSPI_TERM_DT        DATE          NULL,
    CSPI_STS            CHAR(2)       NOT NULL DEFAULT 'AC',
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE()
);

-- =============================================================================
-- GROUP 6: MEMBER DOMAIN CHILDREN
-- =============================================================================

-- Subscriber class assignment
CREATE TABLE raw.CMC_SBCS_CLASS (
    SBCS_ID             INT           NOT NULL PRIMARY KEY,
    SBSB_ID             INT           NOT NULL REFERENCES raw.CMC_SBSB_SUBSC(SBSB_ID),
    CSCS_ID             INT           NOT NULL REFERENCES raw.CMC_CSCS_CLASS(CSCS_ID),
    SBCS_EFF_DT         DATE          NOT NULL,
    SBCS_TERM_DT        DATE          NULL,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE()
);

-- Subscriber eligibility entity
CREATE TABLE raw.CMC_SBEL_ELIG_ENT (
    SBEL_ID             INT           NOT NULL PRIMARY KEY,
    SBSB_ID             INT           NOT NULL REFERENCES raw.CMC_SBSB_SUBSC(SBSB_ID),
    SBEL_EFF_DT         DATE          NOT NULL,
    SBEL_TERM_DT        DATE          NULL,
    SBEL_ELIG_STS       CHAR(2)       NOT NULL DEFAULT 'AC',
    SBEL_PLAN_TYPE      VARCHAR(10)   NULL,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE(),
    ETL_PROCESS_EXECUTION_ID  BIGINT  NULL,
    ROW_HASH_VALUE      VARBINARY(32) NULL
);

-- Member demographic data
CREATE TABLE raw.CMC_MEDD_DEM_DATA (
    MEDD_ID             INT           NOT NULL PRIMARY KEY,
    MEME_ID             INT           NOT NULL REFERENCES raw.CMC_MEME_MEMBER(MEME_ID),
    MEDD_ETHNICITY_CD   VARCHAR(10)   NULL,
    MEDD_RACE_CD        VARCHAR(10)   NULL,
    MEDD_LANG_CD        VARCHAR(10)   NULL,
    MEDD_DISABILITY_IND CHAR(1)       NULL DEFAULT 'N',
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE()
);

-- Member ID cross-reference (links Facets ID to external system IDs)
CREATE TABLE raw.CMC_MECR_NO_XREF (
    MECR_ID             INT           NOT NULL PRIMARY KEY,
    MEME_ID             INT           NOT NULL REFERENCES raw.CMC_MEME_MEMBER(MEME_ID),
    MECR_NO             VARCHAR(30)   NOT NULL,
    MECR_TYPE           VARCHAR(10)   NULL,
    MECR_EFF_DT         DATE          NULL,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE()
);

-- Member primary care provider assignment
CREATE TABLE raw.CMC_MEPR_PRIM_PROV (
    MEPR_ID             INT           NOT NULL PRIMARY KEY,
    MEME_ID             INT           NOT NULL REFERENCES raw.CMC_MEME_MEMBER(MEME_ID),
    PRPR_ID             INT           NOT NULL REFERENCES raw.CMC_PRPR_PROV(PRPR_ID),
    MEPR_EFF_DT         DATE          NOT NULL,
    MEPR_TERM_DT        DATE          NULL,
    MEPR_PCP_TYPE       CHAR(2)       NULL DEFAULT 'PCP',
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE(),
    ETL_PROCESS_EXECUTION_ID  BIGINT  NULL,
    ROW_HASH_VALUE      VARBINARY(32) NULL
);

-- Member coordination of benefits (other coverage)
CREATE TABLE raw.CMC_MECB_COB (
    MECB_ID             INT           NOT NULL PRIMARY KEY,
    MEME_ID             INT           NOT NULL REFERENCES raw.CMC_MEME_MEMBER(MEME_ID),
    MECB_CARRIER_NM     VARCHAR(60)   NULL,
    MECB_POLICY_NO      VARCHAR(30)   NULL,
    MECB_EFF_DT         DATE          NULL,
    MECB_TERM_DT        DATE          NULL,
    MECB_COB_ORDER      CHAR(1)       NULL DEFAULT '2',
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE()
);

-- Member relationship to subscriber
CREATE TABLE raw.CMC_MERP_RELATION (
    MERP_ID             INT           NOT NULL PRIMARY KEY,
    MEME_ID             INT           NOT NULL REFERENCES raw.CMC_MEME_MEMBER(MEME_ID),
    MERP_REL_CD         CHAR(2)       NULL,
    MERP_EFF_DT         DATE          NOT NULL,
    MERP_TERM_DT        DATE          NULL,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE()
);

-- Member ID activity log (leaf table — safe to delete old records)
CREATE TABLE raw.CMC_MEIA_ID_ACT (
    MEIA_ID             INT           NOT NULL PRIMARY KEY,
    MEME_ID             INT           NOT NULL REFERENCES raw.CMC_MEME_MEMBER(MEME_ID),
    MEIA_ACT_TYPE       VARCHAR(10)   NULL,
    MEIA_ACT_DTM        DATETIME2     NOT NULL DEFAULT GETDATE(),
    MEIA_USUS_ID        VARCHAR(20)   NULL,
    MEIA_DETAIL         VARCHAR(200)  NULL,
    ETL_PROCESS_EXECUTION_ID  BIGINT  NULL,
    ROW_HASH_VALUE      VARBINARY(32) NULL
);

-- Member contract code transactions (leaf table)
CREATE TABLE raw.CMC_MCTR_CD_TRANS (
    MCTR_ID             INT           NOT NULL PRIMARY KEY,
    MCTR_TYPE           VARCHAR(10)   NOT NULL,
    MCTR_VALUE          VARCHAR(30)   NOT NULL,
    MCTR_DESC           VARCHAR(80)   NULL,
    MCTR_ENTITY         VARCHAR(10)   NULL,
    MCTR_FILTER         VARCHAR(20)   NULL,
    MCTR_SORT           INT           NULL DEFAULT 0,
    MCTR_VALUE_SIZE     INT           NULL,
    MCTR_LOCK_TOKEN     INT           NOT NULL DEFAULT 0,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE(),
    ETL_PROCESS_EXECUTION_ID  BIGINT  NULL,
    ROW_HASH_VALUE      VARBINARY(32) NULL
);

-- =============================================================================
-- GROUP 7: ENROLLMENT / ELIGIBILITY DOMAIN
-- =============================================================================

-- Processed eligibility — the central enrollment/eligibility table (HIGH VOLUME)
CREATE TABLE raw.CMC_MEPE_PRCS_ELIG (
    MEPE_ID             INT           NOT NULL PRIMARY KEY,
    MEME_ID             INT           NOT NULL REFERENCES raw.CMC_MEME_MEMBER(MEME_ID),
    SBSB_ID             INT           NOT NULL REFERENCES raw.CMC_SBSB_SUBSC(SBSB_ID),
    CSPI_ID             INT           NOT NULL REFERENCES raw.CMC_CSPI_CS_PLAN(CSPI_ID),
    MEPE_EFF_DT         DATE          NOT NULL,
    MEPE_TERM_DT        DATE          NULL,
    MEPE_STS            CHAR(2)       NOT NULL DEFAULT 'AC',
    MEPE_ELIG_TYPE      VARCHAR(10)   NULL,
    MEPE_PLAN_TYPE      VARCHAR(10)   NULL,
    MEPE_LOCK_TOKEN     INT           NOT NULL DEFAULT 0,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE(),
    ETL_PROCESS_EXECUTION_ID  BIGINT  NULL,
    ROW_HASH_VALUE      VARBINARY(32) NULL
);

-- Exchange/marketplace enrollment
CREATE TABLE raw.CMC_MEES_EXCHANGE (
    MEES_ID             INT           NOT NULL PRIMARY KEY,
    MEME_ID             INT           NOT NULL REFERENCES raw.CMC_MEME_MEMBER(MEME_ID),
    MEES_EXCHANGE_ID    VARCHAR(30)   NULL,
    MEES_EFF_DT         DATE          NOT NULL,
    MEES_TERM_DT        DATE          NULL,
    MEES_ENROLL_TYPE    VARCHAR(10)   NULL,
    MEES_PLAN_ID        VARCHAR(20)   NULL,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE(),
    ETL_PROCESS_EXECUTION_ID  BIGINT  NULL,
    ROW_HASH_VALUE      VARBINARY(32) NULL
);

-- Medicaid-specific eligibility
CREATE TABLE raw.CMC_MECD_MEDICAID (
    MECD_ID             INT           NOT NULL PRIMARY KEY,
    MEME_ID             INT           NOT NULL REFERENCES raw.CMC_MEME_MEMBER(MEME_ID),
    MECD_AID_CD         VARCHAR(10)   NULL,
    MECD_BIC            VARCHAR(20)   NULL,                    -- Beneficiary Identification Code
    MECD_EFF_DT         DATE          NOT NULL,
    MECD_TERM_DT        DATE          NULL,
    MECD_STS            CHAR(2)       NULL DEFAULT 'AC',
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE(),
    ETL_PROCESS_EXECUTION_ID  BIGINT  NULL,
    ROW_HASH_VALUE      VARBINARY(32) NULL
);

-- Subsidy and premium data
CREATE TABLE raw.CMC_MESU_SUBSIDY (
    MESU_ID             INT           NOT NULL PRIMARY KEY,
    MEME_ID             INT           NOT NULL REFERENCES raw.CMC_MEME_MEMBER(MEME_ID),
    MESU_SUBSIDY_AMT    DECIMAL(10,2) NULL,
    MESU_PREMIUM_AMT    DECIMAL(10,2) NULL,
    MESU_EFF_DT         DATE          NOT NULL,
    MESU_TERM_DT        DATE          NULL,
    MESU_SUBSIDY_TYPE   VARCHAR(10)   NULL,
    SYS_LAST_UPD_DTM    DATETIME2     NOT NULL DEFAULT GETDATE(),
    ETL_PROCESS_EXECUTION_ID  BIGINT  NULL,
    ROW_HASH_VALUE      VARBINARY(32) NULL
);

-- =============================================================================
-- GROUP 8: STANDALONE REFERENCE / LOOKUP TABLE (no FK dependencies)
-- =============================================================================

-- Provider Type reference codes
-- Lookup table with ~15 rows; no FK parents or children
CREATE TABLE raw.CMC_PRTP_PROV_TYPE (
    PRTP_ID             INT           NOT NULL,
    PRTP_CODE           VARCHAR(10)   NOT NULL,
    PRTP_DESC           VARCHAR(100)  NOT NULL,
    PRTP_CATEGORY       VARCHAR(30)   NULL,
    PRTP_ACTIVE_FLAG    CHAR(1)       NOT NULL DEFAULT 'Y',
    PRTP_SORT_ORDER     INT           NULL,
    ETL_PROCESS_EXECUTION_ID BIGINT   NULL,
    ROW_HASH_VALUE      VARBINARY(32) NULL,
    CONSTRAINT PK_CMC_PRTP PRIMARY KEY (PRTP_ID)
);
GO

INSERT INTO raw.CMC_PRTP_PROV_TYPE
    (PRTP_ID, PRTP_CODE, PRTP_DESC, PRTP_CATEGORY, PRTP_ACTIVE_FLAG, PRTP_SORT_ORDER)
VALUES
    (1,  'MD',  'Medical Doctor',                   'Physician',        'Y', 1),
    (2,  'DO',  'Doctor of Osteopathy',              'Physician',        'Y', 2),
    (3,  'NP',  'Nurse Practitioner',                'Mid-Level',        'Y', 3),
    (4,  'PA',  'Physician Assistant',               'Mid-Level',        'Y', 4),
    (5,  'RN',  'Registered Nurse',                  'Nursing',          'Y', 5),
    (6,  'HOS', 'Hospital - Acute Care',             'Facility',         'Y', 6),
    (7,  'SNF', 'Skilled Nursing Facility',          'Facility',         'Y', 7),
    (8,  'HHC', 'Home Health Care Agency',           'Facility',         'Y', 8),
    (9,  'DME', 'Durable Medical Equipment',         'Ancillary',        'Y', 9),
    (10, 'PHR', 'Pharmacy',                          'Ancillary',        'Y', 10),
    (11, 'LAB', 'Clinical Laboratory',               'Ancillary',        'Y', 11),
    (12, 'BHV', 'Behavioral Health Provider',        'Behavioral',       'Y', 12),
    (13, 'DEN', 'Dental Provider',                   'Dental/Vision',    'Y', 13),
    (14, 'VIS', 'Vision Provider',                   'Dental/Vision',    'Y', 14),
    (15, 'TRN', 'Non-Emergency Medical Transport',   'Transportation',   'Y', 15);
GO

PRINT 'All 36 Facets demo tables created in openflow.raw successfully.';
GO
