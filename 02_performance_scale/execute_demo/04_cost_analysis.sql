-- =============================================================================
-- FILE:    04_cost_analysis.sql
-- PURPOSE: Cost & consumption governance demo
--          Source: SNOWFLAKE.ACCOUNT_USAGE (45-min latency)
--          Covers: warehouse spend, query attribution, user/role cost,
--                  storage, serverless, trends, budgets, resource monitors
-- NOTE:    ACCOUNT_USAGE requires ACCOUNTADMIN or SNOWFLAKE database grants
-- =============================================================================

USE ROLE      ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;   -- adjust to your warehouse
USE DATABASE  SNOWFLAKE;


/* ============================================================================
   SECTION 1 — EXECUTIVE SUMMARY
   Total credits consumed this month across all service types
   ============================================================================ */

SELECT
    SERVICE_TYPE,
    ROUND(SUM(CREDITS_USED), 2)             AS total_credits,
    ROUND(SUM(CREDITS_USED_COMPUTE), 2)     AS compute_credits,
    ROUND(SUM(CREDITS_USED_CLOUD_SERVICES), 2) AS cloud_svc_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE START_TIME >= DATE_TRUNC('month', CURRENT_DATE())
GROUP BY SERVICE_TYPE
ORDER BY total_credits DESC;


/* ============================================================================
   SECTION 2 — CREDITS BY WAREHOUSE (last 30 days)
   Identifies which warehouses are driving the most spend
   ============================================================================ */

SELECT
    WAREHOUSE_NAME,
    ROUND(SUM(CREDITS_USED), 2)              AS total_credits,
    ROUND(SUM(CREDITS_USED_COMPUTE), 2)      AS compute_credits,
    ROUND(SUM(CREDITS_USED_CLOUD_SERVICES), 2) AS cloud_svc_credits,
    COUNT(*)                                  AS billing_periods,
    MIN(START_TIME)::DATE                     AS first_active,
    MAX(START_TIME)::DATE                     AS last_active
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY WAREHOUSE_NAME
ORDER BY total_credits DESC;


/* ============================================================================
   SECTION 3 — MOST EXPENSIVE QUERIES (Query Attribution)
   QUERY_ATTRIBUTION_HISTORY attributes credits to individual queries.
   This is the most accurate view for pinpointing costly SQL.
   ============================================================================ */

SELECT
    QA.QUERY_ID,
    QH.QUERY_TEXT,
    QH.USER_NAME,
    QH.ROLE_NAME,
    QH.WAREHOUSE_NAME,
    QH.DATABASE_NAME,
    QH.SCHEMA_NAME,
    ROUND(QA.CREDITS_ATTRIBUTED_COMPUTE, 6) AS credits_attributed,
    QH.EXECUTION_TIME / 1000                AS execution_secs,
    QH.BYTES_SCANNED / 1e9                  AS gb_scanned,
    QH.QUERY_START_TIME::DATE               AS query_date
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY QA
JOIN SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY             QH
    ON QA.QUERY_ID = QH.QUERY_ID
WHERE QA.QUERY_START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND QA.CREDITS_ATTRIBUTED_COMPUTE > 0
ORDER BY credits_attributed DESC
LIMIT 25;


/* ============================================================================
   SECTION 4 — MOST EXPENSIVE USERS (last 30 days)
   Ranks users by total compute credits their queries consumed
   ============================================================================ */

SELECT
    QH.USER_NAME,
    COUNT(DISTINCT QH.QUERY_ID)              AS query_count,
    ROUND(SUM(QA.CREDITS_ATTRIBUTED_COMPUTE), 4) AS total_credits,
    ROUND(AVG(QA.CREDITS_ATTRIBUTED_COMPUTE), 6) AS avg_credits_per_query,
    ROUND(MAX(QA.CREDITS_ATTRIBUTED_COMPUTE), 6) AS max_single_query,
    ROUND(SUM(QH.BYTES_SCANNED) / 1e12, 3)  AS tb_scanned
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY QA
JOIN SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY             QH
    ON QA.QUERY_ID = QH.QUERY_ID
WHERE QA.QUERY_START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY QH.USER_NAME
ORDER BY total_credits DESC
LIMIT 20;


/* ============================================================================
   SECTION 5 — MOST EXPENSIVE ROLES (last 30 days)
   Useful for chargeback / cost allocation by team or function
   ============================================================================ */

