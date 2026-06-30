import streamlit as st
import pandas as pd
from datetime import datetime

st.set_page_config(
    page_title="Openflow Observability",
    page_icon="🔄",
    layout="wide",
)

st.title("🔄 Openflow CDC — Table Ingestion Monitor")
st.caption("Facets SQL Server (openflow/raw) → FACETS_BRONZE.RAW via Snowpipe Streaming")

conn = st.connection("snowflake")
session = conn.session()

# Openflow-only filter
OF_FILTER = """
    RESOURCE_ATTRIBUTES:"service.name"::VARCHAR IN ('openflow', 'openflow-runtime-server')
"""

with st.sidebar:
    st.header("Filters")
    hours_back = st.selectbox(
        "Time window",
        options=[6, 12, 24, 48, 168],
        index=2,
        format_func=lambda h: f"Last {h}h" if h < 168 else "Last 7 days",
    )
    st.divider()
    st.caption("Filtered to: service.name IN (openflow, openflow-runtime-server)")

@st.cache_data(ttl=60)
def q(sql):
    return session.sql(sql).to_pandas()

# ── 1. Per-table ingestion status ─────────────────────────────────────────────
table_sql = f"""
WITH telemetry AS (
    SELECT
        RECORD_ATTRIBUTES:"source.table.name"::VARCHAR                  AS table_name,
        MAX(CASE WHEN RECORD:"metric"."name"::VARCHAR = 'db.last.ingestion.time'
                 THEN CONVERT_TIMEZONE('UTC', 'America/Denver',
                      TO_TIMESTAMP_NTZ(VALUE::BIGINT / 1000)) END)      AS last_ingestion_mtn,
        MAX(CASE WHEN RECORD:"metric"."name"::VARCHAR = 'db.table.status'
                 THEN VALUE::INTEGER END)                               AS status_code
    FROM OPENFLOW.TELEMETRY.EVENTS
    WHERE RECORD_TYPE = 'METRIC'
      AND {OF_FILTER}
      AND RECORD:"metric"."name"::VARCHAR IN ('db.last.ingestion.time', 'db.table.status')
      AND TIMESTAMP >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
    GROUP BY 1
),
row_counts AS (
    SELECT TABLE_NAME, ROW_COUNT, LAST_ALTERED
    FROM FACETS_BRONZE.INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = 'RAW'
      AND TABLE_NAME NOT LIKE '%JOURNAL%'
)
SELECT
    t.table_name,
    t.last_ingestion_mtn,
    DATEDIFF('minute', t.last_ingestion_mtn,
             CONVERT_TIMEZONE('America/Denver', CURRENT_TIMESTAMP()))    AS mins_since_ingest,
    CASE t.status_code
        WHEN 3 THEN '🟢 Active'
        WHEN 2 THEN '🟡 Snapshot'
        WHEN 1 THEN '🟡 Starting'
        ELSE '🔴 Status ' || t.status_code
    END AS status,
    r.row_count,
    r.LAST_ALTERED                                                  AS last_altered
FROM telemetry t
LEFT JOIN row_counts r ON r.TABLE_NAME = t.table_name
ORDER BY t.last_ingestion_mtn DESC
"""
table_df = q(table_sql)

# ── 2. CDC throughput over time ───────────────────────────────────────────────
cdc_sql = f"""
SELECT
    DATE_TRUNC('hour', CONVERT_TIMEZONE('America/Denver', TIMESTAMP))    AS hour,
    SUM(CASE WHEN RECORD_ATTRIBUTES:"counter"::VARCHAR = 'DML Events Processed'
             THEN VALUE::FLOAT ELSE 0 END)                           AS dml_events,
    SUM(CASE WHEN RECORD_ATTRIBUTES:"counter"::VARCHAR = 'Rows Sent'
             AND RECORD_ATTRIBUTES:"component"::VARCHAR = 'PublishChangeDataSnowpipeStreaming'
             THEN VALUE::FLOAT ELSE 0 END)                           AS rows_sent_snowflake,
    SUM(CASE WHEN RECORD_ATTRIBUTES:"counter"::VARCHAR = 'Rows Fetched'
             THEN VALUE::FLOAT ELSE 0 END)                           AS rows_fetched_snapshot
FROM OPENFLOW.TELEMETRY.EVENTS
WHERE RECORD_TYPE = 'METRIC'
  AND {OF_FILTER}
  AND RECORD:"metric"."name"::VARCHAR = 'processor.counter'
  AND RECORD_ATTRIBUTES:"counter"::VARCHAR IN (
      'DML Events Processed', 'Rows Sent', 'Rows Fetched'
  )
  AND TIMESTAMP >= DATEADD('hour', -{hours_back}, CURRENT_TIMESTAMP())
GROUP BY 1
ORDER BY 1
"""
cdc_df = q(cdc_sql)

