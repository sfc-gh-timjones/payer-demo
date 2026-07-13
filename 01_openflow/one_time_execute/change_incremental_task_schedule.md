# Changing the Openflow Incremental Task Schedule

`FACETS_INCREMENTAL_TASK` is the root task that drives the entire pipeline:

```
FACETS_INCREMENTAL_TASK  (scheduled, root)
  └─ DBT_REFRESH_TASK_DEV
       └─ DBT_REFRESH_TASK_QA
            └─ DBT_REFRESH_TASK_PROD
                 └─ PROVIDER_SCD2_STREAM_TASK
```

All downstream tasks fire as a chain after each incremental load completes.
Changing the schedule on this root task controls how frequently the entire
pipeline runs end-to-end.

---

## Does the task need to be suspended first?

**Yes.** Snowflake requires a root task to be **suspended before `ALTER TASK ... SET SCHEDULE`**.
Child tasks (those with `AFTER` predecessors) do not require suspension for schedule changes —
but this task has no predecessor, so it is the root and must be suspended.

> Child tasks in the chain (`DBT_REFRESH_TASK_DEV`, etc.) do **not** need to be suspended
> when only changing the root task's schedule.

---

## How to change the schedule

```sql
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WH_XS;

-- Step 1: Suspend the root task
ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK SUSPEND;

-- Step 2: Set the new schedule (replace interval below)
ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK
    SET SCHEDULE = '45 MINUTE';   -- ← change this value

-- Step 3: Resume
ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK RESUME;

-- Verify
SHOW TASKS LIKE 'FACETS_INCREMENTAL_TASK' IN SCHEMA FACETS_BRONZE.UTILS;
```

---

## Schedule reference

| Frequency | `SET SCHEDULE` value |
|---|---|
| Every 5 minutes | `'5 MINUTE'` |
| Every 10 minutes | `'10 MINUTE'` |
| Every 15 minutes | `'15 MINUTE'` |
| Every 30 minutes | `'30 MINUTE'` |
| Every 45 minutes | `'45 MINUTE'` ← current |
| Every 60 minutes | `'60 MINUTE'` |

You can also use a cron expression for exact clock-time scheduling:

```sql
-- Example: run at :00 and :30 of every hour (Mountain Time)
ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK
    SET SCHEDULE = 'USING CRON 0,30 * * * * America/Denver';
```

---

## Copy-paste blocks for common intervals

**30 minutes**
```sql
ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK SUSPEND;
ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK SET SCHEDULE = '30 MINUTE';
ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK RESUME;
```

**15 minutes**
```sql
ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK SUSPEND;
ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK SET SCHEDULE = '15 MINUTE';
ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK RESUME;
```

**10 minutes**
```sql
ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK SUSPEND;
ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK SET SCHEDULE = '10 MINUTE';
ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK RESUME;
```

**5 minutes**
```sql
ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK SUSPEND;
ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK SET SCHEDULE = '5 MINUTE';
ALTER TASK FACETS_BRONZE.UTILS.FACETS_INCREMENTAL_TASK RESUME;
```

---

## Check task history after changing schedule

```sql
SELECT
    NAME,
    STATE,
    SCHEDULED_TIME,
    COMPLETED_TIME,
    DATEDIFF('second', SCHEDULED_TIME, COMPLETED_TIME) AS duration_sec,
    ERROR_CODE,
    ERROR_MESSAGE
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('hour', -2, CURRENT_TIMESTAMP()),
    TASK_NAME => 'FACETS_INCREMENTAL_TASK'
))
ORDER BY SCHEDULED_TIME DESC
LIMIT 10;
```

---

## Notes

- **Credit usage**: tasks only consume credits when they execute, not while suspended or waiting.
  Running at 5-minute intervals costs 12x more than hourly — use shorter intervals for demos only.
- **Minimum interval**: Snowflake's minimum task schedule is `1 MINUTE`.
- **NO_OVERLAP policy**: `FACETS_INCREMENTAL_TASK` has `OVERLAP_POLICY = NO_OVERLAP`, so if a
  run is still executing when the next interval fires, the scheduled run is skipped (not queued).
  At shorter intervals, confirm the Openflow load completes faster than the interval.