SELECT
    QH.ROLE_NAME,
    COUNT(DISTINCT QH.USER_NAME)             AS distinct_users,
    COUNT(DISTINCT QH.QUERY_ID)              AS query_count,
    ROUND(SUM(QA.CREDITS_ATTRIBUTED_COMPUTE), 4) AS total_credits,
    ROUND(AVG(QA.CREDITS_ATTRIBUTED_COMPUTE), 6) AS avg_credits_per_query,
    ROUND(SUM(QH.BYTES_SCANNED) / 1e12, 3)  AS tb_scanned
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY QA
JOIN SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY             QH
    ON QA.QUERY_ID = QH.QUERY_ID
WHERE QA.QUERY_START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY QH.ROLE_NAME
ORDER BY total_credits DESC
LIMIT 20;


/* ============================================================================
   SECTION 6 — STORAGE COSTS (last 30 days)
   Database-level storage broken into active, time travel, and fail-safe
   ============================================================================ */

SELECT
    DATABASE_NAME,
    ROUND(AVG(AVERAGE_DATABASE_BYTES)      / 1e9, 2) AS avg_active_gb,
    ROUND(AVG(AVERAGE_FAILSAFE_BYTES)      / 1e9, 2) AS avg_failsafe_gb,
    ROUND(AVG(AVERAGE_DATABASE_BYTES + AVERAGE_FAILSAFE_BYTES) / 1e9, 2) AS avg_total_gb,
    MAX(USAGE_DATE)                                   AS last_recorded
FROM SNOWFLAKE.ACCOUNT_USAGE.DATABASE_STORAGE_USAGE_HISTORY
WHERE USAGE_DATE >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY DATABASE_NAME
ORDER BY avg_total_gb DESC;


/* ============================================================================
   SECTION 7 — SERVERLESS & PIPELINE SERVICE COSTS (last 30 days)
   Covers auto-clustering, search optimization, Snowpipe, tasks, replication
   ============================================================================ */

-- Serverless tasks
SELECT 'SERVERLESS_TASK' AS service, ROUND(SUM(CREDITS_USED), 4) AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.SERVERLESS_TASK_HISTORY
WHERE START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())

UNION ALL

-- Snowpipe
SELECT 'SNOWPIPE', ROUND(SUM(CREDITS_USED), 4)
FROM SNOWFLAKE.ACCOUNT_USAGE.PIPE_USAGE_HISTORY
WHERE START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())

UNION ALL

-- Auto-clustering
SELECT 'AUTO_CLUSTERING', ROUND(SUM(CREDITS_USED), 4)
FROM SNOWFLAKE.ACCOUNT_USAGE.AUTOMATIC_CLUSTERING_HISTORY
WHERE START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())

UNION ALL

-- Search optimization
SELECT 'SEARCH_OPTIMIZATION', ROUND(SUM(CREDITS_USED), 4)
FROM SNOWFLAKE.ACCOUNT_USAGE.SEARCH_OPTIMIZATION_HISTORY
WHERE START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())

UNION ALL

-- Replication
SELECT 'REPLICATION', ROUND(SUM(CREDITS_USED), 4)
FROM SNOWFLAKE.ACCOUNT_USAGE.REPLICATION_GROUP_USAGE_HISTORY
WHERE START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())

ORDER BY credits DESC;


/* ============================================================================
   SECTION 8 — DAILY CREDIT TREND (last 30 days)
   Rolling spend by day — useful for spotting anomalies or growth trends
   ============================================================================ */

SELECT
    DATE_TRUNC('day', START_TIME)::DATE     AS usage_date,
    ROUND(SUM(CREDITS_USED_COMPUTE), 2)     AS compute_credits,
    ROUND(SUM(CREDITS_USED_CLOUD_SERVICES), 2) AS cloud_svc_credits,
    ROUND(SUM(CREDITS_USED), 2)             AS total_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY usage_date
ORDER BY usage_date;


/* ============================================================================
   SECTION 9 — TOP TABLES BY QUERY FREQUENCY (last 7 days)
   Surfaces the hottest tables — cost + performance tuning candidates
   ============================================================================ */

SELECT
    BASE_OBJECTS_ACCESSED[0]:objectName::VARCHAR  AS table_name,
    COUNT(*)                                       AS query_count,
    COUNT(DISTINCT USER_NAME)                      AS distinct_users,
    ROUND(SUM(BYTES_SCANNED) / 1e9, 2)            AS total_gb_scanned,
    ROUND(AVG(EXECUTION_TIME) / 1000, 1)          AS avg_exec_secs
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE QUERY_START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
  AND EXECUTION_STATUS = 'SUCCESS'
  AND ARRAY_SIZE(BASE_OBJECTS_ACCESSED) > 0
GROUP BY table_name
ORDER BY query_count DESC
LIMIT 20;


