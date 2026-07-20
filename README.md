# CalOptima RFP 26-038 — Snowflake Demo Environment

This repo is a complete Sales Engineering demo environment for **CalOptima RFP 26-038**. It demonstrates Snowflake's capabilities across seven scenarios using synthetic [TriZetto Facets](https://www.trizetto.com/products/facets/) health plan data replicated in real time from Azure SQL Server via Openflow.

A colleague starting fresh should be able to rebuild the entire environment by following the setup order in this document.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Setup Order — From Scratch](#2-setup-order--from-scratch)
3. [Pre-Demo Reset (Before Every Session)](#3-pre-demo-reset-before-every-session)
4. [Post-Demo Cleanup](#4-post-demo-cleanup)
5. [Demo Sections](#5-demo-sections)
   - [00 — Flat File Ingestion](#00--flat-file-ingestion)
   - [01 — Openflow CDC](#01--openflow-cdc)
   - [01 — Openflow Observability (Streamlit App)](#01--openflow-observability-streamlit-app)
   - [02 — dbt / CI/CD / Time Travel Rollback](#02--dbt--cicd--time-travel-rollback)
   - [03 — Cortex Agent](#03--cortex-agent)
   - [04 — Performance & Scale](#04--performance--scale)
   - [05 — Data Quality](#05--data-quality)
   - [06 — Governance](#06--governance)
6. [Database Map](#6-database-map)
7. [Task & Alert Pipeline](#7-task--alert-pipeline)
8. [dbt Project Structure](#8-dbt-project-structure)
9. [Key Stored Procedures Reference](#9-key-stored-procedures-reference)
10. [File Naming Conventions](#10-file-naming-conventions)

---

## 1. Architecture Overview

**Data flow:**

```
Azure SQL Server (openflow db, 36 Facets tables)
        │
        │  Openflow CDC (Change Tracking)
        ▼
FACETS_BRONZE.RAW.*           ← Bronze landing zone (Openflow manages this)
        │
        │  Snowflake Tasks trigger dbt
        ▼
FACETS_DEV / QA / PROD        ← Silver + Gold (dbt manages these)
        │
        ├── STAGING.*          views over Bronze
        ├── SILVER.*           incremental tables (merge)
        ├── GOLD.*             views for analytics consumers
        └── DQ.*               pipeline observability tables
```

**Two dbt project objects keep dev isolated from production:**

| Git event | Deploys to | Runs against |
|---|---|---|
| `push → dev` | `CALOPTIMA_DW_DEV` | `FACETS_DEV` |
| `merge → main` (PR) | `CALOPTIMA_DW` | `FACETS_QA` + `FACETS_PROD` |

A broken dev commit only affects `FACETS_DEV` — QA and PROD keep running the last stable main-branch code. See [`02_dbt/one_time_execute/99_dbt_projects_and_environments.md`](02_dbt/one_time_execute/99_dbt_projects_and_environments.md) for the full architecture doc.

---

## 2. Setup Order — From Scratch

Run each step in order. Steps marked **SSMS** run in SQL Server Management Studio or Azure Data Studio against the `openflow` database.

### Step 1 — Azure SQL Server tables and permissions

```
01_openflow/one_time_execute/openflow_initial_direct_setup/01_sql_server_ddl.sql         (SSMS)
01_openflow/one_time_execute/openflow_initial_direct_setup/02_sql_server_permissions.sql  (SSMS)
```

Creates all 36 Facets tables in the `openflow.raw` schema and enables Change Tracking on all of them. Grants `openflow_user` the `VIEW CHANGE TRACKING` permission needed by Openflow's CDC connector.

### Step 2 — Snowflake infrastructure

```
01_openflow/one_time_execute/openflow_initial_direct_setup/03_snowflake_secrets_setup.sql
02_dbt/one_time_execute/01_database_schema_setup.sql
02_dbt/one_time_execute/02_github_actions_setup.sql
```

Creates: `FACETS_BRONZE` database + `UTILS` schema, the `FACETS_SQL_CREDS` password secret, the `AZURE_SQL_NETWORK_RULE` egress rule, and `AZURE_SQL_FACETS_EAI` External Access Integration. Also creates `FACETS_DEV/QA/PROD` databases with `STAGING/SILVER/GOLD/DQ` schemas, and a network policy that allows GitHub Actions IP ranges to authenticate.

### Step 3 — Seed data into Azure SQL

```
01_openflow/one_time_execute/openflow_initial_direct_setup/04_initial_load_deploy.sql
```

Deploys `FACETS_BRONZE.UTILS.FACETS_INITIAL_LOAD` (Python stored proc). Then call it:

```sql
CALL FACETS_BRONZE.UTILS.FACETS_INITIAL_LOAD(
    'tjonessqlserver.database.windows.net',
    'openflow'
);
```

Seeds all 35 tables with synthetic data: 20 networks, 50 agreements, 5,000 providers, 50,000 subscribers, ~70K+ members, eligibility spans, Medicaid records, office hours, etc.

### Step 4 — Configure Openflow connector

In the Openflow UI:
1. Create a new connector pointing at `tjonessqlserver.database.windows.net` / `openflow` database
2. Add all 36 tables from the list in `01_openflow/execute_demo/00_OF_add_table_s_.sql`
3. Let Openflow run its initial snapshot — it will populate `FACETS_BRONZE.RAW.*`

### Step 5 — Deploy the incremental load task

```
01_openflow/one_time_execute/openflow_initial_direct_setup/05_incremental_load_deploy.sql
```

Deploys `FACETS_INCREMENTAL_LOAD` Python stored proc + `FACETS_INCREMENTAL_TASK` Snowflake task. The task runs tier-weighted synthetic CDC DML every 15 minutes to keep Bronze data changing (Tier 1: member/eligibility always; Tier 2: provider changes 50% probability; Tier 3: spot updates 20% probability). Resume when ready:

```sql
ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK RESUME;
```

### Step 6 — Deploy the Openflow revert stored proc

```
01_openflow/one_time_execute/openflow_mssql_revert_sproc.sql
```

Deploys `FACETS_BRONZE.UTILS.OPENFLOW_SCHEMA_REVERT_MSSQL`. This idempotent sproc resets the Azure SQL Server side of the schema drift demo and is called automatically by the pre-demo reset script on every demo run. Deploy it once and leave it.

### Step 7 — Deploy utility stored procs (optional but recommended)

```
01_openflow/one_time_execute/non_openflow_direct_setup/00_alert_data_latency.sql
01_openflow/one_time_execute/non_openflow_direct_setup/07_azure_sql_connection_test.sql
```

The latency alert deploys `FACETS_LATENCY_CHECK` + `FACETS_LATENCY_TASK` — checks replication lag between Azure SQL and Bronze every 15 minutes and emails if any table is >15 min behind. The connection test verifies Snowflake can reach Azure SQL.

### Step 8 — CI/CD: deploy dbt project objects

1. Fork/clone this repo, push to the `dev` branch
2. Set GitHub Actions secrets: `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_PAT`
3. A push to `dev` automatically runs `.github/workflows/dbt_ci.yml` which deploys `CALOPTIMA_DW_DEV` and runs `dbt build --target dev`
4. Merge to `main` deploys `CALOPTIMA_DW` and runs qa + prod builds

To manually deploy without CI:

```bash
cd caloptima_dw && snow dbt deploy caloptima_dw_dev --database ANALYTICS_ADMIN --schema PROJECTS
```

### Step 9 — Rebuild the Stream+Task SCD2 pipeline

```
02_dbt/one_time_execute/03_rebuild_provider_scd2_pipeline.sql
```

Deploy the stored proc, then call it:

```sql
CALL FACETS_BRONZE.UTILS.SP_REBUILD_PROVIDER_SCD2_PIPELINE(
    P_REBUILD_DEV  => TRUE,
    P_REBUILD_QA   => TRUE,
    P_REBUILD_PROD => TRUE,
    P_DRY_RUN      => FALSE
);
```

This creates the CDC streams on `CMC_PRPR_PROV`, the `PROVIDER_SCD2_VIA_STREAM` tables in all three environments, the `SP_PROVIDER_SCD2_STREAM_REFRESH` stored procs, and the `PROVIDER_SCD2_STREAM_TASK_*` tasks.

### Step 10 — Rebuild dbt tasks

```
02_dbt/one_time_execute/04_rebuild_dbt_tasks.sql
```

Creates `DBT_REFRESH_TASK_DEV/QA/PROD` as Snowflake tasks chained after their respective stream tasks. Resumes them automatically.

### Step 11 — Run initial dbt build

```sql
EXECUTE TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_DEV;
```

Or wait for `FACETS_INCREMENTAL_TASK` to fire and trigger the chain automatically.

### Step 12 — Flat file ingestion setup

Upload the CSV/XML files from `00_flat_file_ingestion/zz_flat_file_DATA/data/` to your cloud storage:
- Azure Blob: `azure://timjones.blob.core.windows.net/data/` (or your container)
- AWS S3: `s3://capstone-timjones/` (or your bucket)
- Internal stage: use `PUT file://... @MY_STAGE`

Update the storage integration and stage URLs in the `execute_demo/` scripts to match your environment.

### Step 13 — Governance setup

```
06_governance_demo/one_time_execute/01_governance_setup.sql
```

Creates 3 demo roles, two zero-copy clone databases (`zFACETS_DEV_CLONE`, `GOVERNANCE_CA_DEMO`), AI classification profile, tag-based masking policies, and row access policy. ~560 lines — read the section headers before running.

### Step 14 — Data quality setup

```
05_data_quality/one_time_execute/01_dq_setup.sql
```

Creates `zzFACETS_DEV_CLONE` (zero-copy clone), email notification integration, 3 custom DMFs, 11 DMF associations on `SILVER.MEMBER`, expectations with pass/fail thresholds, and the `MEMBER_DQ_ALERT`. Also deploys `INJECT_DIRTY_DATA()` and `CLEAN_DIRTY_DATA()` stored procs.

> Note: `zFACETS_DEV_CLONE` (single z) is for governance. `zzFACETS_DEV_CLONE` (double z) is for DQ. They are separate clones.

### Step 15 — Performance & scale setup

```
04_performance_scale/one_time_execute/02_concurrency_setup.sql
```

Materializes `TPCH_SF100.LINEITEM` (~600M rows) into a local database (runs once, ~10 min). Creates and pre-resumes 100 `CONCURRENT_USER_NN` tasks for the multi-cluster demo so the kickoff is fast on demo day.

### Step 16 — Streamlit observability app

Deploy `01_openflow_observability/` as a Streamlit in Snowflake app. The `snowflake.yml` file contains the deployment config. The app reads from `OPENFLOW.TELEMETRY.EVENTS` (set by Openflow automatically) and `FACETS_BRONZE.UTILS.APP_CONFIG`.

### Step 17 — Git repository object for pre-demo reset

Set up once in Snowflake:

```sql
CREATE DATABASE IF NOT EXISTS DEMO_DEPLOY;
CREATE SCHEMA  IF NOT EXISTS DEMO_DEPLOY.GIT;

CREATE GIT REPOSITORY DEMO_DEPLOY.GIT.CALOPTIMA_REPO
    API_INTEGRATION = MY_GIT_API_INTEGRATION
    GIT_CREDENTIALS = POLICY_SETTINGS.POLICY_SCHEMA.MY_GIT_SECRET
    ORIGIN = 'https://github.com/sfc-gh-timjones/caloptima';
```

Replace `MY_GIT_API_INTEGRATION` and `MY_GIT_SECRET` with your own Git API Integration and PAT secret. The pre-demo reset script (`one_time_pre_demo_snow.sql`) uses this to fetch and execute scripts directly from GitHub.

---

## 3. Pre-Demo Reset (Before Every Session)

Run **`one_time_pre_demo_snow.sql`** (at the repo root) before every demo. It is designed to be run top-to-bottom and handles all resets automatically:

| Section | What it does |
|---|---|
| 1. Git repo | Creates `DEMO_DEPLOY.GIT.CALOPTIMA_REPO` if not present; fetches latest commits |
| 2. Openflow Snowflake revert | Drops `CMC_PRTP_PROV_TYPE` and any JOURNAL tables from `FACETS_BRONZE.RAW` |
| 3. Openflow SQL Server revert | Calls `OPENFLOW_SCHEMA_REVERT_MSSQL` — restores PRTP_ID 2 and 7, deletes rows ≥9001, drops the added column, re-grants `VIEW CHANGE TRACKING` |
| 4. dbt clean rebuild | Rebuilds `FACETS_DEV.SILVER.PROVIDER_OFFICE_HOURS` from staging with clean data (counteracts the intentionally bad code in dev branch) |
| 5. Governance restore | Re-grants `BUSINESS_ANALYST_ROLE` access to `zFACETS_DEV_CLONE.SILVER.MEMBER` |

After the script completes, two verification queries confirm: (1) no PRTP journal tables remain, (2) `BUSINESS_ANALYST_ROLE` has SELECT on the MEMBER table.

**Important:** Make sure tasks and alerts are **RESUMED** before the demo starts. They are suspended after each session (see [Post-Demo Cleanup](#4-post-demo-cleanup)).

```sql
-- Resume everything before demo
ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK          RESUME;
ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_DEV    RESUME;
ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_QA     RESUME;
ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_PROD   RESUME;
ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_DEV             RESUME;
ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_QA              RESUME;
ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_PROD            RESUME;
ALTER TASK FACETS_BRONZE.UTILS.FACETS_LATENCY_TASK              RESUME;
ALTER ALERT FACETS_BRONZE.UTILS.DAILY_SPEND_ALERT               RESUME;
ALTER ALERT ZZFACETS_DEV_CLONE.SILVER.MEMBER_DQ_ALERT           RESUME;
```

---

## 4. Post-Demo Cleanup

After the demo, suspend everything to stop credit consumption:

```sql
-- Suspend tasks (child before root for DAG tasks)
ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_DEV             SUSPEND;
ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_QA              SUSPEND;
ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_PROD            SUSPEND;
ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_DEV    SUSPEND;
ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_QA     SUSPEND;
ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK_PROD   SUSPEND;
ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK          SUSPEND;
ALTER TASK FACETS_BRONZE.UTILS.FACETS_LATENCY_TASK              SUSPEND;

-- Suspend alerts
ALTER ALERT FACETS_BRONZE.UTILS.DAILY_SPEND_ALERT               SUSPEND;
ALTER ALERT ZZFACETS_DEV_CLONE.SILVER.MEMBER_DQ_ALERT           SUSPEND;
```

**Streams do not consume credits** when idle — they are metadata-only objects. They are safe to leave running. However, if a stream goes unread for longer than the data retention period (7 days on this account), it becomes stale and must be recreated. If the demo will be idle for more than a week, either resume the tasks periodically or rebuild streams via `03_rebuild_provider_scd2_pipeline.sql` before the next demo.

---

## 5. Demo Sections

---

### 00 — Flat File Ingestion

**Folder:** `00_flat_file_ingestion/`

**What it shows:** COPY INTO with schema inference, INFER_SCHEMA, schema evolution, Snowpipe AUTO_INGEST, XML loading.

#### Why are there so many ingestion files?

There are 4 versions of the same demo flow — one notebook and three SQL scripts. They all do the identical steps; only the storage backend differs:

| File | Storage backend | Notes |
|---|---|---|
| `execute_demo/flat_file_ingestion1.ipynb` | Azure Blob | **Primary demo artifact** — the notebook format used in the live demo |
| `execute_demo/flat_file_ingestion1.sql` | Azure Blob | SQL backup version of the same Azure flow |
| `execute_demo/flat_file_ingestion2.sql` | AWS S3 | Use this if your Snowflake account is on AWS |
| `execute_demo/flat_file_ingestion3.sql` | Internal named stage | Use this if no external storage integration is configured |

The **notebook** is the primary demo vehicle. The three SQL scripts exist as fallbacks — if Azure storage is unavailable or the demo account is on a different cloud, you can swap to the matching script without rewriting anything.

#### `z_legacy_ignore/`

Three files from an older iteration of this demo (before the current structure existed):
- `01_storage_int.sql` — Azure storage integration creation
- `02_load_data.sql` — old COPY INTO script
- `03_snowpipe.sql` — old Snowpipe creation

**Do not run these.** They are kept for historical reference only and are excluded from git via `.gitignore`.

#### Data files

All source CSV/XML files are in `zz_flat_file_DATA/data/`. Upload these to your cloud storage before running the demo:

| File | Used for |
|---|---|
| `pharmacy_claims.csv` | Initial COPY INTO load |
| `pharmacy_claims_bad_records.csv` | `VALIDATION_MODE` + `ON_ERROR = CONTINUE` demo |
| `pharmacy_claims_inc1.csv`, `_inc2.csv` | Snowpipe incremental ingestion |
| `pharmacy_claims_add_refillnum.csv` | Schema evolution (adds `REFILL_NUMBER` column) |
| `medical_claims.xml` | XML loading into VARIANT + XMLGET flattening |

#### Demo flow

1. `INFER_SCHEMA` → auto-detect column names and types
2. `CREATE TABLE USING TEMPLATE` with `ENABLE_SCHEMA_EVOLUTION = TRUE`
3. `COPY INTO` with `VALIDATION_MODE = 'RETURN_ERRORS'` and `ON_ERROR = CONTINUE`
4. Create Snowpipe with `AUTO_INGEST = TRUE`; upload incremental files; show auto-ingestion
5. Upload schema-evolution file; Snowflake auto-alters the table and ingests the new column
6. Load `medical_claims.xml` into VARIANT; flatten with `XMLGET`

---

### 01 — Openflow CDC

**Folder:** `01_openflow/`

**What it shows:** Real-time CDC replication from Azure SQL Server via Openflow, schema drift detection, error handling and recovery, row count parity validation.

#### Folder structure

```
01_openflow/
├── execute_pre_demo/       Run before the Openflow demo (handled by master reset script)
├── execute_demo/           Run during the live demo
└── one_time_execute/
    ├── openflow_initial_direct_setup/   Run once, in order 01→05, to build the environment
    └── non_openflow_direct_setup/       Utility sprocs (latency alert, connection test, etc.)
```

#### `one_time_execute/openflow_initial_direct_setup/` — run once in order

| File | What it does |
|---|---|
| `01_sql_server_ddl.sql` | Creates all 36 Facets tables in Azure SQL (`openflow.raw`). SSMS. |
| `02_sql_server_permissions.sql` | Enables Change Tracking on database + all tables. Grants `openflow_user`. SSMS. |
| `03_snowflake_secrets_setup.sql` | Creates `FACETS_BRONZE`, credentials secret, network rule, External Access Integration. |
| `04_initial_load_deploy.sql` | Deploys `FACETS_INITIAL_LOAD` sproc + call it once to seed all 35 tables with synthetic data. |
| `05_incremental_load_deploy.sql` | Deploys `FACETS_INCREMENTAL_LOAD` sproc + `FACETS_INCREMENTAL_TASK` (15-min schedule). |

#### `one_time_execute/non_openflow_direct_setup/` — utility sprocs

| File | What it does |
|---|---|
| `00_alert_data_latency.sql` | Deploys latency check sproc + task. Emails if any table is >15 min behind. |
| `01.1_row_counts_mssql.sql` | Azure SQL: UNION ALL row counts for all 35 tables. Run in SSMS for verification. |
| `01.2_truncate_all_mssql.sql` | Azure SQL: FK-safe DELETE all rows. Use when starting over from scratch. |
| `07_azure_sql_connection_test.sql` | Tests Snowflake → Azure SQL connectivity. Run to verify EAI is working. |

#### `openflow_mssql_revert_sproc.sql`

Deploys `FACETS_BRONZE.UTILS.OPENFLOW_SCHEMA_REVERT_MSSQL`. Deploy this once — it is called by the master pre-demo reset script on every demo run. It idempotently resets the Azure SQL side: restores PRTP_ID 2 and 7, deletes demo rows ≥9001, drops the added column, re-grants `VIEW CHANGE TRACKING`. Safe to run multiple times.

#### `execute_pre_demo/`

| File | What it does | How it runs |
|---|---|---|
| `00_OF_schema_revert_snow.sql` | Drops `CMC_PRTP_PROV_TYPE` and journal tables from `FACETS_BRONZE.RAW` | Called by master reset script via `EXECUTE IMMEDIATE FROM @repo/...` |
| `01_OF_schema_revert_mssql.sql` | Full SQL Server revert script (reference). The sproc above replaces running this manually. | Reference only — sproc handles it automatically |

#### `execute_demo/` — run during the demo

| File | When to run |
|---|---|
| `00_OF_add_table_s_.sql` | Reference: full list of 36 tables to paste into Openflow's "Included Table Names" field when (re)configuring the connector |
| `01_OF_schema_error_comp_SNOW.sql` | Run before and after schema change: shows Bronze auto-adapting to the new column, PRTP_ID 7 update flowing through, PRTP_ID 2 soft-delete (`_SNOWFLAKE_DELETED = TRUE`) |
| `02_OF_schema_change_mssql.sql` | **Run in SSMS.** The schema drift demo: widens `PRTP_DESC` to VARCHAR(200), adds `PRTP_EFFECTIVE_DT DATE`, inserts 5 new rows (9001–9005), updates PRTP_ID 7, deletes PRTP_ID 2 |
| `03_OF_force_error_mssql.sql` | **Run in SSMS (optional).** Error demo: revokes `VIEW CHANGE TRACKING` → Openflow errors. Inserts 5 more rows (9006–9010). Show the error in Openflow UI, then uncomment the GRANT to recover. |
| `04_OF_row_count_validation.sql` | Calls row count validation sproc. Run **only when `CMC_PRTP_PROV_TYPE` is present in Bronze** (i.e., after step 02 and before the pre-demo revert). |

#### Demo flow

1. Open Openflow UI → show connector health, table list
2. Run `01_OF_schema_error_comp_SNOW.sql` Section A — show current schema (15 rows, no `PRTP_EFFECTIVE_DT`)
3. Run `02_OF_schema_change_mssql.sql` in SSMS
4. Wait ~15-45 seconds for Openflow to pick up the change
5. Run `01_OF_schema_error_comp_SNOW.sql` Section B–D — show new column, updated row, soft-deleted row
6. Run `04_OF_row_count_validation.sql` — show parity report (36 tables including the new one)
7. *(Optional)* Run `03_OF_force_error_mssql.sql` to show error handling and recovery

---

### 01 — Openflow Observability (Streamlit App)

**Folder:** `01_openflow_observability/`

A Streamlit in Snowflake app that monitors the Openflow CDC pipeline in real time. Deploy it via `snowflake.yml`.

**What it shows:**
- 5 KPI tiles: tables tracked, active tables, last ingestion time (Mountain Time), stale tables (>2h), total DML events
- Per-table status grid: ingestion state, last event time, minutes since last event, Bronze row count. Stale rows highlighted.
- Drill-down on any table: per-minute batch history with insert/update/delete counts
- Throughput charts: DML events per hour, rows sent per hour
- DDL event chart: FlowFile DDL spike = schema change event (connects to the schema drift demo)
- Source row count validation button: calls `FACETS_ROW_COUNT_VALIDATION` and renders color-coded parity table

Reads from `OPENFLOW.TELEMETRY.EVENTS` (Openflow sets this automatically as the account event table) and `FACETS_BRONZE.UTILS.APP_CONFIG` for default SQL Server connection info.

---

### 02 — dbt / CI/CD / Time Travel Rollback

**Folder:** `02_dbt/`

**What it shows:** dbt native SCD2 snapshots, stream+task SCD2, CI/CD pipeline with two project objects, Time Travel for data recovery without waiting for a code fix.

#### Background: the intentionally bad code

`caloptima_dw/models/silver/provider_office_hours.sql` has **bad code committed to the dev branch on purpose**:

```sql
-- Active in dev branch:
'Bad Data Inserted Here' AS PROF_DAY_OF_WK,  -- corrupts the day-of-week column
PROF_ID % 2 = 0                               -- only processes half the rows (incremental filter)
```

This bad code is deployed to `CALOPTIMA_DW_DEV` but **never automatically runs** — it is excluded from CI and all scheduled tasks via `--exclude provider_office_hours`. The only time it runs is when you manually trigger it during Step 2 of the rollback demo.

#### `execute_pre_demo/`

`reset_office_hours_clean.sql` — called by the master reset script. Rebuilds `FACETS_DEV.SILVER.PROVIDER_OFFICE_HOURS` directly from staging using `CREATE OR REPLACE TABLE`, bypassing dbt entirely. Gives the demo a clean baseline. dbt has no internal table ownership metadata — it just checks if the table exists — so this is safe.

#### `execute_demo/` — run during the demo

| File | Demo |
|---|---|
| `00_cicd_rollback_demo.sql` | **CI/CD Time Travel rollback.** 6-step flow below. |
| `01_scd2_provider_demo.sql` | Queries `PROVIDER_SNAPSHOT` (dbt native SCD2) and `PROVIDER_SCD2_VIA_STREAM` (stream+task) side by side. Shows version history, current-only filter, point-in-time queries. |
| `02_provider_scd2_stream_task.sql` | Reference/one-time: creates the Stream+Task SCD2 pipeline manually. Use `03_rebuild_provider_scd2_pipeline.sql` instead to rebuild cleanly. |

#### CI/CD rollback demo flow (`00_cicd_rollback_demo.sql`)

```
Step 1: SELECT — show clean data (7 days of the week, no 'Bad Data Inserted Here')
Step 2: EXECUTE DBT PROJECT ANALYTICS_ADMIN.PROJECTS.CALOPTIMA_DW_DEV
        ARGS = 'run --select provider_office_hours --target dev'
        SET bad_run_id = LAST_QUERY_ID();    ← capture immediately
Step 3: SELECT — show ~1,981 rows corrupted with 'Bad Data Inserted Here'
Step 4: CREATE TABLE ... CLONE ... BEFORE (STATEMENT => $bad_run_id)   ← Time Travel
Step 5: SELECT restore table — confirm 7 days back, no bad data
Step 6: ALTER TABLE ... SWAP WITH ...   ← atomic, zero downtime
Step 7: SELECT — confirm production is clean
```

Key talking point: data recovery (Steps 3-6) and code recovery (reverting the bad PR) are completely independent. The table is restored before the code review even starts. The Silver table is never down.

#### `one_time_execute/`

| File | Purpose |
|---|---|
| `01_database_schema_setup.sql` | Creates all FACETS_DEV/QA/PROD databases + schemas. Run once before first dbt build. |
| `02_github_actions_setup.sql` | Network policy for GitHub Actions IPs. Run once. |
| `03_rebuild_provider_scd2_pipeline.sql` | Deploys + runs `SP_REBUILD_PROVIDER_SCD2_PIPELINE`. Rebuilds all streams, SCD2 tables, sprocs, and tasks for DEV/QA/PROD. Has dry-run mode. |
| `04_rebuild_dbt_tasks.sql` | Creates/recreates `DBT_REFRESH_TASK_DEV/QA/PROD` chained after stream tasks. |
| `99_dbt_projects_and_environments.md` | Architecture reference: two-project-object pattern, task chain DAG, deploy commands. |
| `99_reset_scd2_tables.md` | Step-by-step guide to wiping and rebuilding both SCD2 implementations. |

---

### 03 — Cortex Agent

**Folder:** `03_agent/`

**What it shows:** Cortex Agent answering natural-language questions about the member data via a semantic view.

#### `one_time_execute/`

Run in order: `01_setup.sql` → `02_member_enrollment_view.sql` → `03_semantic_view.sql` → `04_agent.sql`.

#### `execute_demo/`

`QUERIES.md` — sample natural-language questions to ask the agent during the demo.

---

### 04 — Performance & Scale

**Folder:** `04_performance_scale/`

**What it shows:** Warehouse auto-scaling, multi-cluster warehouses for concurrency, workload isolation with separate warehouses per role.

#### `one_time_execute/`

`02_concurrency_setup.sql` — run once. Materializes `TPCH_SF100.LINEITEM` (~600M rows) locally, creates and pre-resumes 100 concurrent user tasks so the concurrency demo fires instantly on demo day.

#### `execute_demo/`

The files map to individual Snowsight worksheet tabs in the workload isolation demo:

| File | Demo tab / persona |
|---|---|
| `01_warehouse_sizing.sql` | Scale-up: resize MEDIUM→XL, watch TPC-H Q1 (600M rows) get faster |
| `02_MCW.sql` / `02_MCW2.sql` | Multi-cluster warehouse: fire 100 concurrent users, show automatic cluster scale-out |
| `03__workload_isolation_setup.sql` | Creates 4 separate warehouses for exec/analyst/finance/ML roles |
| `03_tab1_exec.sql` | Executive persona queries on dedicated `CALOPTIMA_EXEC_WH` |
| `03_tab3_analyst.sql` | Analyst persona on dedicated warehouse |
| `03_tab4_finance.sql` | Finance persona on dedicated warehouse |
| `03_tab5_ml.sql` | ML persona on dedicated warehouse |
| `04_cost_analysis.ipynb` | Cost analysis notebook (13 sections covering warehouse credits, query attribution, spend alerts, resource monitors) |

**Workload isolation talking point:** all 4 personas run simultaneously. A heavy ML training job doesn't slow down the exec dashboard — each warehouse is fully independent.

---

### 05 — Data Quality

**Folder:** `05_data_quality/`

**What it shows:** Snowflake Data Metric Functions (DMFs), expectations with pass/fail thresholds, email alerting on violations, custom healthcare-domain DMFs.

#### `one_time_execute/`

`01_dq_setup.sql` — run once. Creates `zzFACETS_DEV_CLONE` (zero-copy clone of `FACETS_DEV`), email notification integration, 3 custom DMFs, 11 DMF associations on `SILVER.MEMBER`, expectations, and `MEMBER_DQ_ALERT`. Also deploys `INJECT_DIRTY_DATA()` and `CLEAN_DIRTY_DATA()` sprocs for the demo.

Custom DMFs created:
- `invalid_npi_count` — counts providers where NPI is not exactly 10 digits
- `medicaid_missing_bic_count` — counts Medicaid members missing a BIC identifier (cross-column)
- `median_birth_year` — computes median birth year from `MEME_DOB` as a proxy for member age distribution

#### `execute_demo/`

`SKIP_02_dq_demo.sql` — prefixed `SKIP_` because it requires `01_dq_setup.sql` to have run first. Shows: list all DMF associations, query expectation status, inject dirty data with `CALL INJECT_DIRTY_DATA()`, watch violations appear in the monitoring results, view historical trend.

---

### 06 — Governance

**Folder:** `06_governance_demo/`

**What it shows:** AI-powered data classification, tag-based dynamic column masking, row-level security by plan type, separation of duties, audit log trail.

#### `one_time_execute/`

`01_governance_setup.sql` (~560 lines) — run once. Creates:
- 3 demo roles: `DATA_ENGINEER_ROLE`, `ANALYTICS_INNOVATOR_ROLE`, `BUSINESS_ANALYST_ROLE`
- `zFACETS_DEV_CLONE` (zero-copy clone) for the demo
- `CALOPTIMA_CLASSIFICATION_PROFILE` with auto-tag enabled
- Tag `DATA_CLASSIFICATION` with 5 values (PII/RESTRICTED/SENSITIVE/INTERNAL/PUBLIC)
- 3 masking policies using `phi_full_access()` UDF as the single privilege-check source
- Row access policy `MEMBER_PLAN_ACCESS_POLICY`: DATA_ENGINEER sees all, ANALYTICS_INNOVATOR sees COMM+DSNP, BUSINESS_ANALYST sees COMM only
- Pre-materialized `ACCOUNT_ACCESS_HISTORY` audit table (90-day snapshot)

#### `execute_pre_demo/`

`01_restore_ba_access.sql` — re-grants `BUSINESS_ANALYST_ROLE` SELECT on `zFACETS_DEV_CLONE.SILVER.MEMBER`. Called automatically by the master reset script.

#### `execute_demo/`

| File | Demo |
|---|---|
| `02_discovery_demo.ipynb` | Primary demo vehicle: shows classification results, tag assignments, column masking by role, row-level filtering by plan type |
| `03_security_demo.ipynb` | Separation of duties: Business Analyst creates their own schema and works in it; blocked from modifying Silver. Part 2: REVOKE access instantly. Part 3: Audit log from `ACCOUNT_ACCESS_HISTORY`. |

---

## 6. Database Map

| Database | Managed by | Purpose |
|---|---|---|
| `FACETS_BRONZE` | Openflow | CDC landing zone for all 36 Facets tables. `UTILS` schema holds all sprocs, tasks, alerts. |
| `FACETS_DEV` | dbt (dev target) | Active dev Silver/Gold/Staging/DQ. Used in all demos. |
| `FACETS_QA` | dbt (qa target) | Pre-merge validation gate. |
| `FACETS_PROD` | dbt (prod target) | Stable production. Main branch code only. |
| `ANALYTICS_ADMIN.PROJECTS` | Snowflake native dbt | Hosts `CALOPTIMA_DW` (main) and `CALOPTIMA_DW_DEV` (dev) project objects. |
| `INGEST_DEMO` | Flat file demo | Pharmacy claims + medical claims tables. |
| `GOVERNANCE_CA_DEMO` | Governance setup | Masking policy definitions, row access policy, `PHI_FULL_ACCESS` UDF. |
| `zFACETS_DEV_CLONE` | Clone of `FACETS_DEV` | Governance demo (classification, masking, row access). Single `z`. |
| `zzFACETS_DEV_CLONE` | Clone of `FACETS_DEV` | Data quality demo (DMFs, expectations, alerts). Double `zz`. |
| `SNOWFLAKE_SAMPLE_DATA2` | Performance setup | Local materialization of `TPCH_SF100.LINEITEM` (600M rows). |
| `DEMO_DEPLOY.GIT` | Pre-demo reset | Git repository object pointing at this GitHub repo. |
| `OPENFLOW.TELEMETRY` | Openflow | CDC telemetry events consumed by the Streamlit observability app. |

---

## 7. Task & Alert Pipeline

```
FACETS_INCREMENTAL_TASK   (FACETS_BRONZE.UTILS, 15 min schedule)
   Calls FACETS_INCREMENTAL_LOAD — synthetic CDC DML across 35 tables
        │
        ├─► DBT_REFRESH_TASK_DEV   (after PROVIDER_SCD2_STREAM_TASK_DEV)
        │       EXECUTE DBT PROJECT CALOPTIMA_DW_DEV --target dev → FACETS_DEV
        │
        ├─► DBT_REFRESH_TASK_QA    (after PROVIDER_SCD2_STREAM_TASK_QA)
        │       EXECUTE DBT PROJECT CALOPTIMA_DW --target qa → FACETS_QA
        │
        └─► DBT_REFRESH_TASK_PROD  (after PROVIDER_SCD2_STREAM_TASK_PROD)
                EXECUTE DBT PROJECT CALOPTIMA_DW --target prod → FACETS_PROD

PROVIDER_SCD2_STREAM_TASK_DEV   (triggered: fires when PRPR_PROV_CHANGE_STREAM has data)
   Calls SP_PROVIDER_SCD2_STREAM_REFRESH → writes FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM

PROVIDER_SCD2_STREAM_TASK_QA    (triggered: PRPR_PROV_CHANGE_STREAM_QA → FACETS_QA)
PROVIDER_SCD2_STREAM_TASK_PROD  (triggered: PRPR_PROV_CHANGE_STREAM_PROD → FACETS_PROD)

FACETS_LATENCY_TASK   (FACETS_BRONZE.UTILS, 15 min, standalone)
   Emails t.jones@snowflake.com if any Bronze table is >15 min behind Azure SQL

DAILY_SPEND_ALERT     (FACETS_BRONZE.UTILS, daily 8am PT)
   Emails if daily credit consumption > 50 credits

MEMBER_DQ_ALERT       (ZZFACETS_DEV_CLONE.SILVER, every 5 min)
   Emails if any DMF expectation on SILVER.MEMBER is violated
```

All tasks and alerts can be found in `FACETS_BRONZE.UTILS` (except `MEMBER_DQ_ALERT` which lives in `ZZFACETS_DEV_CLONE.SILVER`).

---

## 8. dbt Project Structure

**Location:** `caloptima_dw/`

```
caloptima_dw/
├── dbt_project.yml        Materialization rules + schema names per layer
├── profiles.yml           Three targets: dev → FACETS_DEV, qa → FACETS_QA, prod → FACETS_PROD
├── packages.yml           dbt package dependencies
├── snapshots/
│   └── provider_snapshot.sql   dbt native SCD2 on stg_prpr_prov
├── tests/                 Custom singular tests (SQL assertions)
├── macros/
│   ├── generate_schema_name.sql   Overrides dbt default schema naming
│   └── active_records.sql         Helper macro for _SNOWFLAKE_DELETED filter
├── analysis/              Reference SQL (task DDL, latency queries — not dbt models)
└── models/
    ├── sources.yml         Declares FACETS_BRONZE.RAW.* as dbt sources
    ├── staging/            Views over Bronze. Light cleaning + Openflow metadata forwarding.
    ├── intermediate/       Ephemeral (no Snowflake objects — compiled as CTEs into Silver)
    ├── silver/             Incremental tables (merge strategy)
    ├── gold/               Views for analytics consumers
    └── ops/                Tables for pipeline observability (row counts, dup metrics)
```

#### Materialization by layer

| Layer | Materialization | Creates Snowflake object? |
|---|---|---|
| Staging | View | Yes |
| Intermediate | Ephemeral | No — compiled as CTEs into Silver |
| Silver | Incremental table | Yes |
| Gold | View | Yes |
| Ops | Table | Yes |
| Snapshots | Table (in SILVER schema) | Yes |

Intermediate models exist in the dbt DAG for code clarity but produce no Snowflake objects. Column lineage in Snowflake's native lineage graph shows Bronze → Staging → Silver → Gold directly (intermediates are absorbed into the Silver MERGE statement).

#### Schema tests

Four test types are attached across all models in `schema.yml`:
- `not_null` — on every primary key and critical column
- `unique` — on surrogate keys and natural PKs
- `accepted_values` — on decoded fields (e.g., `PROVIDER_TYPE` must be one of `['Individual (Type 1)', 'Organization (Type 2)', 'Unknown']`)
- `relationships` — Silver FKs must resolve to Bronze source rows

#### Unit tests

Two dbt unit tests in `models/staging/schema.yml` validate transformation logic against mock data (no database required):
- `test_provider_entity_decode` — `PRPR_ENTITY = 'I'/'O'` correctly decoded to `PROVIDER_TYPE`
- `test_npi_validation_flag` — non-10-digit and non-numeric NPIs produce `NPI_VALID = false`

---

## 9. Key Stored Procedures Reference

| Procedure | Schema | Language | Purpose |
|---|---|---|---|
| `FACETS_INITIAL_LOAD` | `FACETS_BRONZE.UTILS` | Python | Seeds all 35 Azure SQL tables with synthetic Facets data |
| `FACETS_INCREMENTAL_LOAD` | `FACETS_BRONZE.UTILS` | Python | Tier-weighted incremental DML (CDC simulation) |
| `FACETS_ROW_COUNT_VALIDATION` | `FACETS_BRONZE.UTILS` | Python | Compares Azure SQL vs Bronze row counts for all 36 tables |
| `FACETS_LATENCY_CHECK` | `FACETS_BRONZE.UTILS` | Python | Checks replication lag and sends HTML email alert |
| `FACETS_AZURE_SQL_CONNECTION_TEST` | `FACETS_BRONZE.UTILS` | Python | Verifies Snowflake → Azure SQL connectivity |
| `OPENFLOW_SCHEMA_REVERT_MSSQL` | `FACETS_BRONZE.UTILS` | Python | Idempotent reset of Azure SQL schema drift demo state |
| `DROP_PRTP_JOURNAL_TABLES` | `FACETS_BRONZE.UTILS` | Python | Drops all `CMC_PRTP_PROV_TYPE%JOURNAL%` tables from Bronze |
| `SP_REBUILD_PROVIDER_SCD2_PIPELINE` | `FACETS_BRONZE.UTILS` | SQL | Rebuilds streams, SCD2 tables, sprocs, and tasks for all 3 envs |
| `SP_PROVIDER_SCD2_STREAM_REFRESH` | `FACETS_DEV/QA/PROD.SILVER` | SQL | Processes stream changes into `PROVIDER_SCD2_VIA_STREAM` |
| `INJECT_DIRTY_DATA` | `ZZFACETS_DEV_CLONE.SILVER` | SQL | Seeds DQ violations into SILVER.MEMBER for the demo |
| `CLEAN_DIRTY_DATA` | `ZZFACETS_DEV_CLONE.SILVER` | SQL | Cleans injected violations |

All Python sprocs use `pytds` (pure-Python TDS driver) for Azure SQL connectivity via `AZURE_SQL_FACETS_EAI` External Access Integration and `FACETS_SQL_CREDS` secret.

---

## 10. File Naming Conventions

| Pattern | Meaning |
|---|---|
| `one_time_execute/` folder | Run once to build infrastructure. Safe to re-run for rebuilds, but don't run casually. |
| `execute_pre_demo/` folder | Run before every demo. Handled automatically by `one_time_pre_demo_snow.sql`. |
| `execute_demo/` folder | Run during the live demo. |
| `z_legacy_ignore/` folder | Deprecated scripts. Superseded by current files. Do not run. Excluded from git. |
| `SKIP_` file prefix | Requires a prerequisite setup file to have run first. Not standalone. |
| `NA_now_` file prefix | Previously active, now retired and replaced. |
| `zz_` folder prefix | Data files only (CSVs, XMLs). Not executable scripts. |
| `99_` file prefix | Reference documentation (Markdown). Not executable SQL. |
| `z_ad_hoc/` folder | Ad-hoc development queries. Not part of the demo flow. |