# ── KPI tiles ─────────────────────────────────────────────────────────────────
active_tables = len(table_df[table_df["STATUS"] == "🟢 Active"]) if not table_df.empty else 0
total_tables  = len(table_df)
last_ingest   = table_df["LAST_INGESTION_MTN"].max() if not table_df.empty else None
stale_tables  = len(table_df[table_df["MINS_SINCE_INGEST"] > 120]) if not table_df.empty else 0
total_dml     = int(cdc_df["DML_EVENTS"].sum()) if not cdc_df.empty else 0

k1, k2, k3, k4, k5 = st.columns(5)
k1.metric("Tables Tracked", total_tables)
k2.metric("Active (CDC)", active_tables)
k3.metric(
    "Last Ingestion",
    pd.Timestamp(last_ingest).strftime("%H:%M:%S") if last_ingest else "—"
)
k4.metric(
    "Stale Tables (>2h)",
    stale_tables,
    delta=f"{stale_tables} stale" if stale_tables > 0 else None,
    delta_color="inverse",
)
k5.metric(f"DML Events (last {hours_back}h)", f"{total_dml:,}")

st.divider()

# ── Table ingestion status ─────────────────────────────────────────────────────
st.subheader("Table Ingestion Status — All 35 CMC Tables")
if not table_df.empty:
    display_cols = ["TABLE_NAME", "STATUS", "LAST_INGESTION_MTN", "MINS_SINCE_INGEST", "ROW_COUNT"]
    display = table_df[display_cols].rename(columns={
        "TABLE_NAME":         "Table",
        "STATUS":             "Status",
        "LAST_INGESTION_MTN": "Last Ingestion (MT)",
        "MINS_SINCE_INGEST":  "Mins Ago",
        "ROW_COUNT":          "Row Count",
    })

    def highlight_stale(row):
        if row["Mins Ago"] is not None and row["Mins Ago"] > 120:
            return ["background-color: #fff3cd"] * len(row)
        return [""] * len(row)

    st.dataframe(
        display.style.apply(highlight_stale, axis=1),
        use_container_width=True,
        height=600,
    )
else:
    st.info("No table metrics in the last hour. Try expanding the time window.")

st.divider()

# ── CDC throughput charts ──────────────────────────────────────────────────────
col1, col2 = st.columns(2)

with col1:
    st.subheader("DML Events Captured (SQL Server → NiFi)")
    if not cdc_df.empty and cdc_df["DML_EVENTS"].sum() > 0:
        st.bar_chart(cdc_df.set_index("HOUR")["DML_EVENTS"], height=280)
        st.caption("MultiDatabaseCaptureChangeSqlServer: DML Events Processed counter")
    else:
        st.info("No DML events in this window — no source changes detected.")

with col2:
    st.subheader("Rows Sent to Snowflake (via Snowpipe Streaming)")
    if not cdc_df.empty and cdc_df["ROWS_SENT_SNOWFLAKE"].sum() > 0:
        st.bar_chart(cdc_df.set_index("HOUR")["ROWS_SENT_SNOWFLAKE"], height=280)
        st.caption("PublishChangeDataSnowpipeStreaming: Rows Sent counter")
    else:
        st.info("No rows sent in this window.")

st.divider()

st.caption(
    f"60s cache · Filtered: service.name IN (openflow, openflow-runtime-server) · "
    f"Window: last {hours_back}h · "
    f"Rendered: {datetime.now().strftime('%Y-%m-%d %H:%M MT')}"
)
