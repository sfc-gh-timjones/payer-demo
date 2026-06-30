-- Alert: fires when FACETS_INCREMENTAL_TASK has not succeeded within 20 minutes.
-- Requires a notification integration (email or webhook) to be pre-created.

-- Step 1: Create an email notification integration (run once as ACCOUNTADMIN)
-- CREATE NOTIFICATION INTEGRATION IF NOT EXISTS CDC_EMAIL_NOTIF
--     TYPE = EMAIL
--     ENABLED = TRUE
--     ALLOWED_RECIPIENTS = ('cdc-alerts@caloptima.org', 't.jones@snowflake.com');

-- Step 2: Create the alert
CREATE OR REPLACE ALERT FACETS_BRONZE.UTILS.CDC_LATENCY_ALERT
    WAREHOUSE  = WH_XS
    SCHEDULE   = '5 MINUTE'
    IF (EXISTS (
        -- Condition: task didn't succeed in the last 20 minutes
        SELECT 1
        FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
            SCHEDULED_TIME_RANGE_START => DATEADD('minute', -20, CURRENT_TIMESTAMP())
        ))
        WHERE NAME  = 'FACETS_INCREMENTAL_TASK'
          AND STATE != 'SUCCEEDED'
    ))
    THEN CALL SYSTEM$SEND_EMAIL(
        'CDC_EMAIL_NOTIF',
        'cdc-alerts@caloptima.org',
        'ALERT: Facets CDC pipeline missed SLA',
        'FACETS_INCREMENTAL_TASK has not completed successfully in the last 20 minutes. '
        || 'Please check TASK_HISTORY in FACETS_BRONZE.UTILS.'
    );

-- Step 3: Resume the alert after creation
-- ALTER ALERT FACETS_BRONZE.UTILS.CDC_LATENCY_ALERT RESUME;
