-- =============================================================================
-- FILE: 00_alert_data_latency.sql
-- PURPOSE: Monitor Openflow replication lag between Azure SQL and FACETS_BRONZE.
--          Queries MAX(SYS_LAST_UPD_DTM) from Azure SQL and MAX(_SNOWFLAKE_UPDATED_AT)
--          from each Bronze table, calculates lag in minutes, and sends an HTML
--          email alert if any table exceeds the threshold.
--
-- MECHANISM: Python stored proc (requires AZURE_SQL_FACETS_EAI to query Azure side)
--            + Snowflake Task scheduled every 15 minutes.
--            Note: A native Snowflake ALERT cannot query Azure SQL in its condition
--            clause (pure SQL only), so a Task + proc pattern is used instead.
--
-- EMAIL:     Uses MY_EMAIL_INTEGRATION → t.jones@snowflake.com
--            Threshold: 15 minutes
-- =============================================================================

-- =============================================================================
-- PAUSE / RESUME CONTROLS (run these in Snowsight when needed)
-- =============================================================================
-- ALTER TASK FACETS_BRONZE.UTILS.FACETS_LATENCY_TASK SUSPEND;
-- ALTER TASK FACETS_BRONZE.UTILS.FACETS_LATENCY_TASK RESUME;

-- Check task status:
-- SHOW TASKS LIKE 'FACETS_LATENCY_TASK' IN SCHEMA FACETS_BRONZE.UTILS;

-- Check recent execution history:
-- SELECT * FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
--     SCHEDULED_TIME_RANGE_START => DATEADD('hour', -1, CURRENT_TIMESTAMP()),
--     TASK_NAME => 'FACETS_LATENCY_TASK'
-- )) ORDER BY SCHEDULED_TIME DESC;
-- =============================================================================

USE DATABASE FACETS_BRONZE;
USE SCHEMA   UTILS;

-- =============================================================================
-- STEP 1: Create stored procedure
-- =============================================================================

