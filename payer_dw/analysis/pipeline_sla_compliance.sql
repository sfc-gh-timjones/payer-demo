-- 30-day CDC task run history with SLA compliance (15-minute target).
CREATE OR REPLACE VIEW FACETS_BRONZE.UTILS.PIPELINE_SLA_COMPLIANCE AS
SELECT
    DATE_TRUNC('day', SCHEDULED_TIME)               AS run_date,
    COUNT(*)                                        AS total_runs,
    SUM(
        CASE WHEN DATEDIFF('minute', SCHEDULED_TIME, COMPLETED_TIME) <= 15
        THEN 1 ELSE 0 END
    )                                               AS within_sla,
    ROUND(
        100.0
        * SUM(CASE WHEN DATEDIFF('minute', SCHEDULED_TIME, COMPLETED_TIME) <= 15 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0), 1
    )                                               AS sla_pct,
    AVG(DATEDIFF('minute', SCHEDULED_TIME, COMPLETED_TIME)) AS avg_duration_min,
    MAX(DATEDIFF('minute', SCHEDULED_TIME, COMPLETED_TIME)) AS max_duration_min
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('day', -30, CURRENT_TIMESTAMP())
))
WHERE NAME = 'FACETS_INCREMENTAL_TASK'
  AND STATE IN ('SUCCEEDED', 'FAILED')
GROUP BY 1
ORDER BY 1 DESC;
