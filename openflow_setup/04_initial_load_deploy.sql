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
--         It runs once to seed all 33 tables; no separate .py file is maintained.
-- =============================================================================

CREATE OR REPLACE PROCEDURE FACETS_INITIAL_LOAD(
    SQL_SERVER_HOST STRING,
    SQL_SERVER_DB   STRING
    -- Credentials read from FACETS_SQL_CREDS secret
)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
ARTIFACT_REPOSITORY = snowflake.snowpark.pypi_shared_repository
PACKAGES = ('snowflake-snowpark-python', 'python-tds', 'certifi')
EXTERNAL_ACCESS_INTEGRATIONS = (AZURE_SQL_FACETS_EAI)
SECRETS = ('facets_sql_creds' = FACETS_BRONZE.UTILS.FACETS_SQL_CREDS)
HANDLER = 'initial_load'
COMMENT = 'Seeds all 35 Facets demo tables in Azure SQL Server with synthetic baseline data'
AS
$$
import pytds
import certifi
import random
import hashlib
from datetime import date, timedelta, datetime


def rand_date(start_year=2018, end_year=2024):
    start = date(start_year, 1, 1)
    end = date(end_year, 12, 31)
    return start + timedelta(days=random.randint(0, (end - start).days))

def term_date_or_none(eff_dt, pct_termed=0.20):
    if random.random() < pct_termed:
        return eff_dt + timedelta(days=random.randint(365, 1095))
    return None

def row_hash(values):
    return hashlib.sha256('|'.join(str(v) for v in values).encode()).digest()

def etl_exec_id():
    return random.randint(100000, 999999)

def batch_insert(cur, sql_template, rows, batch_size=500):
    """Bulk-insert via executemany. sql_template must use %s for every column
    value (literals like 'AC' / 'ETL_INIT' may appear between placeholders)."""
    if not rows:
        return
    for i in range(0, len(rows), batch_size):
        cur.executemany(sql_template, rows[i:i + batch_size])

FIRST_NAMES = ['James','Maria','Robert','Jennifer','David','Linda','John','Patricia',
               'Michael','Elizabeth','William','Susan','Richard','Karen','Joseph','Nancy',
               'Thomas','Lisa','Carlos','Ana','Miguel','Rosa','Kevin','Angela','Brian','Mia']
LAST_NAMES  = ['Smith','Johnson','Williams','Jones','Brown','Garcia','Martinez','Davis',
               'Wilson','Anderson','Taylor','Thomas','Hernandez','Moore','Martin','Lee',
               'Perez','Thompson','White','Harris','Nguyen','Robinson','Clark','Lewis']
CITIES      = ['Orange','Anaheim','Santa Ana','Garden Grove','Irvine','Tustin',
               'Fullerton','Costa Mesa','Huntington Beach','Laguna Niguel','Mission Viejo']
TAXONOMIES  = ['207Q00000X','207R00000X','208D00000X','207QA0505X','363L00000X',
               '207W00000X','2084N0400X','193200000X','363LP2300X']
PLAN_TYPES  = ['HMO','PPO','EPO','MEDICAID','DSNP']
LANG_CODES  = ['ENG','SPA','VIE','KOR','ZHO','TGL','ARA','ARM']
DAYS_OF_WK  = ['MON','TUE','WED','THU','FRI']
AID_CODES   = ['01A','14E','2G','30','40','44','58','6N']
MSG_TYPES   = ['CRED_UPDT','ADDR_CHG','NET_ADD','NET_TERM','STATUS_CHG','NPI_ADD']
ACT_TYPES   = ['ID_ISSUE','ID_TERM','ID_REISSUE','ENRL_ADD','ENRL_TERM']


