# Reset SCD2 Tables: Snapshot + Stream/Task

Use this guide to wipe and rebuild both SCD2 implementations from a clean baseline:

| Table | Approach | Targets |
|---|---|---|
| `SILVER.PROVIDER_SNAPSHOT` | DROP TABLE manually + `dbt snapshot` | FACETS_DEV, FACETS_QA, FACETS_PROD |
| `FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM` | Drop + recreate stream + initial load | FACETS_DEV only |

**Why reset both at the same time**: both tables source from `FACETS_BRONZE.RAW.CMC_PRPR_PROV`.
Running them back-to-back while tasks are suspended ensures they start from the same Bronze state
and avoid any drift from Openflow writing new records mid-reset.

---

## Step 1 — Suspend the full task chain

Suspend root-to-leaf so no task fires mid-reset.

```sql
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WH_XS;

-- Suspend root first (stops the schedule)
ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK  SUSPEND;

-- Suspend downstream chain
ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_DEV     SUSPEND;
ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_QA      SUSPEND;
ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_PROD    SUSPEND;
ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK SUSPEND;

-- Confirm all suspended
SHOW TASKS IN SCHEMA FACETS_BRONZE.UTILS;
```

---

## Step 2 — Reset the dbt snapshot (all three targets)

`dbt snapshot --full-refresh` does **not** exist in dbt v1.9 — the subcommand never accepted that flag.
The only way to force a full rebuild is to drop the tables manually first, then run `dbt snapshot`.

Drop all three snapshot tables, then rebuild each target in order.
Wait for each `EXECUTE DBT PROJECT` to complete before running the next.

```sql
-- Drop snapshot tables in all three databases
DROP TABLE IF EXISTS FACETS_DEV.SILVER.PROVIDER_SNAPSHOT;
DROP TABLE IF EXISTS FACETS_QA.SILVER.PROVIDER_SNAPSHOT;
DROP TABLE IF EXISTS FACETS_PROD.SILVER.PROVIDER_SNAPSHOT;

-- DEV target  →  FACETS_DEV.SILVER.PROVIDER_SNAPSHOT
EXECUTE DBT PROJECT ANALYTICS_ADMIN.PROJECTS.CALOPTIMA_DW_DEV
    ARGS = 'snapshot --target dev --select provider_snapshot';

-- QA target   →  FACETS_QA.SILVER.PROVIDER_SNAPSHOT
EXECUTE DBT PROJECT ANALYTICS_ADMIN.PROJECTS.CALOPTIMA_DW
    ARGS = 'snapshot --target qa --select provider_snapshot';

-- PROD target →  FACETS_PROD.SILVER.PROVIDER_SNAPSHOT
EXECUTE DBT PROJECT ANALYTICS_ADMIN.PROJECTS.CALOPTIMA_DW
    ARGS = 'snapshot --target prod --select provider_snapshot';
```

Verify each snapshot rebuilt cleanly (all rows should be current, no historical versions):

```sql
SELECT 'DEV'  AS env, COUNT(*) AS total, SUM(CASE WHEN dbt_valid_to IS NULL THEN 1 ELSE 0 END) AS current_rows FROM FACETS_DEV.SILVER.PROVIDER_SNAPSHOT  UNION ALL
SELECT 'QA'   AS env, COUNT(*) AS total, SUM(CASE WHEN dbt_valid_to IS NULL THEN 1 ELSE 0 END) AS current_rows FROM FACETS_QA.SILVER.PROVIDER_SNAPSHOT   UNION ALL
SELECT 'PROD' AS env, COUNT(*) AS total, SUM(CASE WHEN dbt_valid_to IS NULL THEN 1 ELSE 0 END) AS current_rows FROM FACETS_PROD.SILVER.PROVIDER_SNAPSHOT
ORDER BY env;
-- Expected: total = current_rows for all three (no historical rows on a fresh rebuild)
```

---

## Step 3 — Reset the stream CDC offset

Recreating the stream resets its offset to the current position in the Bronze table's
change log. Any Bronze changes that occurred before this point are discarded — the
subsequent initial load (Step 4) captures current state instead.

```sql
-- Drop and recreate stream to reset CDC offset to NOW
CREATE OR REPLACE STREAM FACETS_BRONZE.UTILS.PRPR_PROV_CHANGE_STREAM
    ON TABLE FACETS_BRONZE.RAW.CMC_PRPR_PROV
    APPEND_ONLY       = FALSE
    SHOW_INITIAL_ROWS = FALSE
    COMMENT           = 'CDC stream on CMC_PRPR_PROV for SCD2 pipeline into SILVER.PROVIDER_SCD2_VIA_STREAM';

-- Confirm stream is empty (offset is fresh)
SELECT SYSTEM$STREAM_HAS_DATA('FACETS_BRONZE.UTILS.PRPR_PROV_CHANGE_STREAM') AS has_data;
-- Expected: FALSE
```

---

## Step 4 — Rebuild the stream/task SCD2 table

Drop and recreate the target table, then seed it with the current Bronze state.
This must run **after** the stream is recreated (Step 3) so the initial load and
the new stream offset are aligned to the same point in time.