CREATE OR REPLACE PROCEDURE FACETS_BRONZE.UTILS.FACETS_LATENCY_CHECK(
    "SQL_SERVER_HOST"    VARCHAR,
    "SQL_SERVER_DB"      VARCHAR,
    "THRESHOLD_MINUTES"  INT,
    "EMAIL_TO"           VARCHAR,
    "EMAIL_INTEGRATION"  VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
ARTIFACT_REPOSITORY = snowflake.snowpark.pypi_shared_repository
PACKAGES = ('snowflake-snowpark-python', 'python-tds', 'certifi')
HANDLER = 'latency_check'
EXTERNAL_ACCESS_INTEGRATIONS = (AZURE_SQL_FACETS_EAI)
SECRETS = ('facets_sql_creds' = FACETS_BRONZE.UTILS.FACETS_SQL_CREDS)
COMMENT = 'Checks Azure SQL vs Snowflake Bronze replication lag; emails alert if any table exceeds threshold'
EXECUTE AS OWNER
AS
$$
import pytds
import certifi
from datetime import datetime, timezone

# Tables to monitor — (azure_schema.table, ts_column, bronze_table)
TABLES = [
    ('raw.CMC_MEME_MEMBER',    'SYS_LAST_UPD_DTM', 'CMC_MEME_MEMBER'),
    ('raw.CMC_MEPE_PRCS_ELIG', 'SYS_LAST_UPD_DTM', 'CMC_MEPE_PRCS_ELIG'),
    ('raw.CMC_SBSB_SUBSC',     'SYS_LAST_UPD_DTM', 'CMC_SBSB_SUBSC'),
    ('raw.CMC_PRPR_PROV',      'SYS_LAST_UPD_DTM', 'CMC_PRPR_PROV'),
    ('raw.CMC_NWPR_RELATION',  'SYS_LAST_UPD_DTM', 'CMC_NWPR_RELATION'),
    ('raw.CMC_MEPR_PRIM_PROV', 'SYS_LAST_UPD_DTM', 'CMC_MEPR_PRIM_PROV'),
    ('raw.CMC_MECD_MEDICAID',  'SYS_LAST_UPD_DTM', 'CMC_MECD_MEDICAID'),
    ('raw.CMC_MESU_SUBSIDY',   'SYS_LAST_UPD_DTM', 'CMC_MESU_SUBSIDY'),
]

def latency_check(session, sql_server_host: str, sql_server_db: str,
                  threshold_minutes: int, email_to: str, email_integration: str) -> str:
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
        autocommit=True
    )
    cur = conn.cursor()

    results = []

    try:
        for azure_table, ts_col, bronze_table in TABLES:
            # --- Azure SQL: last update timestamp ---
            cur.execute(f"SELECT MAX({ts_col}) FROM {azure_table}")
            row = cur.fetchone()
            last_azure = row[0] if row and row[0] else None

            # --- Snowflake Bronze: last delivered timestamp ---
            snow_result = session.sql(
                f"SELECT MAX(_SNOWFLAKE_UPDATED_AT) FROM FACETS_BRONZE.RAW.{bronze_table}"
            ).collect()
            last_snow_raw = snow_result[0][0] if snow_result and snow_result[0][0] else None

            # Normalize to naive UTC for comparison
            if last_azure:
                if hasattr(last_azure, 'tzinfo') and last_azure.tzinfo:
                    last_azure = last_azure.astimezone(timezone.utc).replace(tzinfo=None)

            if last_snow_raw:
                if hasattr(last_snow_raw, 'tzinfo') and last_snow_raw.tzinfo:
                    last_snow = last_snow_raw.astimezone(timezone.utc).replace(tzinfo=None)
                else:
                    last_snow = last_snow_raw
            else:
                last_snow = None

            # Calculate lag in minutes (Azure ahead of Snowflake = positive lag)
            if last_azure and last_snow:
                lag_seconds = (last_azure - last_snow).total_seconds()
                lag_minutes = round(lag_seconds / 60, 1)
            elif last_azure and not last_snow:
                lag_minutes = 9999  # Bronze table empty — treat as max lag
            else:
                lag_minutes = 0

            results.append({
                'table':       bronze_table,
                'last_azure':  last_azure.strftime('%Y-%m-%d %H:%M:%S') if last_azure else 'N/A',
                'last_snow':   last_snow.strftime('%Y-%m-%d %H:%M:%S')  if last_snow  else 'N/A',
                'lag_minutes': lag_minutes,
                'over_limit':  lag_minutes > threshold_minutes
            })

    finally:
        cur.close()
        conn.close()

    # --- Check if any table is over the threshold ---
    lagging = [r for r in results if r['over_limit']]

    if not lagging:
        return f"OK — all {len(results)} tables within {threshold_minutes}-minute threshold"

    # --- Build HTML email ---
    run_ts = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')

    rows_html = ''
    for r in lagging:
        lag_color = '#d32f2f' if r['lag_minutes'] > threshold_minutes * 2 else '#f57c00'
        rows_html += f"""
        <tr>
          <td style="padding:8px;border-bottom:1px solid #e0e0e0;">{r['table']}</td>
          <td style="padding:8px;border-bottom:1px solid #e0e0e0;">{r['last_azure']}</td>
          <td style="padding:8px;border-bottom:1px solid #e0e0e0;">{r['last_snow']}</td>
          <td style="padding:8px;border-bottom:1px solid #e0e0e0;color:{lag_color};font-weight:bold;text-align:right;">{r['lag_minutes']}</td>
        </tr>"""

    html_body = f"""<!DOCTYPE html>
<html>
<body style="font-family:Arial,sans-serif;margin:24px;color:#212121;">
  <h2 style="color:#d32f2f;margin-bottom:4px;">Openflow Replication Lag Alert</h2>
  <p style="color:#666;margin-top:0;font-size:13px;">Checked at {run_ts}</p>
  <p>{len(lagging)} of {len(results)} monitored tables exceeded the <strong>{threshold_minutes}-minute</strong> replication threshold.</p>
  <table cellpadding="0" cellspacing="0" border="0"
         style="border-collapse:collapse;width:100%;max-width:680px;font-size:14px;">
    <thead>
      <tr style="background-color:#0090D4;color:#ffffff;">
        <th style="text-align:left;padding:10px 8px;">Table</th>
        <th style="text-align:left;padding:10px 8px;">Last Azure Update</th>
        <th style="text-align:left;padding:10px 8px;">Last Snowflake Update</th>
        <th style="text-align:right;padding:10px 8px;">Lag (min)</th>
      </tr>
    </thead>
    <tbody>{rows_html}
    </tbody>
  </table>
  <p style="margin-top:20px;">
    <a href="https://app.snowflake.com" style="color:#0090D4;">Open Snowsight</a>
    &nbsp;|&nbsp;
    Check Openflow connector status for delayed tables.
  </p>
  <p style="color:#9e9e9e;font-size:11px;margin-top:32px;">
    Sent by FACETS_BRONZE.UTILS.FACETS_LATENCY_CHECK &bull; Runs every 15 minutes
  </p>
</body>
</html>"""

    # Escape single quotes for SQL embedding
    safe_body = html_body.replace("'", "''")
    subject   = f"[Openflow Alert] {len(lagging)} table(s) lagging > {threshold_minutes} min"

    session.sql(f"""
        CALL SYSTEM$SEND_EMAIL(
            '{email_integration}',
            '{email_to}',
            '{subject}',
            '{safe_body}',
            'text/html'
        )
    """).collect()

    return f"ALERT SENT — {len(lagging)} table(s) over {threshold_minutes}-min threshold: {[r['table'] for r in lagging]}"
$$;

-- =============================================================================
-- STEP 2: Create task (created suspended — resume in Step 3)
-- =============================================================================

CREATE OR REPLACE TASK FACETS_BRONZE.UTILS.FACETS_LATENCY_TASK
    WAREHOUSE = WH_XS
    SCHEDULE  = '15 MINUTE'
    COMMENT   = 'Checks Openflow replication lag every 15 min; emails t.jones@snowflake.com if any table > 15 min behind'
AS
    CALL FACETS_BRONZE.UTILS.FACETS_LATENCY_CHECK(
        'tjonessqlserver.database.windows.net',
        'openflow',
        15,
        't.jones@snowflake.com',
        'MY_EMAIL_INTEGRATION'
    );

-- =============================================================================
-- STEP 3: Resume the task
-- =============================================================================

ALTER TASK FACETS_BRONZE.UTILS.FACETS_LATENCY_TASK RESUME;

-- =============================================================================
-- STEP 4: Test it immediately (manual execution)
-- =============================================================================

CALL FACETS_BRONZE.UTILS.FACETS_LATENCY_CHECK(
    'tjonessqlserver.database.windows.net',
    'openflow',
    15,
    't.jones@snowflake.com',
    'MY_EMAIL_INTEGRATION'
);