/* ============================================================================
   SECTION 10 — BUDGET SETUP (Snowflake Budgets — Business Critical+)
   Creates an account-level budget with email notification at 50% and 90%.
   Snowflake Budgets track credit spend against a defined monthly limit.

   NOTE: Requires ACCOUNTADMIN and Business Critical or higher edition.
         Notification integration must exist before running.
   ============================================================================ */

-- Step 1: Create a notification integration (email)
CREATE NOTIFICATION INTEGRATION IF NOT EXISTS BUDGET_EMAIL_INTEGRATION
    TYPE = EMAIL
    ENABLED = TRUE;

-- Step 2: Create an account-level budget (e.g., 1000 credits/month)
CREATE BUDGET IF NOT EXISTS SNOWFLAKE.LOCAL.CALOPTIMA_ACCOUNT_BUDGET
    CREDIT_QUOTA = 1000                              -- adjust to your contract
    NOTIFY (
        THRESHOLD = 50 PERCENT NOTIFY (INTEGRATION = BUDGET_EMAIL_INTEGRATION),
        THRESHOLD = 90 PERCENT NOTIFY (INTEGRATION = BUDGET_EMAIL_INTEGRATION)
    );

-- Step 3: Check current budget status
SELECT *
FROM TABLE(SNOWFLAKE.LOCAL.GET_BUDGET_ALLOWANCE(
    BUDGET_NAME => 'SNOWFLAKE.LOCAL.CALOPTIMA_ACCOUNT_BUDGET'
));


/* ============================================================================
   SECTION 11 — RESOURCE MONITORS (Warehouse-level spend control)
   Resource monitors hard-stop warehouses when credit thresholds are hit.
   This is the most direct spend-control tool in Snowflake.

   NOTIFY  = send alert but keep running
   SUSPEND = suspend warehouse (in-flight queries finish)
   SUSPEND_IMMEDIATE = kill all queries, suspend now
   ============================================================================ */

-- Monthly resource monitor: warn at 80%, suspend at 100%, hard-stop at 110%
CREATE OR REPLACE RESOURCE MONITOR CALOPTIMA_MONTHLY_MONITOR
    WITH
        CREDIT_QUOTA   = 500               -- monthly credit limit; adjust as needed
        FREQUENCY      = MONTHLY
        START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 80  PERCENT DO NOTIFY
        ON 100 PERCENT DO SUSPEND
        ON 110 PERCENT DO SUSPEND_IMMEDIATE;

-- Attach monitor to your primary compute warehouse
ALTER WAREHOUSE COMPUTE_WH
    SET RESOURCE_MONITOR = CALOPTIMA_MONTHLY_MONITOR;

-- View all resource monitors and their current consumption
SHOW RESOURCE MONITORS;


/* ============================================================================
   SECTION 12 — CUSTOM SPEND ALERT (real-time, Snowflake Alert)
   Fires when yesterday's credits exceed a daily threshold.
   ACCOUNT_USAGE has 45-min latency — pair with METERING_DAILY_HISTORY
   for near-real-time daily signals.
   ============================================================================ */

CREATE OR REPLACE ALERT SNOWFLAKE.LOCAL.DAILY_SPEND_ALERT
    WAREHOUSE = COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 8 * * * America/Los_Angeles'   -- 8am daily check
    IF (
        EXISTS (
            SELECT 1
            FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
            WHERE USAGE_DATE = CURRENT_DATE() - 1
            HAVING SUM(CREDITS_USED) > 50                    -- alert if >50 credits yesterday
        )
    )
    THEN
        CALL SYSTEM$SEND_EMAIL(
            'BUDGET_EMAIL_INTEGRATION',
            'caloptima-snowflake-alerts@caloptima.org',       -- adjust recipient
            'Snowflake Daily Spend Alert',
            'Yesterday''s Snowflake credit consumption exceeded the 50-credit daily threshold. '
            || 'Log in to Snowsight → Admin → Cost Management to review.'
        );

ALTER ALERT SNOWFLAKE.LOCAL.DAILY_SPEND_ALERT RESUME;


/* ============================================================================
   SECTION 13 — VERIFY: CURRENT RESOURCE MONITOR STATUS
   Quick check to confirm monitors and alerts are active
   ============================================================================ */

SHOW RESOURCE MONITORS;

SHOW ALERTS LIKE 'DAILY_SPEND_ALERT%' IN SCHEMA SNOWFLAKE.LOCAL;

-- Current spend against all active resource monitors
SELECT
    NAME,
    CREDIT_QUOTA,
    CREDITS_USED,
    ROUND(CREDITS_USED / CREDIT_QUOTA * 100, 1) AS pct_used,
    FREQUENCY,
    START_TIME,
    END_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.RESOURCE_MONITORS
ORDER BY pct_used DESC NULLS LAST;