```sql
-- Recreate the SCD2 target table (empty)
CREATE OR REPLACE TABLE FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM (
    PROVIDER_SK         VARCHAR        NOT NULL,
    PRPR_ID             NUMBER         NOT NULL,
    PRPR_NPI            VARCHAR,
    PRPR_NAME           VARCHAR,
    PROVIDER_TYPE       VARCHAR,
    PRPR_ENTITY         VARCHAR,
    STATUS_DESC         VARCHAR,
    PRPR_STS            VARCHAR,
    CONTRACT_TYPE       VARCHAR,
    PRPR_MCTR_TYPE      VARCHAR,
    PRPR_TAXONOMY_CD    VARCHAR,
    TERM_DT             DATE,
    IS_DELETED          BOOLEAN        DEFAULT FALSE,
    EFFECTIVE_FROM      TIMESTAMP_NTZ  NOT NULL,
    EFFECTIVE_TO        TIMESTAMP_NTZ,
    IS_CURRENT          BOOLEAN        NOT NULL,
    BRONZE_UPDATED_AT   TIMESTAMP_NTZ,
    SILVER_LOADED_AT    TIMESTAMP_NTZ
);

-- Initial load: seed all current Bronze providers as Version 1
INSERT INTO FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM
SELECT
    MD5(PRPR_ID::VARCHAR || '|' || _SNOWFLAKE_UPDATED_AT::VARCHAR)  AS PROVIDER_SK,
    PRPR_ID,
    PRPR_NPI,
    PRPR_NAME,
    CASE PRPR_ENTITY
        WHEN 'I' THEN 'Individual (Type 1)'
        WHEN 'O' THEN 'Organization (Type 2)'
        ELSE 'Unknown'
    END                                                              AS PROVIDER_TYPE,
    PRPR_ENTITY,
    CASE PRPR_STS
        WHEN 'AC' THEN 'Active'
        WHEN 'IN' THEN 'Inactive'
        WHEN 'SU' THEN 'Suspended'
        ELSE PRPR_STS
    END                                                              AS STATUS_DESC,
    PRPR_STS,
    CASE PRPR_MCTR_TYPE
        WHEN 'FFS'      THEN 'Fee for Service'
        WHEN 'CAP'      THEN 'Capitation'
        WHEN 'PER_DIEM' THEN 'Per Diem'
        ELSE PRPR_MCTR_TYPE
    END                                                              AS CONTRACT_TYPE,
    PRPR_MCTR_TYPE,
    PRPR_TAXONOMY_CD,
    PRPR_TERM_DT                                                     AS TERM_DT,
    _SNOWFLAKE_DELETED                                               AS IS_DELETED,
    _SNOWFLAKE_UPDATED_AT                                            AS EFFECTIVE_FROM,
    NULL::TIMESTAMP_NTZ                                              AS EFFECTIVE_TO,
    TRUE                                                             AS IS_CURRENT,
    _SNOWFLAKE_UPDATED_AT                                            AS BRONZE_UPDATED_AT,
    CURRENT_TIMESTAMP()                                              AS SILVER_LOADED_AT
FROM FACETS_BRONZE.RAW.CMC_PRPR_PROV;
```

---

## Step 5 — Recreate the task

The stream was recreated in Step 3 which invalidates the task's WHEN clause reference.
Recreate and re-chain the task before resuming.

```sql
-- Recreate task (re-links to the new stream)
CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK
    WAREHOUSE = WH_XS
    COMMENT   = 'SCD2 refresh for SILVER.PROVIDER_SCD2_VIA_STREAM when Bronze CMC_PRPR_PROV changes'
    AFTER     FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_PROD
    WHEN      SYSTEM$STREAM_HAS_DATA('FACETS_BRONZE.UTILS.PRPR_PROV_CHANGE_STREAM')
AS
    CALL FACETS_DEV.SILVER.SP_PROVIDER_SCD2_STREAM_REFRESH();
```

> The stored procedure `FACETS_DEV.SILVER.SP_PROVIDER_SCD2_STREAM_REFRESH` does **not**
> need to be recreated — it is stateless and reads from the stream by name.

---

## Step 6 — Resume task chain (leaf → root)

Always resume leaf-to-root so the dependency graph is valid when the root fires.

```sql
ALTER TASK FACETS_BRONZE.UTILS.PROVIDER_SCD2_STREAM_TASK  RESUME;
ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_PROD      RESUME;
ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_QA        RESUME;
ALTER TASK FACETS_BRONZE.UTILS.DBT_REFRESH_TASK_DEV       RESUME;
ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK    RESUME;

-- Confirm all resumed
SHOW TASKS IN SCHEMA FACETS_BRONZE.UTILS;
```

---

## Step 7 — Verify sync between the two tables

Run this after the next hourly task fires (or wait ~5 minutes for the stream task window).

```sql
-- Row counts should match
SELECT
    'dbt snapshot (DEV)' AS approach,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT PRPR_ID) AS distinct_providers
FROM FACETS_DEV.SILVER.PROVIDER_SNAPSHOT WHERE dbt_valid_to IS NULL

UNION ALL

SELECT
    'stream/task' AS approach,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT PRPR_ID) AS distinct_providers
FROM FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM WHERE IS_CURRENT = TRUE

ORDER BY approach;

-- Any current-state attribute mismatches (should be 0 rows after clean reset)
-- Run the full comparison from: 01_openflow/z_ad_hoc/compare_snapshot_vs_stream.sql
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `dbt snapshot --full-refresh` error | Flag does not exist in dbt v1.9 | Use `DROP TABLE` first, then `dbt snapshot` (no flag) |
| Stream still has data after recreate | Ran initial load before recreating stream | Redo Steps 3→4 in order |
| Task fires but snapshot not updating | `--select` comma syntax bug | Verify task uses space-separated selectors (fixed Jul 13 2026) |
| Both tables have different provider counts | Openflow wrote records between Steps 2 and 4 | Normal — next hourly dbt run will catch snapshot up |
