-- =============================================================================
-- FILE: 05_incremental_load_deploy.sql
-- PURPOSE: Create the FACETS_INCREMENTAL_LOAD stored procedure and schedule it
--          on a Snowflake Task to drive ongoing synthetic CDC activity.
--
-- PRE-REQUISITE: Run 04_initial_load_deploy.sql first.
--   The External Access Integration (AZURE_SQL_FACETS_EAI) must already exist.
--
-- RUN ORDER:
--   1. 01_sql_server_ddl.sql          — create tables in Azure SQL Server
--   2. 02_sql_server_permissions.sql  — change tracking + openflow_user grants
--   3. 03_snowflake_secrets_setup.sql — FACETS_BRONZE database, UTILS schema, secret
--   4. 04_initial_load_deploy.sql     — EAI + initial load proc + call once to seed
--   5. THIS FILE                      — incremental proc + task (hourly until Jul 7, then 12 min)
-- =============================================================================

USE DATABASE FACETS_BRONZE;
USE SCHEMA   UTILS;

-- =============================================================================
-- STEP 1: Incremental Load Stored Procedure
-- =============================================================================

CREATE OR REPLACE PROCEDURE FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_LOAD("SQL_SERVER_HOST" VARCHAR, "SQL_SERVER_DB" VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
ARTIFACT_REPOSITORY = snowflake.snowpark.pypi_shared_repository
PACKAGES = ('snowflake-snowpark-python','python-tds','certifi')
HANDLER = 'incremental_load'
EXTERNAL_ACCESS_INTEGRATIONS = (AZURE_SQL_FACETS_EAI)
SECRETS = ('facets_sql_creds'=FACETS_BRONZE.UTILS.FACETS_SQL_CREDS)
COMMENT='Tier-weighted inserts/updates/deletes across all 35 Facets tables'
EXECUTE AS OWNER
AS
$$
import pytds
import certifi
import random
from datetime import date, timedelta, datetime


def rand_date(start_year=2023, end_year=2026):
    start = date(start_year, 1, 1)
    end = min(date(end_year, 12, 31), date.today())
    return start + timedelta(days=random.randint(0, max(1, (end - start).days)))

def etl_exec_id():
    return random.randint(1000000, 9999999)

def get_max_id(cur, table, pk_col):
    cur.execute(f"SELECT ISNULL(MAX({pk_col}), 10000) FROM {table}")
    return cur.fetchone()[0]

def get_random_ids(cur, table, pk_col, n=20):
    cur.execute(f"SELECT TOP {n} {pk_col} FROM {table} ORDER BY NEWID()")
    return [row[0] for row in cur.fetchall()]

def get_random_ids_where(cur, table, pk_col, where, n=20):
    cur.execute(f"SELECT TOP {n} {pk_col} FROM {table} WHERE {where} ORDER BY NEWID()")
    return [row[0] for row in cur.fetchall()]

def get_random_member_subscriber_pairs(cur, n=200):
    cur.execute(f"SELECT TOP {n} MEME_ID, SBSB_ID FROM raw.CMC_MEME_MEMBER ORDER BY NEWID()")
    return [(row[0], row[1]) for row in cur.fetchall()]

FIRST_NAMES = ['James','Maria','Robert','Jennifer','David','Linda','John','Patricia','Michael','Elizabeth']
LAST_NAMES  = ['Smith','Johnson','Williams','Jones','Brown','Garcia','Martinez','Davis','Wilson','Anderson']
CITIES      = ['Orange','Anaheim','Santa Ana','Garden Grove','Irvine','Tustin','Fullerton']
PLAN_TYPES  = ['HMO','PPO','EPO','MEDICAID','DSNP']
AID_CODES   = ['01A','14E','2G','30','40','44','58','6N']
MSG_TYPES   = ['CRED_UPDT','ADDR_CHG','NET_ADD','NET_TERM','STATUS_CHG']
ACT_TYPES   = ['ID_ISSUE','ID_TERM','ID_REISSUE','ENRL_ADD','ENRL_TERM']
TAXONOMIES  = ['207Q00000X','207R00000X','208D00000X','207QA0505X','363L00000X']


def incremental_load(session, sql_server_host: str, sql_server_db: str) -> str:
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
    log = []
    run_ts = datetime.utcnow().isoformat()
    exec_id = etl_exec_id()
    RH = None  # ROW_HASH_VALUE — NULL; pytds bytes issue; ETL tracking only

    try:
        # Get current max IDs from each table (schema-qualified)
        max_ids = {
            'mepe': get_max_id(cur,'raw.CMC_MEPE_PRCS_ELIG','MEPE_ID'),
            'meme': get_max_id(cur,'raw.CMC_MEME_MEMBER','MEME_ID'),
            'sbsb': get_max_id(cur,'raw.CMC_SBSB_SUBSC','SBSB_ID'),
            'sbel': get_max_id(cur,'raw.CMC_SBEL_ELIG_ENT','SBEL_ID'),
            'meia': get_max_id(cur,'raw.CMC_MEIA_ID_ACT','MEIA_ID'),
            'mctr': get_max_id(cur,'raw.CMC_MCTR_CD_TRANS','MCTR_ID'),
            'mesu': get_max_id(cur,'raw.CMC_MESU_SUBSIDY','MESU_ID'),
            'prpr': get_max_id(cur,'raw.CMC_PRPR_PROV','PRPR_ID'),
            'prad': get_max_id(cur,'raw.CMC_PRAD_ADDRESS','PRAD_ID'),
            'nwpr': get_max_id(cur,'raw.CMC_NWPR_RELATION','NWPR_ID'),
            'mepr': get_max_id(cur,'raw.CMC_MEPR_PRIM_PROV','MEPR_ID'),
            'mecb': get_max_id(cur,'raw.CMC_MECB_COB','MECB_ID'),
            'mecr': get_max_id(cur,'raw.CMC_MECR_NO_XREF','MECR_ID'),
            'mees': get_max_id(cur,'raw.CMC_MEES_EXCHANGE','MEES_ID'),
            'mecd': get_max_id(cur,'raw.CMC_MECD_MEDICAID','MECD_ID'),
            'prwm': get_max_id(cur,'raw.CMC_PRWM_PR_MSG','PRWM_ID'),
            'prcr': get_max_id(cur,'raw.CMC_PRCR_CREDEN','PRCR_ID'),
            'prcf': get_max_id(cur,'raw.CMC_PRCF_CERT','PRCF_ID'),
            'prnp': get_max_id(cur,'raw.CMC_PRNP_NPI','PRNP_ID'),
            'agag': get_max_id(cur,'raw.CMC_AGAG_AGREEMENT','AGAG_ID'),
        }

        def nxt(key):
            max_ids[key] += 1
            return max_ids[key]

        prpr_ids = get_random_ids(cur,'raw.CMC_PRPR_PROV','PRPR_ID',50)
        sbsb_ids = get_random_ids(cur,'raw.CMC_SBSB_SUBSC','SBSB_ID',100)
        meme_ids = get_random_ids(cur,'raw.CMC_MEME_MEMBER','MEME_ID',200)
        nwnw_ids = get_random_ids(cur,'raw.CMC_NWNW_NETWORK','NWNW_ID',10)
        agag_ids = get_random_ids(cur,'raw.CMC_AGAG_AGREEMENT','AGAG_ID',10)
        cspi_ids = get_random_ids(cur,'raw.CMC_CSPI_CS_PLAN','CSPI_ID',20)
        prpr_t1  = get_random_ids_where(cur,'raw.CMC_PRPR_PROV','PRPR_ID',"PRPR_ENTITY='I'",50)
        prpr_t2  = get_random_ids_where(cur,'raw.CMC_PRPR_PROV','PRPR_ID',"PRPR_ENTITY='O'",20)
        meme_sub_pairs = get_random_member_subscriber_pairs(cur, 200)
        if not meme_sub_pairs:
            return "INCREMENTAL LOAD SKIPPED: CMC_MEME_MEMBER is empty — run FACETS_INITIAL_LOAD first"

        # ── TIER 1: runs every window ──────────────────────────────────────────
        n = random.randint(200,400)
        for _ in range(n):
            mid, sid = random.choice(meme_sub_pairs)
            pid = nxt('mepe'); eff = rand_date()
            cur.execute("INSERT INTO raw.CMC_MEPE_PRCS_ELIG (MEPE_ID,MEME_ID,SBSB_ID,CSPI_ID,MEPE_EFF_DT,MEPE_TERM_DT,MEPE_STS,MEPE_ELIG_TYPE,MEPE_PLAN_TYPE,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,NULL,'AC','MEDICAID',%s,%s,%s)",
                (pid,mid,sid,random.choice(cspi_ids),eff,random.choice(PLAN_TYPES),exec_id,RH))
        for mid in get_random_ids(cur,'raw.CMC_MEPE_PRCS_ELIG','MEPE_ID',random.randint(50,100)):
            cur.execute("UPDATE raw.CMC_MEPE_PRCS_ELIG SET MEPE_STS=%s,SYS_LAST_UPD_DTM=GETDATE(),ETL_PROCESS_EXECUTION_ID=%s WHERE MEPE_ID=%s",
                (random.choice(['AC','IN']),exec_id,mid))
        conn.commit()
        log.append(f"MEPE +{n} ins, upd")

        n = random.randint(50,150)
        for _ in range(n):
            mid = nxt('meme'); sid = random.choice(sbsb_ids)
            dob = date.today()-timedelta(days=random.randint(365,365*60))
            cur.execute("INSERT INTO raw.CMC_MEME_MEMBER (MEME_ID,SBSB_ID,MEME_REL_CD,MEME_LAST_NAME,MEME_FIRST_NAME,MEME_DOB,MEME_SEX,MEME_STS,MEME_MCTR_TYPE,SYS_USUS_ID,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,%s,%s,'AC',%s,'ETL_INCR',%s,%s)",
                (mid,sid,random.choice(['01','02','03']),random.choice(LAST_NAMES),random.choice(FIRST_NAMES),dob,random.choice(['M','F','U']),random.choice(['MEDCAID','COMM','DSNP']),exec_id,RH))
            meme_ids.append(mid)
            meme_sub_pairs.append((mid, sid))
        for mid in get_random_ids(cur,'raw.CMC_MEME_MEMBER','MEME_ID',random.randint(30,80)):
            cur.execute("UPDATE raw.CMC_MEME_MEMBER SET MEME_STS=%s,SYS_LAST_UPD_DTM=GETDATE(),ETL_PROCESS_EXECUTION_ID=%s WHERE MEME_ID=%s",
                (random.choice(['AC','IN']),exec_id,mid))
        conn.commit()
        log.append(f"MEME +{n} ins, upd")

        n = random.randint(30,100)
        for _ in range(n):
            sid = nxt('sbsb'); dob = date.today()-timedelta(days=random.randint(365*18,365*70))
            cur.execute("INSERT INTO raw.CMC_SBSB_SUBSC (SBSB_ID,SBSB_LAST_NAME,SBSB_FIRST_NAME,SBSB_DOB,SBSB_SEX,SBSB_STS,SBSB_MCTR_TYPE,SYS_USUS_ID,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,'AC',%s,'ETL_INCR',%s,%s)",
                (sid,random.choice(LAST_NAMES),random.choice(FIRST_NAMES),dob,random.choice(['M','F','U']),random.choice(['MEDCAID','COMM','DSNP']),exec_id,RH))
            sbsb_ids.append(sid)
        for sid in get_random_ids(cur,'raw.CMC_SBSB_SUBSC','SBSB_ID',random.randint(20,50)):
            cur.execute("UPDATE raw.CMC_SBSB_SUBSC SET SBSB_STS=%s,SYS_LAST_UPD_DTM=GETDATE(),ETL_PROCESS_EXECUTION_ID=%s WHERE SBSB_ID=%s",
                (random.choice(['AC','IN']),exec_id,sid))
        conn.commit()
        log.append(f"SBSB +{n} ins, upd")

        n = random.randint(100,200)
        for _ in range(n):
            eid = nxt('sbel'); eff = rand_date()
            cur.execute("INSERT INTO raw.CMC_SBEL_ELIG_ENT (SBEL_ID,SBSB_ID,SBEL_EFF_DT,SBEL_ELIG_STS,SBEL_PLAN_TYPE,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,'AC',%s,%s,%s)",
                (eid,random.choice(sbsb_ids),eff,random.choice(PLAN_TYPES),exec_id,RH))
        conn.commit()
        log.append(f"SBEL +{n}")

        n = random.randint(150,250)
        for _ in range(n):
            aid = nxt('meia')
            cur.execute("INSERT INTO raw.CMC_MEIA_ID_ACT (MEIA_ID,MEME_ID,MEIA_ACT_TYPE,MEIA_USUS_ID,MEIA_DETAIL,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,'ETL_INCR',%s,%s,%s)",
                (aid,random.choice(meme_ids),random.choice(ACT_TYPES),f"Event at {run_ts}",exec_id,RH))
        cur.execute("DELETE TOP (5) FROM raw.CMC_MEIA_ID_ACT WHERE MEIA_ACT_DTM < DATEADD(day,-90,GETDATE())")
        conn.commit()
        log.append(f"MEIA +{n} ins, -stale")

        n = random.randint(50,150)
        for _ in range(n):
            cid = nxt('mctr')
            cur.execute("INSERT INTO raw.CMC_MCTR_CD_TRANS (MCTR_ID,MCTR_TYPE,MCTR_VALUE,MCTR_DESC,MCTR_ENTITY,MCTR_SORT,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,'MEMBER',%s,%s,%s)",
                (cid,random.choice(['PLAN','LOB','GRP']),f"CD{random.randint(100,999)}",f"Code {cid}",cid%100,exec_id,RH))
        cur.execute("DELETE TOP (3) FROM raw.CMC_MCTR_CD_TRANS WHERE MCTR_LOCK_TOKEN=0 AND MCTR_SORT<50")
        conn.commit()
        log.append(f"MCTR +{n} ins, -stale")

        n = random.randint(50,100)
        for _ in range(n):
            sid2 = nxt('mesu'); eff = rand_date()
            cur.execute("INSERT INTO raw.CMC_MESU_SUBSIDY (MESU_ID,MEME_ID,MESU_SUBSIDY_AMT,MESU_PREMIUM_AMT,MESU_EFF_DT,MESU_SUBSIDY_TYPE,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,'APTC',%s,%s)",
                (sid2,random.choice(meme_ids),round(random.uniform(100,800),2),round(random.uniform(0,150),2),eff,exec_id,RH))
        for sid2 in get_random_ids(cur,'raw.CMC_MESU_SUBSIDY','MESU_ID',random.randint(20,40)):
            cur.execute("UPDATE raw.CMC_MESU_SUBSIDY SET MESU_SUBSIDY_AMT=%s,SYS_LAST_UPD_DTM=GETDATE(),ETL_PROCESS_EXECUTION_ID=%s WHERE MESU_ID=%s",
                (round(random.uniform(100,900),2),exec_id,sid2))
        conn.commit()
        log.append(f"MESU +{n} ins, upd")

        # ── TIER 2: 50% probability ────────────────────────────────────────────
        run_t2 = random.random() < 0.50
        if run_t2:
            n = random.randint(1,3)
            for _ in range(n):
                pid = nxt('prpr'); entity = random.choice(['I','I','I','O'])
                name = f"Dr. {random.choice(LAST_NAMES)}, MD" if entity=='I' else f"{random.choice(LAST_NAMES)} Group"
                npi = ''.join([str(random.randint(0,9)) for _ in range(10)])
                cur.execute("INSERT INTO raw.CMC_PRPR_PROV (PRPR_ID,PRPR_ENTITY,PRPR_NAME,PRPR_NPI,PRPR_TAXONOMY_CD,PRPR_STS,PRPR_MCTR_TYPE,PRPR_OPTS,PRPR_LOCK_TOKEN,SYS_USUS_ID,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,'AC','FFS','Y',0,'ETL_INCR',%s,%s)",
                    (pid,entity,name,npi,random.choice(TAXONOMIES) if entity=='I' else '193200000X',exec_id,RH))
                prpr_ids.append(pid)
                prid = nxt('prad')
                cur.execute("INSERT INTO raw.CMC_PRAD_ADDRESS (PRAD_ID,PRPR_ID,PRAD_ADDR1,PRAD_CITY,PRAD_ST,PRAD_ZIP,PRAD_TYPE) VALUES (%s,%s,%s,%s,'CA',%s,'PR')",
                    (prid,pid,f"{random.randint(100,9999)} New Blvd",random.choice(CITIES),f"926{random.randint(10,99)}"))
            for pid in get_random_ids(cur,'raw.CMC_PRPR_PROV','PRPR_ID',random.randint(1,2)):
                cur.execute("UPDATE raw.CMC_PRPR_PROV SET PRPR_STS=%s,SYS_LAST_UPD_DTM=GETDATE(),ETL_PROCESS_EXECUTION_ID=%s WHERE PRPR_ID=%s",
                    (random.choice(['AC','IN','SU']),exec_id,pid))
            conn.commit()
            log.append(f"PRPR +{n} [T2]")

            n = random.randint(1,3)
            for _ in range(n):
                nrid = nxt('nwpr'); eff = rand_date()
                cur.execute("INSERT INTO raw.CMC_NWPR_RELATION (NWPR_ID,NWNW_ID,PRPR_ID,AGAG_ID,NWPR_EFF_DT,NWPR_TERM_DT,NWPR_PCP_IND,NWPR_DIRECTORY_IND,NWPR_ACC_PAT_IND,NWPR_ACC_MEDCD_IND,NWPR_PAT_CTR,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,NULL,%s,'Y','Y','Y',%s,%s,%s)",
                    (nrid,random.choice(nwnw_ids),random.choice(prpr_ids),random.choice(agag_ids),eff,'Y' if random.random()>0.7 else 'N',random.randint(0,200),exec_id,RH))
            conn.commit()
            log.append(f"NWPR +{n} [T2]")

            for _ in range(random.randint(2,5)):
                mpid = nxt('mepr'); eff = rand_date()
                # MEPR_PCP_TYPE is CHAR(2) — use 'PC' not 'PCP'
                cur.execute("INSERT INTO raw.CMC_MEPR_PRIM_PROV (MEPR_ID,MEME_ID,PRPR_ID,MEPR_EFF_DT,MEPR_PCP_TYPE,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,'PC',%s,%s)",
                    (mpid,random.choice(meme_ids),random.choice(prpr_t1 if prpr_t1 else prpr_ids),eff,exec_id,RH))
            for mid in get_random_ids(cur,'raw.CMC_MEPR_PRIM_PROV','MEPR_ID',random.randint(1,3)):
                cur.execute("UPDATE raw.CMC_MEPR_PRIM_PROV SET MEPR_TERM_DT=%s,SYS_LAST_UPD_DTM=GETDATE(),ETL_PROCESS_EXECUTION_ID=%s WHERE MEPR_ID=%s AND MEPR_TERM_DT IS NULL",
                    (rand_date(),exec_id,mid))
            conn.commit()
            log.append("MEPR ins+upd [T2]")

            for _ in range(random.randint(1,3)):
                cur.execute("INSERT INTO raw.CMC_MECB_COB (MECB_ID,MEME_ID,MECB_CARRIER_NM,MECB_POLICY_NO,MECB_EFF_DT,MECB_COB_ORDER) VALUES (%s,%s,%s,%s,%s,'2')",
                    (nxt('mecb'),random.choice(meme_ids),random.choice(['Blue Shield','Aetna','Cigna']),f"POL{random.randint(100000,999999)}",rand_date()))
            for _ in range(random.randint(2,5)):
                cur.execute("INSERT INTO raw.CMC_MECR_NO_XREF (MECR_ID,MEME_ID,MECR_NO,MECR_TYPE,MECR_EFF_DT) VALUES (%s,%s,%s,'MEDI_CAL',%s)",
                    (nxt('mecr'),random.choice(meme_ids),f"MC{random.randint(10000000,99999999)}",rand_date()))
            for _ in range(random.randint(2,5)):
                cdid = nxt('mecd'); eff = rand_date()
                cur.execute("INSERT INTO raw.CMC_MECD_MEDICAID (MECD_ID,MEME_ID,MECD_AID_CD,MECD_BIC,MECD_EFF_DT,MECD_STS,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,'AC',%s,%s)",
                    (cdid,random.choice(meme_ids),random.choice(AID_CODES),f"BIC{random.randint(1000000,9999999)}",eff,exec_id,RH))
            for mid in get_random_ids(cur,'raw.CMC_MECD_MEDICAID','MECD_ID',random.randint(1,2)):
                cur.execute("UPDATE raw.CMC_MECD_MEDICAID SET MECD_AID_CD=%s,SYS_LAST_UPD_DTM=GETDATE(),ETL_PROCESS_EXECUTION_ID=%s WHERE MECD_ID=%s",
                    (random.choice(AID_CODES),exec_id,mid))
            conn.commit()

            for _ in range(random.randint(1,3)):
                eid2 = nxt('mees'); eff = rand_date()
                cur.execute("INSERT INTO raw.CMC_MEES_EXCHANGE (MEES_ID,MEME_ID,MEES_EXCHANGE_ID,MEES_EFF_DT,MEES_ENROLL_TYPE,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,'SEP',%s,%s)",
                    (eid2,random.choice(meme_ids),f"EX{random.randint(10000000,99999999)}",eff,exec_id,RH))
            conn.commit()

            n = random.randint(3,8)
            for _ in range(n):
                wmid = nxt('prwm')
                cur.execute("INSERT INTO raw.CMC_PRWM_PR_MSG (PRWM_ID,PRPR_ID,PRWM_MSG_TYPE,PRWM_MSG_TEXT,PRWM_USUS_ID) VALUES (%s,%s,%s,%s,'ETL_INCR')",
                    (wmid,random.choice(prpr_ids),random.choice(MSG_TYPES),f"Workflow at {run_ts}"))
            cur.execute("DELETE TOP (3) FROM raw.CMC_PRWM_PR_MSG WHERE PRWM_MSG_DTM < DATEADD(day,-60,GETDATE())")
            conn.commit()
            log.append(f"PRWM +{n} [T2]")

            for pid in get_random_ids(cur,'raw.CMC_PRAD_ADDRESS','PRAD_ID',random.randint(1,3)):
                cur.execute("UPDATE raw.CMC_PRAD_ADDRESS SET PRAD_ADDR1=%s,PRAD_CITY=%s,SYS_LAST_UPD_DTM=GETDATE() WHERE PRAD_ID=%s",
                    (f"{random.randint(100,9999)} Updated Blvd",random.choice(CITIES),pid))
            conn.commit()

        # ── TIER 3: 20% probability ────────────────────────────────────────────
        run_t3 = random.random() < 0.20
        if run_t3:
            if random.random() < 0.4:
                aid2 = nxt('agag'); eff = rand_date(2024, 2026)
                cur.execute("INSERT INTO raw.CMC_AGAG_AGREEMENT (AGAG_ID,AGAG_DESC,AGAG_EFF_DT,AGAG_MCTR_TYPE,AGAG_CAT) VALUES (%s,%s,%s,%s,'PR')",
                    (aid2,f"New Agreement {aid2}",eff,random.choice(['FFS','CAP'])))
            if random.random() < 0.5:
                pid2 = nxt('prcr')
                cur.execute("INSERT INTO raw.CMC_PRCR_CREDEN (PRCR_ID,PRPR_ID,PRCR_TYPE,PRCR_STATUS,PRCR_EFF_DT) VALUES (%s,%s,%s,'AC',%s)",
                    (pid2,random.choice(prpr_t1 if prpr_t1 else prpr_ids),random.choice(['CRED','RECRED']),rand_date()))
            if random.random() < 0.4:
                cfid = nxt('prcf')
                cur.execute("INSERT INTO raw.CMC_PRCF_CERT (PRCF_ID,PRPR_ID,PRCF_BOARD_TYPE,PRCF_CERT_NO,PRCF_EFF_DT) VALUES (%s,%s,%s,%s,%s)",
                    (cfid,random.choice(prpr_t1 if prpr_t1 else prpr_ids),random.choice(['ABIM','ABFM']),f"CERT{random.randint(10000,99999)}",rand_date()))
            if random.random() < 0.3:
                npid = nxt('prnp')
                cur.execute("INSERT INTO raw.CMC_PRNP_NPI (PRNP_ID,PRPR_ID,PRNP_NPI,PRNP_NPI_TYPE,PRNP_EFF_DT) VALUES (%s,%s,%s,'2',%s)",
                    (npid,random.choice(prpr_t2 if prpr_t2 else prpr_ids),''.join([str(random.randint(0,9)) for _ in range(10)]),rand_date()))
            if random.random() < 0.4:
                cur.execute("UPDATE raw.CMC_MEDD_DEM_DATA SET MEDD_LANG_CD=%s,SYS_LAST_UPD_DTM=GETDATE() WHERE MEDD_ID=(SELECT TOP 1 MEDD_ID FROM raw.CMC_MEDD_DEM_DATA ORDER BY NEWID())",
                    (random.choice(['ENG','SPA','VIE','KOR','ZHO']),))
            if random.random() < 0.3:
                cur.execute("UPDATE raw.CMC_AGAG_AGREEMENT SET AGAG_TERM_DT=%s,SYS_LAST_UPD_DTM=GETDATE() WHERE AGAG_ID=(SELECT TOP 1 AGAG_ID FROM raw.CMC_AGAG_AGREEMENT WHERE AGAG_TERM_DT IS NULL ORDER BY NEWID())",
                    (rand_date(2025,2026),))
            conn.commit()
            log.append("T3: AGAG/CRED/CERT/NPI/DEM spot updates")

        # ── Safe delete: aged-out MEPE spans ──────────────────────────────────
        cur.execute("DELETE TOP (10) FROM raw.CMC_MEPE_PRCS_ELIG WHERE MEPE_STS='IN' AND MEPE_TERM_DT < DATEADD(day,-365,GETDATE())")
        mepe_del = cur.rowcount
        conn.commit()
        if mepe_del > 0:
            log.append(f"MEPE -{mepe_del} aged spans purged")

        # ── Near-duplicate drip (~5% per run) — supports Silver dedup demo ────
        if random.random() < 0.05:
            cur.execute("SELECT TOP 1 MEME_ID, SBSB_ID, MEME_LAST_NAME, MEME_FIRST_NAME, MEME_DOB, MEME_SEX, MEME_MCTR_TYPE FROM raw.CMC_MEME_MEMBER ORDER BY NEWID()")
            row = cur.fetchone()
            if row:
                orig_mid, sid, lname, fname, dob, sex, mctr = row
                dup_mid = max_ids['meme'] + 1
                max_ids['meme'] = dup_mid
                cur.execute(
                    "INSERT INTO raw.CMC_MEME_MEMBER (MEME_ID,SBSB_ID,MEME_REL_CD,MEME_LAST_NAME,MEME_FIRST_NAME,MEME_DOB,MEME_SEX,MEME_STS,MEME_MCTR_TYPE,SYS_USUS_ID,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,'01',%s,%s,%s,%s,'AC',%s,'ETL_INCR_DUP',%s,%s)",
                    (dup_mid, sid, lname, fname, dob, sex, mctr, exec_id, RH))
                conn.commit()
                log.append(f"MEME near-dup injected (MEME_ID={dup_mid})")

        if random.random() < 0.05:
            cur.execute("SELECT TOP 1 MEME_ID, SBSB_ID, CSPI_ID, MEPE_EFF_DT, MEPE_PLAN_TYPE FROM raw.CMC_MEPE_PRCS_ELIG WHERE MEPE_TERM_DT IS NULL ORDER BY NEWID()")
            row = cur.fetchone()
            if row:
                orig_mid, orig_sid, orig_cspi, orig_eff, orig_plan = row
                overlap_eff = orig_eff + timedelta(days=random.randint(30, 120))
                if overlap_eff <= date.today():
                    dup_mepe = max_ids['mepe'] + 1
                    max_ids['mepe'] = dup_mepe
                    cur.execute(
                        "INSERT INTO raw.CMC_MEPE_PRCS_ELIG (MEPE_ID,MEME_ID,SBSB_ID,CSPI_ID,MEPE_EFF_DT,MEPE_TERM_DT,MEPE_STS,MEPE_ELIG_TYPE,MEPE_PLAN_TYPE,ETL_PROCESS_EXECUTION_ID,ROW_HASH_VALUE) VALUES (%s,%s,%s,%s,%s,NULL,'AC','MEDICAID',%s,%s,%s)",
                        (dup_mepe, orig_mid, orig_sid, orig_cspi, overlap_eff, orig_plan, exec_id, RH))
                    conn.commit()
                    log.append(f"MEPE overlapping span injected (MEME_ID={orig_mid}, EFF={overlap_eff})")

        return f"INCR [{run_ts}] T2={'Y' if run_t2 else 'N'} T3={'Y' if run_t3 else 'N'}\n" + "\n".join(log)

    except Exception as e:
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()
$$;

-- =============================================================================
-- STEP 2: Snowflake Task
--         Schedule: hourly until July 7, then alter to 12 MINUTE for the demo.
--         WH_XS is the demo warehouse — swap if needed.
-- =============================================================================

CREATE OR REPLACE TASK FACETS_INCREMENTAL_TASK
    WAREHOUSE = WH_XS
    SCHEDULE  = '60 MINUTE'
    COMMENT   = 'Synthetic Facets CDC: hourly until Jul 7, then 12 MINUTE'
AS
    CALL FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_LOAD(
        'tjonessqlserver.database.windows.net',
        'openflow'
    );

-- Start the task (uncomment when ready):
-- ALTER TASK FACETS_INCREMENTAL_TASK RESUME;

-- Switch to 12-minute schedule on July 7:
-- ALTER TASK FACETS_INCREMENTAL_TASK SUSPEND;
-- ALTER TASK FACETS_INCREMENTAL_TASK SET SCHEDULE = '12 MINUTE';
-- ALTER TASK FACETS_INCREMENTAL_TASK RESUME;

-- =============================================================================
-- STEP 3: Verification
-- =============================================================================

SHOW TASKS LIKE 'FACETS_INCREMENTAL_TASK';

SELECT *
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('hour', -1, CURRENT_TIMESTAMP()),
    TASK_NAME => 'FACETS_INCREMENTAL_TASK'
))
ORDER BY SCHEDULED_TIME DESC;
