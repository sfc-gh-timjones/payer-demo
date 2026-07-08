-- =============================================================================
-- FILE: 04_initial_load_deploy.sql
-- PURPOSE: One-time setup — create the Network Rule, External Access Integration,
--          and the FACETS_INITIAL_LOAD stored procedure, then call it to seed all
--          35 Facets tables in Azure SQL Server.
--
-- PRE-REQUISITE: Run 03_snowflake_secrets_setup.sql first.
--   FACETS_BRONZE.UTILS.FACETS_SQL_CREDS must exist before this script runs.
--
-- RUN ORDER:
--   1. 01_sql_server_ddl.sql         — create tables in Azure SQL Server
--   2. 02_sql_server_permissions.sql — change tracking + openflow_user grants
--   3. 03_snowflake_secrets_setup.sql — FACETS_BRONZE database, UTILS schema, secret
--   4. THIS FILE                     — Network Rule, EAI, initial load proc, call once
--   5. 05_incremental_load_deploy.sql — incremental proc + scheduled task
--
-- CUSTOMISE BEFORE RUNNING:
--   <AZURE_SQL_HOST>   — e.g. tjones-sql.database.windows.net (just the hostname)
-- =============================================================================

USE DATABASE FACETS_BRONZE;
USE SCHEMA   UTILS;

-- =============================================================================
-- STEP 1: Initial Load Stored Procedure
--         (Network Rule, EAI, and Secret created in 03_snowflake_secrets_setup.sql)
--         Source of truth for this procedure is this file.
--         It runs once to seed all 35 tables; no separate .py file is maintained.
--         ROW_HASH_VALUE is set to NULL (RH = None) — binary digest encoding
--         is not supported by pytds without explicit bytearray handling.
-- =============================================================================