def initial_load(session, sql_server_host: str, sql_server_db: str) -> str:
    import _snowflake
    creds = _snowflake.get_username_password('facets_sql_creds')
    conn = pytds.connect(
        server=sql_server_host,
        database=sql_server_db,
        user=creds.username,
        password=creds.password,
        port=1433,
        cafile=certifi.where(),
        validate_host=False,
        timeout=30,
        autocommit=False
    )
    cur = conn.cursor()
    summary = []

    try:
        ids = {t: 1000 for t in [
            'nwnw','agag','cscs','prpr','sbsb','prad','nwpr','prer','prfa','praf',
            'prcr','prcf','prrg','prds','prcp','prnp','prhi','prla','prof','prwm',
            'meme','cspi','sbcs','sbel','medd','mecr','mepr','mecb','merp','meia',
            'mctr','mepe','mees','mecd','mesu'
        ]}

        def next_id(key):
            ids[key] += 1
            return ids[key]

        # ── 1. Networks ─────────────────────────────────────────────────────
        networks = []
        for _ in range(20):
            nid = next_id('nwnw')
            eff = rand_date(2015, 2020)
            networks.append(nid)
            cur.execute(
                "INSERT INTO raw.CMC_NWNW_NETWORK (NWNW_ID,NWNW_NAME,NWNW_ABBR,NWNW_STS,NWNW_EFF_DT,NWNW_TERM_DT,NWNW_TYPE) VALUES (%s,%s,%s,'AC',%s,NULL,%s)",
                (str(nid), f"Network {nid} - {random.choice(['HMO','PPO','MEDICAID'])}", f"NET{nid}", eff, random.choice(['HMO','PPO','MCD','DSNP'])))
        conn.commit()
        summary.append(f"CMC_NWNW_NETWORK: {len(networks)}")

        # ── 2. Agreements ───────────────────────────────────────────────────
        agreements = []
        for _ in range(50):
            aid = next_id('agag')
            eff = rand_date(2016, 2022)
            agreements.append(aid)
            cur.execute(
                "INSERT INTO raw.CMC_AGAG_AGREEMENT (AGAG_ID,AGAG_DESC,AGAG_EFF_DT,AGAG_TERM_DT,AGAG_MCTR_TYPE,AGAG_CAT) VALUES (%s,%s,%s,%s,%s,%s)",
                (aid, f"Agreement {aid}", eff, term_date_or_none(eff, 0.15), random.choice(['FFS','CAP','PER_DIEM']), random.choice(['PR','FA'])))
        conn.commit()
        summary.append(f"CMC_AGAG_AGREEMENT: {len(agreements)}")

        # ── 3. Coverage structure classes ───────────────────────────────────
        classes = []
        for _ in range(30):
            cid = next_id('cscs')
            classes.append(cid)
            cur.execute(
                "INSERT INTO raw.CMC_CSCS_CLASS (CSCS_ID,CSCS_NAME,CSCS_ABBR,CSCS_STS,CSCS_EFF_DT) VALUES (%s,%s,%s,'AC',%s)",
                (cid, f"Class {cid} - {random.choice(['Medi-Cal','DSNP','HMO','PPO'])}", f"CLS{cid}", rand_date(2018, 2022)))
        conn.commit()
        summary.append(f"CMC_CSCS_CLASS: {len(classes)}")

        # ── 4. Providers (5000: 800 org, 4200 individual) ───────────────────
        providers_type1 = []
        providers_type2 = []
        for i in range(5000):
            pid = next_id('prpr')
            entity = 'O' if i < 800 else 'I'
            eff = rand_date(2015, 2023)
            name = (f"{random.choice(LAST_NAMES)} Medical Group" if entity == 'O'
                    else f"Dr. {random.choice(LAST_NAMES)}, {random.choice(['MD','DO','NP','PA'])}")
            npi = ''.join([str(random.randint(0,9)) for _ in range(10)])
            sts = 'AC' if random.random() > 0.05 else random.choice(['IN','SU'])
            cur.execute(
                "INSERT INTO raw.CMC_PRPR_PROV (PRPR_ID,PRPR_ENTITY,PRPR_NAME,PRPR_NPI,PRPR_TAXONOMY_CD,PRPR_STS,PRPR_MCTR_TYPE,PRPR_OPTS,PRPR_LOCK_TOKEN,SYS_USUS_ID,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,%s,%s,'Y',0,'ETL_INIT',%s,%s)",
                (pid, entity, name, npi,
                 random.choice(TAXONOMIES) if entity == 'I' else '193200000X',
                 sts, random.choice(['FFS','CAP']), etl_exec_id(), row_hash([pid, entity, npi])))
            (providers_type2 if entity == 'O' else providers_type1).append(pid)
        conn.commit()
        summary.append(f"CMC_PRPR_PROV: {len(providers_type1)+len(providers_type2)} (T1:{len(providers_type1)}, T2:{len(providers_type2)})")

        all_providers = providers_type1 + providers_type2

        # ── 5. Subscribers (50000) ───────────────────────────────────────────
        subscribers = []
        sub_rows = []
        for _ in range(50000):
            sid = next_id('sbsb')
            subscribers.append(sid)
            dob = date.today() - timedelta(days=random.randint(365*18, 365*80))
            sub_rows.append((sid, random.choice(LAST_NAMES), random.choice(FIRST_NAMES), dob,
                             random.choice(['M','F','U']), random.choice(['MEDCAID','COMM','DSNP']),
                             etl_exec_id(), row_hash([sid])))
        batch_insert(cur,
            "INSERT INTO raw.CMC_SBSB_SUBSC (SBSB_ID,SBSB_LAST_NAME,SBSB_FIRST_NAME,SBSB_DOB,SBSB_SEX,SBSB_STS,SBSB_MCTR_TYPE,SYS_USUS_ID,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,'AC',%s,'ETL_INIT',%s,%s)",
            sub_rows)
        conn.commit()
        summary.append(f"CMC_SBSB_SUBSC: {len(subscribers)}")

        # ── 6. Provider addresses (1 per provider) ─────────────────────────
        for pid in all_providers:
            prid = next_id('prad')
            cur.execute(
                "INSERT INTO raw.CMC_PRAD_ADDRESS (PRAD_ID,PRPR_ID,PRAD_ADDR1,PRAD_CITY,PRAD_ST,PRAD_ZIP,PRAD_TYPE) VALUES (%s,%s,%s,%s,'CA',%s,'PR')",
                (prid, pid, f"{random.randint(100,9999)} {random.choice(['Main','Oak','Harbor'])} St",
                 random.choice(CITIES), f"926{random.randint(10,99)}"))
        conn.commit()
        summary.append(f"CMC_PRAD_ADDRESS: {len(all_providers)}")

        # ── 7. Network participation (1-3 networks per provider) ───────────
        nwpr_count = 0
        for pid in all_providers:
            for _ in range(random.randint(1, 3)):
                nrid = next_id('nwpr')
                eff = rand_date(2018, 2023)
                cur.execute(
                    "INSERT INTO raw.CMC_NWPR_RELATION (NWPR_ID,NWNW_ID,PRPR_ID,AGAG_ID,NWPR_EFF_DT,NWPR_TERM_DT,NWPR_PCP_IND,NWPR_DIRECTORY_IND,NWPR_ACC_PAT_IND,NWPR_ACC_MEDCD_IND,NWPR_PAT_CTR,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,%s,%s,'Y','Y','Y',%s,%s,%s)",
                    (nrid, random.choice(networks), pid, random.choice(agreements), eff,
                     term_date_or_none(eff, 0.10), 'Y' if random.random() > 0.7 else 'N',
                     random.randint(0, 1200), etl_exec_id(), row_hash([nrid, pid])))
                nwpr_count += 1
        conn.commit()
        summary.append(f"CMC_NWPR_RELATION: {nwpr_count}")

        # ── 8. Provider-to-org links ────────────────────────────────────────
        prer_count = 0
        for pid in random.sample(providers_type1, min(800, len(providers_type1))):
            prid = next_id('prer')
            eff = rand_date(2018, 2023)
            cur.execute(
                "INSERT INTO raw.CMC_PRER_RELATION (PRER_ID,PRPR_ID,PRER_PRPR_ID,PRER_EFF_DT,PRER_TERM_DT,PRER_PRPR_ENTITY,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,'O',%s,%s)",
                (prid, pid, random.choice(providers_type2), eff, term_date_or_none(eff, 0.15),
                 etl_exec_id(), row_hash([prid, pid])))
            prer_count += 1
        conn.commit()
        summary.append(f"CMC_PRER_RELATION: {prer_count}")

        # ── 8b. Facility attributes (Type 2 orgs) ──────────────────────────
        prfa_count = 0
        for pid in random.sample(providers_type2, min(300, len(providers_type2))):
            cur.execute(
                "INSERT INTO raw.CMC_PRFA_FACILITY (PRFA_ID,PRPR_ID,PRFA_FAC_TYPE,PRFA_BED_CNT,PRFA_LICENSE_NO,PRFA_ACCRED_TYPE) VALUES (%s,%s,%s,%s,%s,%s)",
                (next_id('prfa'), pid, random.choice(['HOSP','CLIN','ASC','SNF']),
                 random.randint(20, 500), f"LIC{random.randint(100000,999999)}",
                 random.choice(['JCAHO','NCQA','AAAHC','CARF'])))
            prfa_count += 1
        conn.commit()
        summary.append(f"CMC_PRFA_FACILITY: {prfa_count}")

        # ── 8c. Provider-to-facility affiliations ──────────────────────────
        praf_count = 0
        for pid in random.sample(providers_type1, min(500, len(providers_type1))):
            eff = rand_date(2018, 2023)
            cur.execute(
                "INSERT INTO raw.CMC_PRAF_FAC_AFFIL (PRAF_ID,PRPR_ID,PRAF_FAC_PRPR_ID,PRAF_EFF_DT,PRAF_TERM_DT,PRAF_AFFIL_TYPE) VALUES (%s,%s,%s,%s,%s,%s)",
                (next_id('praf'), pid, random.choice(providers_type2), eff,
                 term_date_or_none(eff, 0.10), random.choice(['AD','PR','ST'])))
            praf_count += 1
        conn.commit()
        summary.append(f"CMC_PRAF_FAC_AFFIL: {praf_count}")

        # ── 9. Provider detail tables ───────────────────────────────────────
        for pid in random.sample(providers_type1, min(600, len(providers_type1))):
            cur.execute("INSERT INTO raw.CMC_PRCR_CREDEN (PRCR_ID,PRPR_ID,PRCR_TYPE,PRCR_STATUS,PRCR_EFF_DT) VALUES (%s,%s,%s,'AC',%s)",
                (next_id('prcr'), pid, random.choice(['CRED','RECRED']), rand_date(2018,2023)))
        conn.commit()

        for pid in random.sample(providers_type1, min(400, len(providers_type1))):
            cur.execute("INSERT INTO raw.CMC_PRCF_CERT (PRCF_ID,PRPR_ID,PRCF_BOARD_TYPE,PRCF_CERT_NO,PRCF_EFF_DT) VALUES (%s,%s,%s,%s,%s)",
                (next_id('prcf'), pid, random.choice(['ABIM','ABFM','ABPEDS']), f"CERT{random.randint(10000,99999)}", rand_date(2015,2022)))
        conn.commit()

        for pid in random.sample(all_providers, min(1500, len(all_providers))):
            cur.execute("INSERT INTO raw.CMC_PRRG_REG (PRRG_ID,PRPR_ID,PRRG_STATE,PRRG_LIC_NO,PRRG_TYPE,PRRG_EFF_DT) VALUES (%s,%s,'CA',%s,'MD_LIC',%s)",
                (next_id('prrg'), pid, f"CA{random.randint(100000,999999)}", rand_date(2015,2022)))
        conn.commit()

        for pid in random.sample(all_providers, min(1000, len(all_providers))):
            for dt in ['EFF','CRED']:
                cur.execute("INSERT INTO raw.CMC_PRDS_DATE (PRDS_ID,PRPR_ID,PRDS_TYPE,PRDS_EFF_DT) VALUES (%s,%s,%s,%s)",
                    (next_id('prds'), pid, dt, rand_date(2018,2023)))
        conn.commit()

        for pid in random.sample(providers_type1, min(700, len(providers_type1))):
            cur.execute("INSERT INTO raw.CMC_PRCP_COMM_PRAC (PRCP_ID,PRPR_ID,PRCP_GRP_NAME,PRCP_SOLO_IND) VALUES (%s,%s,%s,%s)",
                (next_id('prcp'), pid, f"{random.choice(LAST_NAMES)} Associates", 'Y' if random.random() < 0.3 else 'N'))
        conn.commit()

        for pid in random.sample(all_providers, min(500, len(all_providers))):
            cur.execute("INSERT INTO raw.CMC_PRNP_NPI (PRNP_ID,PRPR_ID,PRNP_NPI,PRNP_NPI_TYPE,PRNP_EFF_DT) VALUES (%s,%s,%s,%s,%s)",
                (next_id('prnp'), pid, ''.join([str(random.randint(0,9)) for _ in range(10)]),
                 '1' if pid in providers_type1 else '2', rand_date(2018,2022)))
        conn.commit()

        for pid in random.sample(all_providers, min(800, len(all_providers))):
            for lang in random.sample(LANG_CODES, random.randint(1,3)):
                cur.execute("INSERT INTO raw.CMC_PRLA_LANG (PRLA_ID,PRPR_ID,PRLA_LANG_CD,PRLA_FLUENT_IND) VALUES (%s,%s,%s,'Y')",
                    (next_id('prla'), pid, lang))
        conn.commit()

        for pid in random.sample(all_providers, min(1000, len(all_providers))):
            for day in random.sample(DAYS_OF_WK, random.randint(3,5)):
                cur.execute("INSERT INTO raw.CMC_PROF_OFF_HRS (PROF_ID,PRPR_ID,PROF_DAY_OF_WK,PROF_OPEN_TM,PROF_CLOSE_TM) VALUES (%s,%s,%s,'08:00:00','17:00:00')",
                    (next_id('prof'), pid, day))
        conn.commit()
        summary.append(f"CMC_PRCR/PRCF/PRRG/PRDS/PRCP/PRNP/PRLA/PROF: populated")

        prhi_count = 0
        for pid in random.sample(all_providers, min(400, len(all_providers))):
            for _ in range(random.randint(1, 3)):
                old_val, new_val = random.choice(['AC','IN']), random.choice(['IN','AC','SU'])
                cur.execute(
                    "INSERT INTO raw.CMC_PRHI_HIST (PRHI_ID,PRPR_ID,PRHI_FIELD_NM,PRHI_OLD_VAL,PRHI_NEW_VAL,PRHI_USUS_ID) VALUES (%s,%s,%s,%s,%s,'ETL_INIT')",
                    (next_id('prhi'), pid, random.choice(['PRPR_STS','PRPR_NAME','PRPR_NPI']), old_val, new_val))
                prhi_count += 1
        conn.commit()
        summary.append(f"CMC_PRHI_HIST: {prhi_count}")

        prwm_count = 0
        for pid in random.sample(all_providers, min(500, len(all_providers))):
            for _ in range(random.randint(1,5)):
                cur.execute("INSERT INTO raw.CMC_PRWM_PR_MSG (PRWM_ID,PRPR_ID,PRWM_MSG_TYPE,PRWM_MSG_TEXT,PRWM_USUS_ID) VALUES (%s,%s,%s,%s,'ETL_INIT')",
                    (next_id('prwm'), pid, random.choice(MSG_TYPES), f"Initial audit for PRPR {pid}"))
                prwm_count += 1
        conn.commit()
        summary.append(f"CMC_PRWM_PR_MSG: {prwm_count}")

        # ── 10. Members (~80K across 50K subscribers) ─────────────────────
        members = []
        meme_rows = []
        for sid in subscribers:
            num_members = 1 if random.random() > 0.4 else random.randint(2,4)
            for rel_idx in range(num_members):
                mid = next_id('meme')
                rel = '01' if rel_idx == 0 else random.choice(['02','03','04'])
                dob = date.today() - timedelta(days=random.randint(365*1, 365*75))
                members.append(mid)
                meme_rows.append((mid, sid, rel, random.choice(LAST_NAMES), random.choice(FIRST_NAMES),
                                  dob, random.choice(['M','F','U']), random.choice(['MEDCAID','COMM','DSNP']),
                                  etl_exec_id(), row_hash([mid, sid])))
        batch_insert(cur,
            "INSERT INTO raw.CMC_MEME_MEMBER (MEME_ID,SBSB_ID,MEME_REL_CD,MEME_LAST_NAME,MEME_FIRST_NAME,MEME_DOB,MEME_SEX,MEME_STS,MEME_MCTR_TYPE,SYS_USUS_ID,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,%s,%s,'AC',%s,'ETL_INIT',%s,%s)",
            meme_rows)
        conn.commit()
        summary.append(f"CMC_MEME_MEMBER: {len(members)}")

        # ── 11. Plan instances (80) ─────────────────────────────────────────
        plans = []
        for _ in range(80):
            cid = next_id('cspi')
            plans.append(cid)
            cur.execute(
                "INSERT INTO raw.CMC_CSPI_CS_PLAN (CSPI_ID,CSCS_ID,CSPI_NAME,CSPI_PLAN_TYPE,CSPI_EFF_DT,CSPI_STS) VALUES (%s,%s,%s,%s,%s,'AC')",
                (cid, random.choice(classes), f"Plan {cid} - {random.choice(PLAN_TYPES)} {random.randint(2020,2025)}", random.choice(PLAN_TYPES), rand_date(2018,2022)))
        conn.commit()
        summary.append(f"CMC_CSPI_CS_PLAN: {len(plans)}")

        # ── 12. Subscriber child tables ─────────────────────────────────────
        for sid in subscribers:
            eff = rand_date(2019, 2023)
            cur.execute("INSERT INTO raw.CMC_SBCS_CLASS (SBCS_ID,SBSB_ID,CSCS_ID,SBCS_EFF_DT) VALUES (%s,%s,%s,%s)",
                (next_id('sbcs'), sid, random.choice(classes), eff))
            cur.execute("INSERT INTO raw.CMC_SBEL_ELIG_ENT (SBEL_ID,SBSB_ID,SBEL_EFF_DT,SBEL_ELIG_STS,SBEL_PLAN_TYPE,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,'AC',%s,%s,%s)",
                (next_id('sbel'), sid, eff, random.choice(PLAN_TYPES), etl_exec_id(), row_hash([sid, eff])))
        conn.commit()
        summary.append(f"CMC_SBCS_CLASS/SBEL_ELIG_ENT: {len(subscribers)} each")

        # ── 13. Member child tables ─────────────────────────────────────────
        for mid in random.sample(members, int(len(members)*0.6)):
            cur.execute("INSERT INTO raw.CMC_MEDD_DEM_DATA (MEDD_ID,MEME_ID,MEDD_ETHNICITY_CD,MEDD_RACE_CD,MEDD_LANG_CD) VALUES (%s,%s,%s,%s,%s)",
                (next_id('medd'), mid, random.choice(['NON_HISP','HISP','UNK']), random.choice(['WHITE','BLACK','ASIAN','OTHER','UNK']), random.choice(LANG_CODES)))
        conn.commit()

        for mid in members:
            cur.execute("INSERT INTO raw.CMC_MECR_NO_XREF (MECR_ID,MEME_ID,MECR_NO,MECR_TYPE,MECR_EFF_DT) VALUES (%s,%s,%s,'MEDI_CAL',%s)",
                (next_id('mecr'), mid, f"MC{random.randint(10000000,99999999)}", rand_date(2019,2023)))
        conn.commit()

        pcp_pool = random.sample(providers_type1, max(1, len(providers_type1)//2))
        mepr_count = 0
        for mid in random.sample(members, int(len(members)*0.80)):
            eff = rand_date(2020, 2023)
            cur.execute("INSERT INTO raw.CMC_MEPR_PRIM_PROV (MEPR_ID,MEME_ID,PRPR_ID,MEPR_EFF_DT,MEPR_PCP_TYPE,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,'PCP',%s,%s)",
                (next_id('mepr'), mid, random.choice(pcp_pool), eff, etl_exec_id(), row_hash([mid, eff])))
            mepr_count += 1
        conn.commit()

        for mid in random.sample(members, int(len(members)*0.10)):
            cur.execute("INSERT INTO raw.CMC_MECB_COB (MECB_ID,MEME_ID,MECB_CARRIER_NM,MECB_POLICY_NO,MECB_EFF_DT,MECB_COB_ORDER) VALUES (%s,%s,%s,%s,%s,'2')",
                (next_id('mecb'), mid, random.choice(['Blue Shield','Aetna','Cigna','UHC']), f"POL{random.randint(100000,999999)}", rand_date(2020,2023)))
        conn.commit()

        for mid in random.sample(members, int(len(members)*0.40)):
            cur.execute("INSERT INTO raw.CMC_MERP_RELATION (MERP_ID,MEME_ID,MERP_REL_CD,MERP_EFF_DT) VALUES (%s,%s,%s,%s)",
                (next_id('merp'), mid, random.choice(['02','03','04']), rand_date(2020,2023)))
        conn.commit()

        meia_count = 0
        for mid in random.sample(members, int(len(members)*0.90)):
            cur.execute("INSERT INTO raw.CMC_MEIA_ID_ACT (MEIA_ID,MEME_ID,MEIA_ACT_TYPE,MEIA_USUS_ID,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,'ID_ISSUE','ETL_INIT',%s,%s)",
                (next_id('meia'), mid, etl_exec_id(), row_hash([mid])))
            meia_count += 1
        conn.commit()
        summary.append(f"CMC_MEDD/MECR/MEPR({mepr_count})/MECB/MERP/MEIA({meia_count}): populated")

        for _ in range(200):
            cid2 = next_id('mctr')
            cur.execute("INSERT INTO raw.CMC_MCTR_CD_TRANS (MCTR_ID,MCTR_TYPE,MCTR_VALUE,MCTR_DESC,MCTR_ENTITY,MCTR_SORT,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,'MEMBER',%s,%s,%s)",
                (cid2, random.choice(['PLAN','LOB','GRP','AID']), f"CD{random.randint(100,999)}", f"Code {cid2}", cid2%100, etl_exec_id(), row_hash([cid2])))
        conn.commit()
        summary.append(f"CMC_MCTR_CD_TRANS: 200")

        # ── 14. Eligibility — built from meme_rows (no table scan needed) ────
        mem_to_sub = {r[0]: r[1] for r in meme_rows}

        mepe_rows = []
        for mid in members:
            sid = mem_to_sub.get(mid, random.choice(subscribers))
            eff = rand_date(2020, 2023)
            pid = next_id('mepe')
            mepe_rows.append((pid, mid, sid, random.choice(plans), eff,
                              term_date_or_none(eff, 0.15), random.choice(PLAN_TYPES),
                              etl_exec_id(), row_hash([mid, eff])))
            if random.random() < 0.20:
                eff2 = eff + timedelta(days=random.randint(180,730))
                pid2 = next_id('mepe')
                mepe_rows.append((pid2, mid, sid, random.choice(plans), eff2,
                                  None, random.choice(PLAN_TYPES),
                                  etl_exec_id(), row_hash([mid, eff2])))
        batch_insert(cur,
            "INSERT INTO raw.CMC_MEPE_PRCS_ELIG (MEPE_ID,MEME_ID,SBSB_ID,CSPI_ID,MEPE_EFF_DT,MEPE_TERM_DT,MEPE_STS,MEPE_ELIG_TYPE,MEPE_PLAN_TYPE,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,%s,'AC','MEDICAID',%s,%s,%s)",
            mepe_rows)
        conn.commit()
        summary.append(f"CMC_MEPE_PRCS_ELIG: {len(mepe_rows)}")

        mees_count = 0
        for mid in random.sample(members, int(len(members)*0.15)):
            eff = rand_date(2021, 2023)
            cur.execute("INSERT INTO raw.CMC_MEES_EXCHANGE (MEES_ID,MEME_ID,MEES_EXCHANGE_ID,MEES_EFF_DT,MEES_ENROLL_TYPE,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,'OE',%s,%s)",
                (next_id('mees'), mid, f"EX{random.randint(10000000,99999999)}", eff, etl_exec_id(), row_hash([mid, eff])))
            mees_count += 1
        conn.commit()

        mecd_count = 0
        for mid in random.sample(members, int(len(members)*0.85)):
            eff = rand_date(2019, 2023)
            cur.execute("INSERT INTO raw.CMC_MECD_MEDICAID (MECD_ID,MEME_ID,MECD_AID_CD,MECD_BIC,MECD_EFF_DT,MECD_STS,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,'AC',%s,%s)",
                (next_id('mecd'), mid, random.choice(AID_CODES), f"BIC{random.randint(1000000,9999999)}", eff, etl_exec_id(), row_hash([mid, eff])))
            mecd_count += 1
        conn.commit()

        mesu_count = 0
        for mid in random.sample(members, int(len(members)*0.30)):
            eff = rand_date(2020, 2023)
            cur.execute("INSERT INTO raw.CMC_MESU_SUBSIDY (MESU_ID,MEME_ID,MESU_SUBSIDY_AMT,MESU_PREMIUM_AMT,MESU_EFF_DT,MESU_SUBSIDY_TYPE,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,'APTC',%s,%s)",
                (next_id('mesu'), mid, round(random.uniform(100,800),2), round(random.uniform(0,150),2), eff, etl_exec_id(), row_hash([mid, eff])))
            mesu_count += 1
        conn.commit()
        summary.append(f"CMC_MEES({mees_count})/MECD({mecd_count})/MESU({mesu_count}): populated")

        # ── 15. DUPLICATION INJECTION ───────────────────────────────────────
        # Intentional business-key duplicates (~1.5-3% rates) to support
        # Bronze-to-Silver deduplication demo in dbt.
        # These are NOT PK duplicates — each row gets a unique PK so Openflow
        # replication is unaffected. The duplicate is on the business grain.

        # 15a. Provider NPI duplicates (~2% of Type 1 providers)
        #      Same NPI, same entity, different PRPR_ID, slightly different name.
        #      Represents re-credentialing or a data entry name-format variation.
        dup_prpr = random.sample(providers_type1, max(1, int(len(providers_type1) * 0.02)))
        prpr_dup_count = 0
        for orig_pid in dup_prpr:
            cur.execute("SELECT PRPR_NPI, PRPR_ENTITY, PRPR_NAME, PRPR_TAXONOMY_CD, PRPR_STS, PRPR_MCTR_TYPE FROM raw.CMC_PRPR_PROV WHERE PRPR_ID=%s", (orig_pid,))
            row = cur.fetchone()
            if row:
                npi, entity, name, tax, sts, mctr = row
                dup_pid = next_id('prpr')
                # Name variation: swap to "FIRSTNAME LASTNAME" format if currently "LASTNAME, FIRSTNAME"
                dup_name = name.replace(', MD','').replace(', DO','').replace(', NP','').replace(', PA','') + ' MD' if ',' in str(name) else str(name) + ', MD'
                cur.execute(
                    "INSERT INTO raw.CMC_PRPR_PROV (PRPR_ID,PRPR_ENTITY,PRPR_NAME,PRPR_NPI,PRPR_TAXONOMY_CD,PRPR_STS,PRPR_MCTR_TYPE,PRPR_OPTS,PRPR_LOCK_TOKEN,SYS_USUS_ID,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,%s,%s,'Y',0,'ETL_INIT_DUP',%s,%s)",
                    (dup_pid, entity, dup_name, npi, tax, sts, mctr, etl_exec_id(), row_hash([dup_pid, npi, 'DUP'])))
                prpr_dup_count += 1
        conn.commit()
        summary.append(f"CMC_PRPR_PROV duplicates (same NPI, diff PRPR_ID): {prpr_dup_count}")

        # 15b. Member near-duplicates (~1.5% of members)
        #      Same SBSB_ID + same DOB + same sex + same last name, new MEME_ID.
        #      Represents a Medi-Cal re-enrollment where a new MEME_ID was issued
        #      instead of reactivating the existing record.
        dup_meme = random.sample(members, max(1, int(len(members) * 0.015)))
        meme_dup_count = 0
        for orig_mid in dup_meme:
            cur.execute("SELECT SBSB_ID, MEME_LAST_NAME, MEME_FIRST_NAME, MEME_DOB, MEME_SEX, MEME_MCTR_TYPE FROM raw.CMC_MEME_MEMBER WHERE MEME_ID=%s", (orig_mid,))
            row = cur.fetchone()
            if row:
                sid, lname, fname, dob, sex, mctr = row
                dup_mid = next_id('meme')
                cur.execute(
                    "INSERT INTO raw.CMC_MEME_MEMBER (MEME_ID,SBSB_ID,MEME_REL_CD,MEME_LAST_NAME,MEME_FIRST_NAME,MEME_DOB,MEME_SEX,MEME_STS,MEME_MCTR_TYPE,SYS_USUS_ID,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,'01',%s,%s,%s,%s,'AC',%s,'ETL_INIT_DUP',%s,%s)",
                    (dup_mid, sid, lname, fname, dob, sex, mctr, etl_exec_id(), row_hash([dup_mid, sid, 'DUP'])))
                meme_dup_count += 1
        conn.commit()
        summary.append(f"CMC_MEME_MEMBER near-duplicates (same demographics, diff MEME_ID): {meme_dup_count}")

        # 15c. Overlapping MEPE eligibility spans (~3% of active spans)
        #      A second eligibility span is inserted whose EFF_DT falls within an
        #      existing span. Represents a retro-eligibility correction.
        cur2b = conn.cursor()
        cur2b.execute("SELECT MEME_ID, SBSB_ID, CSPI_ID, MEPE_EFF_DT, MEPE_PLAN_TYPE FROM raw.CMC_MEPE_PRCS_ELIG WHERE MEPE_TERM_DT IS NULL")
        active_spans = cur2b.fetchall()
        overlap_sample = random.sample(active_spans, max(1, int(len(active_spans) * 0.03)))
        mepe_dup_count = 0
        for span in overlap_sample:
            orig_mid, orig_sid, orig_cspi, orig_eff, orig_plan = span
            # New span starts mid-way through the existing active span (overlap)
            overlap_eff = orig_eff + timedelta(days=random.randint(30, 180))
            if overlap_eff <= date.today():
                dup_mepe_id = next_id('mepe')
                cur.execute(
                    "INSERT INTO raw.CMC_MEPE_PRCS_ELIG (MEPE_ID,MEME_ID,SBSB_ID,CSPI_ID,MEPE_EFF_DT,MEPE_TERM_DT,MEPE_STS,MEPE_ELIG_TYPE,MEPE_PLAN_TYPE,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,NULL,'AC','MEDICAID',%s,%s,%s)",
                    (dup_mepe_id, orig_mid, orig_sid, orig_cspi, overlap_eff, orig_plan, etl_exec_id(), row_hash([dup_mepe_id, orig_mid, 'OVERLAP'])))
                mepe_dup_count += 1
        conn.commit()
        summary.append(f"CMC_MEPE_PRCS_ELIG overlapping spans: {mepe_dup_count}")

        # 15d. Multiple active PCP assignments (~2% of members with a PCP)
        #      A second active PCP record (MEPR_TERM_DT IS NULL) for the same member.
        #      Represents a PCP change where the old assignment was never closed.
        cur2c = conn.cursor()
        cur2c.execute("SELECT TOP 500 MEME_ID FROM raw.CMC_MEPR_PRIM_PROV WHERE MEPR_TERM_DT IS NULL ORDER BY NEWID()")
        active_pcp = [row[0] for row in cur2c.fetchall()]
        pcp_dup_sample = random.sample(active_pcp, max(1, int(len(active_pcp) * 0.02)))
        pcp_dup_count = 0
        for mid in pcp_dup_sample:
            dup_mepr_id = next_id('mepr')
            new_pcp = random.choice(providers_type1)
            eff = rand_date(2023, 2024)
            cur.execute(
                "INSERT INTO raw.CMC_MEPR_PRIM_PROV (MEPR_ID,MEME_ID,PRPR_ID,MEPR_EFF_DT,MEPR_TERM_DT,MEPR_PCP_TYPE,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,NULL,'PCP',%s,%s)",
                (dup_mepr_id, mid, new_pcp, eff, etl_exec_id(), row_hash([dup_mepr_id, mid, 'DUP_PCP'])))
            pcp_dup_count += 1
        conn.commit()
        summary.append(f"CMC_MEPR_PRIM_PROV multiple active PCP: {pcp_dup_count}")

        return "INITIAL LOAD COMPLETE\n" + "\n".join(summary)

    except Exception as e:
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()
$$;

-- =============================================================================
-- STEP 3: Call the procedure to seed Azure SQL Server (run once)
-- =============================================================================
-- Uncomment to seed (run once; takes several minutes at current volumes):
-- CALL FACETS_BRONZE.UTILS.FACETS_INITIAL_LOAD(
--     'tjonessqlserver.database.windows.net',
--     'openflow'
-- );