CREATE OR REPLACE PROCEDURE FACETS_BRONZE.UTILS.FACETS_INITIAL_LOAD("SQL_SERVER_HOST" VARCHAR, "SQL_SERVER_DB" VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
ARTIFACT_REPOSITORY = snowflake.snowpark.pypi_shared_repository
PACKAGES = ('snowflake-snowpark-python','python-tds','certifi')
HANDLER = 'initial_load'
EXTERNAL_ACCESS_INTEGRATIONS = (AZURE_SQL_FACETS_EAI)
SECRETS = ('facets_sql_creds'=FACETS_BRONZE.UTILS.FACETS_SQL_CREDS)
COMMENT='Seeds all 35 Facets demo tables in Azure SQL Server with synthetic baseline data'
EXECUTE AS OWNER
AS '
import pytds
import certifi
import random
from datetime import date, timedelta

def rand_date(start_year=2018, end_year=2024):
    start = date(start_year, 1, 1)
    end = date(end_year, 12, 31)
    return start + timedelta(days=random.randint(0, (end - start).days))

def term_date_or_none(eff_dt, pct_termed=0.20):
    if random.random() < pct_termed:
        return eff_dt + timedelta(days=random.randint(365, 1095))
    return None

def etl_exec_id():
    return random.randint(100000, 999999)

def batch_insert(cur, sql_template, rows, batch_size=100):
    if not rows:
        return
    upper = sql_template.upper()
    val_pos = upper.rfind(''VALUES'')
    insert_prefix = sql_template[:val_pos] + ''VALUES ''
    row_pattern = sql_template[val_pos + 6:].strip()
    for i in range(0, len(rows), batch_size):
        chunk = rows[i:i + batch_size]
        cur.execute(
            insert_prefix + '',''.join([row_pattern] * len(chunk)),
            [v for row in chunk for v in row]
        )

FIRST_NAMES = [''James'',''Maria'',''Robert'',''Jennifer'',''David'',''Linda'',''John'',''Patricia'',
               ''Michael'',''Elizabeth'',''William'',''Susan'',''Richard'',''Karen'',''Joseph'',''Nancy'',
               ''Thomas'',''Lisa'',''Carlos'',''Ana'',''Miguel'',''Rosa'',''Kevin'',''Angela'',''Brian'',''Mia'']
LAST_NAMES  = [''Smith'',''Johnson'',''Williams'',''Jones'',''Brown'',''Garcia'',''Martinez'',''Davis'',
               ''Wilson'',''Anderson'',''Taylor'',''Thomas'',''Hernandez'',''Moore'',''Martin'',''Lee'',
               ''Perez'',''Thompson'',''White'',''Harris'',''Nguyen'',''Robinson'',''Clark'',''Lewis'']
CITIES      = [''Orange'',''Anaheim'',''Santa Ana'',''Garden Grove'',''Irvine'',''Tustin'',
               ''Fullerton'',''Costa Mesa'',''Huntington Beach'',''Laguna Niguel'',''Mission Viejo'']
TAXONOMIES  = [''207Q00000X'',''207R00000X'',''208D00000X'',''207QA0505X'',''363L00000X'',
               ''207W00000X'',''2084N0400X'',''193200000X'',''363LP2300X'']
PLAN_TYPES  = [''HMO'',''PPO'',''EPO'',''MEDICAID'',''DSNP'']
LANG_CODES  = [''ENG'',''SPA'',''VIE'',''KOR'',''ZHO'',''TGL'',''ARA'',''ARM'']
DAYS_OF_WK  = [''MON'',''TUE'',''WED'',''THU'',''FRI'']
AID_CODES   = [''01A'',''14E'',''2G'',''30'',''40'',''44'',''58'',''6N'']
MSG_TYPES   = [''CRED_UPDT'',''ADDR_CHG'',''NET_ADD'',''NET_TERM'',''STATUS_CHG'',''NPI_ADD'']

CLEANUP_ORDER = [
    ''raw.CMC_MESU_SUBSIDY'',''raw.CMC_MECD_MEDICAID'',''raw.CMC_MEES_EXCHANGE'',
    ''raw.CMC_MEPE_PRCS_ELIG'',''raw.CMC_MCTR_CD_TRANS'',''raw.CMC_MEIA_ID_ACT'',
    ''raw.CMC_MERP_RELATION'',''raw.CMC_MECB_COB'',''raw.CMC_MEPR_PRIM_PROV'',
    ''raw.CMC_MECR_NO_XREF'',''raw.CMC_MEDD_DEM_DATA'',''raw.CMC_SBCS_CLASS'',
    ''raw.CMC_SBEL_ELIG_ENT'',''raw.CMC_CSPI_CS_PLAN'',''raw.CMC_MEME_MEMBER'',
    ''raw.CMC_PRWM_PR_MSG'',''raw.CMC_PRHI_HIST'',''raw.CMC_PROF_OFF_HRS'',
    ''raw.CMC_PRLA_LANG'',''raw.CMC_PRNP_NPI'',''raw.CMC_PRCP_COMM_PRAC'',
    ''raw.CMC_PRDS_DATE'',''raw.CMC_PRRG_REG'',''raw.CMC_PRCF_CERT'',
    ''raw.CMC_PRCR_CREDEN'',''raw.CMC_PRAF_FAC_AFFIL'',''raw.CMC_PRFA_FACILITY'',
    ''raw.CMC_PRER_RELATION'',''raw.CMC_NWPR_RELATION'',''raw.CMC_PRAD_ADDRESS'',
    ''raw.CMC_PRPR_PROV'',''raw.CMC_SBSB_SUBSC'',''raw.CMC_CSCS_CLASS'',
    ''raw.CMC_AGAG_AGREEMENT'',''raw.CMC_NWNW_NETWORK''
]


def initial_load(session, sql_server_host: str, sql_server_db: str) -> str:
    import _snowflake
    creds = _snowflake.get_username_password(''facets_sql_creds'')
    conn = pytds.connect(
        server=sql_server_host, database=sql_server_db,
        user=creds.username, password=creds.password,
        port=1433, cafile=certifi.where(), validate_host=False,
        timeout=30, autocommit=False
    )
    cur = conn.cursor()
    summary = []

    try:
        for table in CLEANUP_ORDER:
            cur.execute(f"DELETE FROM {table}")
        conn.commit()
        summary.append("cleanup: OK")

        ids = {t: 1000 for t in [
            ''nwnw'',''agag'',''cscs'',''prpr'',''sbsb'',''prad'',''nwpr'',''prer'',''prfa'',''praf'',
            ''prcr'',''prcf'',''prrg'',''prds'',''prcp'',''prnp'',''prhi'',''prla'',''prof'',''prwm'',
            ''meme'',''cspi'',''sbcs'',''sbel'',''medd'',''mecr'',''mepr'',''mecb'',''merp'',''meia'',
            ''mctr'',''mepe'',''mees'',''mecd'',''mesu''
        ]}
        def nxt(k):
            ids[k] += 1; return ids[k]
        EX = etl_exec_id; RH = None

        nw_rows = []
        networks = []
        for _ in range(20):
            nid = nxt(''nwnw''); eff = rand_date(2015,2020); networks.append(nid)
            nw_rows.append((nid, f"Network {nid} - {random.choice([''HMO'',''PPO'',''MEDICAID''])}", f"NET{nid}", eff, random.choice([''HMO'',''PPO'',''MCD'',''DSNP''])))
        batch_insert(cur, "INSERT INTO raw.CMC_NWNW_NETWORK (NWNW_ID,NWNW_NAME,NWNW_ABBR,NWNW_STS,NWNW_EFF_DT,NWNW_TERM_DT,NWNW_TYPE) VALUES (%s,%s,%s,''AC'',%s,NULL,%s)", nw_rows)
        conn.commit(); summary.append(f"CMC_NWNW_NETWORK: {len(networks)}")

        agreements = []; ag_rows = []
        for _ in range(50):
            aid = nxt(''agag''); eff = rand_date(2016,2022); agreements.append(aid)
            ag_rows.append((aid, f"Agreement {aid}", eff, term_date_or_none(eff,0.15), random.choice([''FFS'',''CAP'',''PER_DIEM'']), random.choice([''PR'',''FA''])))
        batch_insert(cur, "INSERT INTO raw.CMC_AGAG_AGREEMENT (AGAG_ID,AGAG_DESC,AGAG_EFF_DT,AGAG_TERM_DT,AGAG_MCTR_TYPE,AGAG_CAT) VALUES (%s,%s,%s,%s,%s,%s)", ag_rows)
        conn.commit(); summary.append(f"CMC_AGAG_AGREEMENT: {len(agreements)}")

        classes = []; cs_rows = []
        for _ in range(30):
            cid = nxt(''cscs''); classes.append(cid)
            cs_rows.append((cid, f"Class {cid} - {random.choice([''Medi-Cal'',''DSNP'',''HMO'',''PPO''])}", f"CLS{cid}", rand_date(2018,2022)))
        batch_insert(cur, "INSERT INTO raw.CMC_CSCS_CLASS (CSCS_ID,CSCS_NAME,CSCS_ABBR,CSCS_STS,CSCS_EFF_DT) VALUES (%s,%s,%s,''AC'',%s)", cs_rows)
        conn.commit(); summary.append(f"CMC_CSCS_CLASS: {len(classes)}")

        providers_type1 = []; providers_type2 = []; pr_rows = []
        for i in range(5000):
            pid = nxt(''prpr''); entity = ''O'' if i < 800 else ''I''
            name = (f"{random.choice(LAST_NAMES)} Medical Group" if entity==''O''
                    else f"Dr. {random.choice(LAST_NAMES)}, {random.choice([''MD'',''DO'',''NP'',''PA''])}")
            npi = ''''.join([str(random.randint(0,9)) for _ in range(10)])
            sts = ''AC'' if random.random()>0.05 else random.choice([''IN'',''SU''])
            tax = random.choice(TAXONOMIES) if entity==''I'' else ''193200000X''
            pr_rows.append((pid, entity, name, npi, tax, sts, random.choice([''FFS'',''CAP'']), EX(), RH))
            (providers_type2 if entity==''O'' else providers_type1).append(pid)
        batch_insert(cur, "INSERT INTO raw.CMC_PRPR_PROV (PRPR_ID,PRPR_ENTITY,PRPR_NAME,PRPR_NPI,PRPR_TAXONOMY_CD,PRPR_STS,PRPR_MCTR_TYPE,PRPR_OPTS,PRPR_LOCK_TOKEN,SYS_USUS_ID,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,%s,%s,''Y'',0,''ETL_INIT'',%s,%s)", pr_rows)
        conn.commit(); all_providers = providers_type1 + providers_type2
        summary.append(f"CMC_PRPR_PROV: {len(all_providers)}")

        subscribers = []; sub_rows = []
        for _ in range(50000):
            sid = nxt(''sbsb''); subscribers.append(sid)
            dob = date.today() - timedelta(days=random.randint(365*18, 365*80))
            sub_rows.append((sid, random.choice(LAST_NAMES), random.choice(FIRST_NAMES), dob,
                             random.choice([''M'',''F'',''U'']), random.choice([''MEDCAID'',''COMM'',''DSNP'']), EX(), RH))
        batch_insert(cur, "INSERT INTO raw.CMC_SBSB_SUBSC (SBSB_ID,SBSB_LAST_NAME,SBSB_FIRST_NAME,SBSB_DOB,SBSB_SEX,SBSB_STS,SBSB_MCTR_TYPE,SYS_USUS_ID,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,''AC'',%s,''ETL_INIT'',%s,%s)", sub_rows)
        conn.commit(); summary.append(f"CMC_SBSB_SUBSC: {len(subscribers)}")

        addr_rows = []
        for pid in all_providers:
            addr_rows.append((nxt(''prad''), pid, f"{random.randint(100,9999)} {random.choice([''Main'',''Oak'',''Harbor''])} St", random.choice(CITIES), f"926{random.randint(10,99)}"))
        batch_insert(cur, "INSERT INTO raw.CMC_PRAD_ADDRESS (PRAD_ID,PRPR_ID,PRAD_ADDR1,PRAD_CITY,PRAD_ST,PRAD_ZIP,PRAD_TYPE) VALUES (%s,%s,%s,%s,''CA'',%s,''PR'')", addr_rows)
        conn.commit(); summary.append(f"CMC_PRAD_ADDRESS: {len(addr_rows)}")

        nwpr_rows = []
        for pid in all_providers:
            for _ in range(random.randint(1,3)):
                nrid = nxt(''nwpr''); eff = rand_date(2018,2023)
                nwpr_rows.append((nrid, random.choice(networks), pid, random.choice(agreements), eff, term_date_or_none(eff,0.10), ''Y'' if random.random()>0.7 else ''N'', random.randint(0,1200), EX(), RH))
        batch_insert(cur, "INSERT INTO raw.CMC_NWPR_RELATION (NWPR_ID,NWNW_ID,PRPR_ID,AGAG_ID,NWPR_EFF_DT,NWPR_TERM_DT,NWPR_PCP_IND,NWPR_DIRECTORY_IND,NWPR_ACC_PAT_IND,NWPR_ACC_MEDCD_IND,NWPR_PAT_CTR,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,%s,%s,''Y'',''Y'',''Y'',%s,%s,%s)", nwpr_rows)
        conn.commit(); summary.append(f"CMC_NWPR_RELATION: {len(nwpr_rows)}")

        prer_rows = []
        for pid in random.sample(providers_type1, min(800,len(providers_type1))):
            prid = nxt(''prer''); eff = rand_date(2018,2023)
            prer_rows.append((prid, pid, random.choice(providers_type2), eff, term_date_or_none(eff,0.15), EX(), RH))
        batch_insert(cur, "INSERT INTO raw.CMC_PRER_RELATION (PRER_ID,PRPR_ID,PRER_PRPR_ID,PRER_EFF_DT,PRER_TERM_DT,PRER_PRPR_ENTITY,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,''O'',%s,%s)", prer_rows)
        conn.commit(); summary.append(f"CMC_PRER_RELATION: {len(prer_rows)}")

        prfa_rows = []
        for pid in random.sample(providers_type2, min(300,len(providers_type2))):
            prfa_rows.append((nxt(''prfa''), pid, random.choice([''HOSP'',''CLIN'',''ASC'',''SNF'']), random.randint(20,500), f"LIC{random.randint(100000,999999)}", random.choice([''JCAHO'',''NCQA'',''AAAHC'',''CARF''])))
        batch_insert(cur, "INSERT INTO raw.CMC_PRFA_FACILITY (PRFA_ID,PRPR_ID,PRFA_FAC_TYPE,PRFA_BED_CNT,PRFA_LICENSE_NO,PRFA_ACCRED_TYPE) VALUES (%s,%s,%s,%s,%s,%s)", prfa_rows)
        conn.commit(); summary.append(f"CMC_PRFA_FACILITY: {len(prfa_rows)}")

        praf_rows = []
        for pid in random.sample(providers_type1, min(500,len(providers_type1))):
            eff = rand_date(2018,2023)
            praf_rows.append((nxt(''praf''), pid, random.choice(providers_type2), eff, term_date_or_none(eff,0.10), random.choice([''AD'',''PR'',''ST''])))
        batch_insert(cur, "INSERT INTO raw.CMC_PRAF_FAC_AFFIL (PRAF_ID,PRPR_ID,PRAF_FAC_PRPR_ID,PRAF_EFF_DT,PRAF_TERM_DT,PRAF_AFFIL_TYPE) VALUES (%s,%s,%s,%s,%s,%s)", praf_rows)
        conn.commit(); summary.append(f"CMC_PRAF_FAC_AFFIL: {len(praf_rows)}")

        cr_rows=[]; cf_rows=[]; rg_rows=[]; ds_rows=[]; cp_rows=[]; np_rows=[]; la_rows=[]; of_rows=[]
        for pid in random.sample(providers_type1, min(600,len(providers_type1))):
            cr_rows.append((nxt(''prcr''), pid, random.choice([''CRED'',''RECRED'']), rand_date(2018,2023)))
        for pid in random.sample(providers_type1, min(400,len(providers_type1))):
            cf_rows.append((nxt(''prcf''), pid, random.choice([''ABIM'',''ABFM'',''ABPEDS'']), f"CERT{random.randint(10000,99999)}", rand_date(2015,2022)))
        for pid in random.sample(all_providers, min(1500,len(all_providers))):
            rg_rows.append((nxt(''prrg''), pid, f"CA{random.randint(100000,999999)}", rand_date(2015,2022)))
        for pid in random.sample(all_providers, min(1000,len(all_providers))):
            for dt in [''EFF'',''CRED'']:
                ds_rows.append((nxt(''prds''), pid, dt, rand_date(2018,2023)))
        for pid in random.sample(providers_type1, min(700,len(providers_type1))):
            cp_rows.append((nxt(''prcp''), pid, f"{random.choice(LAST_NAMES)} Associates", ''Y'' if random.random()<0.3 else ''N''))
        for pid in random.sample(all_providers, min(500,len(all_providers))):
            np_rows.append((nxt(''prnp''), pid, ''''.join([str(random.randint(0,9)) for _ in range(10)]), ''1'' if pid in providers_type1 else ''2'', rand_date(2018,2022)))
        for pid in random.sample(all_providers, min(800,len(all_providers))):
            for lang in random.sample(LANG_CODES, random.randint(1,3)):
                la_rows.append((nxt(''prla''), pid, lang))
        for pid in random.sample(all_providers, min(1000,len(all_providers))):
            for day in random.sample(DAYS_OF_WK, random.randint(3,5)):
                of_rows.append((nxt(''prof''), pid, day))
        batch_insert(cur, "INSERT INTO raw.CMC_PRCR_CREDEN (PRCR_ID,PRPR_ID,PRCR_TYPE,PRCR_STATUS,PRCR_EFF_DT) VALUES (%s,%s,%s,''AC'',%s)", cr_rows)
        batch_insert(cur, "INSERT INTO raw.CMC_PRCF_CERT (PRCF_ID,PRPR_ID,PRCF_BOARD_TYPE,PRCF_CERT_NO,PRCF_EFF_DT) VALUES (%s,%s,%s,%s,%s)", cf_rows)
        batch_insert(cur, "INSERT INTO raw.CMC_PRRG_REG (PRRG_ID,PRPR_ID,PRRG_STATE,PRRG_LIC_NO,PRRG_TYPE,PRRG_EFF_DT) VALUES (%s,%s,''CA'',%s,''MD_LIC'',%s)", rg_rows)
        batch_insert(cur, "INSERT INTO raw.CMC_PRDS_DATE (PRDS_ID,PRPR_ID,PRDS_TYPE,PRDS_EFF_DT) VALUES (%s,%s,%s,%s)", ds_rows)
        batch_insert(cur, "INSERT INTO raw.CMC_PRCP_COMM_PRAC (PRCP_ID,PRPR_ID,PRCP_GRP_NAME,PRCP_SOLO_IND) VALUES (%s,%s,%s,%s)", cp_rows)
        batch_insert(cur, "INSERT INTO raw.CMC_PRNP_NPI (PRNP_ID,PRPR_ID,PRNP_NPI,PRNP_NPI_TYPE,PRNP_EFF_DT) VALUES (%s,%s,%s,%s,%s)", np_rows)
        batch_insert(cur, "INSERT INTO raw.CMC_PRLA_LANG (PRLA_ID,PRPR_ID,PRLA_LANG_CD,PRLA_FLUENT_IND) VALUES (%s,%s,%s,''Y'')", la_rows)
        batch_insert(cur, "INSERT INTO raw.CMC_PROF_OFF_HRS (PROF_ID,PRPR_ID,PROF_DAY_OF_WK,PROF_OPEN_TM,PROF_CLOSE_TM) VALUES (%s,%s,%s,''08:00:00'',''17:00:00'')", of_rows)
        conn.commit(); summary.append("CMC_PRCR/PRCF/PRRG/PRDS/PRCP/PRNP/PRLA/PROF: populated")

        prhi_rows=[]; prwm_rows=[]
        for pid in random.sample(all_providers, min(400,len(all_providers))):
            for _ in range(random.randint(1,3)):
                old_v, new_v = random.choice([''AC'',''IN'']), random.choice([''IN'',''AC'',''SU''])
                prhi_rows.append((nxt(''prhi''), pid, random.choice([''PRPR_STS'',''PRPR_NAME'',''PRPR_NPI'']), old_v, new_v))
        for pid in random.sample(all_providers, min(500,len(all_providers))):
            for _ in range(random.randint(1,5)):
                prwm_rows.append((nxt(''prwm''), pid, random.choice(MSG_TYPES), f"Audit for PRPR {pid}"))
        batch_insert(cur, "INSERT INTO raw.CMC_PRHI_HIST (PRHI_ID,PRPR_ID,PRHI_FIELD_NM,PRHI_OLD_VAL,PRHI_NEW_VAL,PRHI_USUS_ID) VALUES (%s,%s,%s,%s,%s,''ETL_INIT'')", prhi_rows)
        batch_insert(cur, "INSERT INTO raw.CMC_PRWM_PR_MSG (PRWM_ID,PRPR_ID,PRWM_MSG_TYPE,PRWM_MSG_TEXT,PRWM_USUS_ID) VALUES (%s,%s,%s,%s,''ETL_INIT'')", prwm_rows)
        conn.commit(); summary.append(f"CMC_PRHI({len(prhi_rows)})/PRWM({len(prwm_rows)}): populated")

        members=[]; meme_rows=[]
        for sid in subscribers:
            for rel_idx in range(1 if random.random()>0.4 else random.randint(2,4)):
                mid = nxt(''meme''); rel = ''01'' if rel_idx==0 else random.choice([''02'',''03'',''04''])
                dob = date.today() - timedelta(days=random.randint(365, 365*75))
                members.append(mid)
                meme_rows.append((mid, sid, rel, random.choice(LAST_NAMES), random.choice(FIRST_NAMES),
                                  dob, random.choice([''M'',''F'',''U'']), random.choice([''MEDCAID'',''COMM'',''DSNP'']), EX(), RH))
        batch_insert(cur, "INSERT INTO raw.CMC_MEME_MEMBER (MEME_ID,SBSB_ID,MEME_REL_CD,MEME_LAST_NAME,MEME_FIRST_NAME,MEME_DOB,MEME_SEX,MEME_STS,MEME_MCTR_TYPE,SYS_USUS_ID,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,%s,%s,''AC'',%s,''ETL_INIT'',%s,%s)", meme_rows)
        conn.commit(); summary.append(f"CMC_MEME_MEMBER: {len(members)}")

        plans=[]; pl_rows=[]
        for _ in range(80):
            cid = nxt(''cspi''); plans.append(cid)
            pl_rows.append((cid, random.choice(classes), f"Plan {cid} - {random.choice(PLAN_TYPES)} {random.randint(2020,2025)}", random.choice(PLAN_TYPES), rand_date(2018,2022)))
        batch_insert(cur, "INSERT INTO raw.CMC_CSPI_CS_PLAN (CSPI_ID,CSCS_ID,CSPI_NAME,CSPI_PLAN_TYPE,CSPI_EFF_DT,CSPI_STS) VALUES (%s,%s,%s,%s,%s,''AC'')", pl_rows)
        conn.commit(); summary.append(f"CMC_CSPI_CS_PLAN: {len(plans)}")

        sbcs_rows=[]; sbel_rows=[]
        for sid in subscribers:
            eff = rand_date(2019,2023)
            sbcs_rows.append((nxt(''sbcs''), sid, random.choice(classes), eff))
            sbel_rows.append((nxt(''sbel''), sid, eff, random.choice(PLAN_TYPES), EX(), RH))
        batch_insert(cur, "INSERT INTO raw.CMC_SBCS_CLASS (SBCS_ID,SBSB_ID,CSCS_ID,SBCS_EFF_DT) VALUES (%s,%s,%s,%s)", sbcs_rows)
        batch_insert(cur, "INSERT INTO raw.CMC_SBEL_ELIG_ENT (SBEL_ID,SBSB_ID,SBEL_EFF_DT,SBEL_ELIG_STS,SBEL_PLAN_TYPE,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,''AC'',%s,%s,%s)", sbel_rows)
        conn.commit(); summary.append(f"CMC_SBCS_CLASS/SBEL_ELIG_ENT: {len(subscribers)} each")

        medd_rows=[]; mecr_rows=[]; mepr_rows=[]; mecb_rows=[]; merp_rows=[]; meia_rows=[]; mctr_rows=[]
        pcp_pool = random.sample(providers_type1, max(1,len(providers_type1)//2))
        for mid in random.sample(members, int(len(members)*0.6)):
            medd_rows.append((nxt(''medd''), mid, random.choice([''NON_HISP'',''HISP'',''UNK'']), random.choice([''WHITE'',''BLACK'',''ASIAN'',''OTHER'',''UNK'']), random.choice(LANG_CODES)))
        for mid in members:
            mecr_rows.append((nxt(''mecr''), mid, f"MC{random.randint(10000000,99999999)}", rand_date(2019,2023)))
        for mid in random.sample(members, int(len(members)*0.80)):
            eff = rand_date(2020,2023)
            mepr_rows.append((nxt(''mepr''), mid, random.choice(pcp_pool), eff, EX(), RH))
        for mid in random.sample(members, int(len(members)*0.10)):
            mecb_rows.append((nxt(''mecb''), mid, random.choice([''Blue Shield'',''Aetna'',''Cigna'',''UHC'']), f"POL{random.randint(100000,999999)}", rand_date(2020,2023)))
        for mid in random.sample(members, int(len(members)*0.40)):
            merp_rows.append((nxt(''merp''), mid, random.choice([''02'',''03'',''04'']), rand_date(2020,2023)))
        for mid in random.sample(members, int(len(members)*0.90)):
            meia_rows.append((nxt(''meia''), mid, EX(), RH))
        for _ in range(200):
            cid2 = nxt(''mctr'')
            mctr_rows.append((cid2, random.choice([''PLAN'',''LOB'',''GRP'',''AID'']), f"CD{random.randint(100,999)}", f"Code {cid2}", cid2%100, EX(), RH))

        batch_insert(cur, "INSERT INTO raw.CMC_MEDD_DEM_DATA (MEDD_ID,MEME_ID,MEDD_ETHNICITY_CD,MEDD_RACE_CD,MEDD_LANG_CD) VALUES (%s,%s,%s,%s,%s)", medd_rows)
        batch_insert(cur, "INSERT INTO raw.CMC_MECR_NO_XREF (MECR_ID,MEME_ID,MECR_NO,MECR_TYPE,MECR_EFF_DT) VALUES (%s,%s,%s,''MEDI_CAL'',%s)", mecr_rows)
        # MEPR_PCP_TYPE is CHAR(2) — use ''PC'' not ''PCP''
        batch_insert(cur, "INSERT INTO raw.CMC_MEPR_PRIM_PROV (MEPR_ID,MEME_ID,PRPR_ID,MEPR_EFF_DT,MEPR_PCP_TYPE,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,''PC'',%s,%s)", mepr_rows)
        batch_insert(cur, "INSERT INTO raw.CMC_MECB_COB (MECB_ID,MEME_ID,MECB_CARRIER_NM,MECB_POLICY_NO,MECB_EFF_DT,MECB_COB_ORDER) VALUES (%s,%s,%s,%s,%s,''2'')", mecb_rows)
        batch_insert(cur, "INSERT INTO raw.CMC_MERP_RELATION (MERP_ID,MEME_ID,MERP_REL_CD,MERP_EFF_DT) VALUES (%s,%s,%s,%s)", merp_rows)
        batch_insert(cur, "INSERT INTO raw.CMC_MEIA_ID_ACT (MEIA_ID,MEME_ID,MEIA_ACT_TYPE,MEIA_USUS_ID,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,''ID_ISSUE'',''ETL_INIT'',%s,%s)", meia_rows)
        batch_insert(cur, "INSERT INTO raw.CMC_MCTR_CD_TRANS (MCTR_ID,MCTR_TYPE,MCTR_VALUE,MCTR_DESC,MCTR_ENTITY,MCTR_SORT,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,''MEMBER'',%s,%s,%s)", mctr_rows)
        conn.commit(); summary.append(f"CMC_MEDD({len(medd_rows)})/MECR({len(mecr_rows)})/MEPR({len(mepr_rows)})/MECB({len(mecb_rows)})/MERP({len(merp_rows)})/MEIA({len(meia_rows)})/MCTR(200): populated")

        mem_to_sub = {r[0]: r[1] for r in meme_rows}; mepe_rows=[]
        for mid in members:
            sid = mem_to_sub.get(mid, random.choice(subscribers)); eff = rand_date(2020,2023); pid = nxt(''mepe'')
            mepe_rows.append((pid, mid, sid, random.choice(plans), eff, term_date_or_none(eff,0.15), random.choice(PLAN_TYPES), EX(), RH))
            if random.random()<0.20:
                eff2 = eff + timedelta(days=random.randint(180,730))
                mepe_rows.append((nxt(''mepe''), mid, sid, random.choice(plans), eff2, None, random.choice(PLAN_TYPES), EX(), RH))
        batch_insert(cur, "INSERT INTO raw.CMC_MEPE_PRCS_ELIG (MEPE_ID,MEME_ID,SBSB_ID,CSPI_ID,MEPE_EFF_DT,MEPE_TERM_DT,MEPE_STS,MEPE_ELIG_TYPE,MEPE_PLAN_TYPE,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,%s,''AC'',''MEDICAID'',%s,%s,%s)", mepe_rows)
        conn.commit(); summary.append(f"CMC_MEPE_PRCS_ELIG: {len(mepe_rows)}")

        mees_rows=[]; mecd_rows=[]; mesu_rows=[]
        for mid in random.sample(members, int(len(members)*0.15)):
            mees_rows.append((nxt(''mees''), mid, f"EX{random.randint(10000000,99999999)}", rand_date(2021,2023), EX(), RH))
        for mid in random.sample(members, int(len(members)*0.85)):
            mecd_rows.append((nxt(''mecd''), mid, random.choice(AID_CODES), f"BIC{random.randint(1000000,9999999)}", rand_date(2019,2023), EX(), RH))
        for mid in random.sample(members, int(len(members)*0.30)):
            mesu_rows.append((nxt(''mesu''), mid, round(random.uniform(100,800),2), round(random.uniform(0,150),2), rand_date(2020,2023), EX(), RH))
        batch_insert(cur, "INSERT INTO raw.CMC_MEES_EXCHANGE (MEES_ID,MEME_ID,MEES_EXCHANGE_ID,MEES_EFF_DT,MEES_ENROLL_TYPE,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,''OE'',%s,%s)", mees_rows)
        batch_insert(cur, "INSERT INTO raw.CMC_MECD_MEDICAID (MECD_ID,MEME_ID,MECD_AID_CD,MECD_BIC,MECD_EFF_DT,MECD_STS,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,''AC'',%s,%s)", mecd_rows)
        batch_insert(cur, "INSERT INTO raw.CMC_MESU_SUBSIDY (MESU_ID,MEME_ID,MESU_SUBSIDY_AMT,MESU_PREMIUM_AMT,MESU_EFF_DT,MESU_SUBSIDY_TYPE,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,''APTC'',%s,%s)", mesu_rows)
        conn.commit(); summary.append(f"CMC_MEES({len(mees_rows)})/MECD({len(mecd_rows)})/MESU({len(mesu_rows)}): populated")

        return "INITIAL LOAD COMPLETE\\n" + "\\n".join(summary)

    except Exception as e:
        conn.rollback(); raise
    finally:
        cur.close(); conn.close()
';

-- =============================================================================
-- STEP 2: Call the procedure to seed Azure SQL Server (run once)
-- =============================================================================
-- Uncomment to seed (run once; takes several minutes at current volumes):
-- CALL FACETS_BRONZE.UTILS.FACETS_INITIAL_LOAD(
--     'tjonessqlserver.database.windows.net',
--     'openflow'
-- );
