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

OF_FILTER = """
    RESOURCE_ATTRIBUTES:"service.name"::VARCHAR IN ('openflow', 'openflow-runtime-server')
"""

# ── Helpers ───────────────────────────────────────────────────────────────────
# Cast to TIMESTAMP_NTZ after CONVERT_TIMEZONE so pandas keeps MT values
# instead of re-converting back to UTC on render.
def to_mtn(expr):
    return f"CONVERT_TIMEZONE('UTC', 'America/Denver', {expr})::TIMESTAMP_NTZ"

# ── Sidebar ───────────────────────────────────────────────────────────────────
with st.sidebar:
    st.header("Filters")
    hours_back = st.selectbox(
        "Time window",
        options=[6, 12, 24, 48, 168],
        index=2,
        format_func=lambda h: f"Last {h}h" if h < 168 else "Last 7 days",
    )
    st.divider()
    table_filter_placeholder = st.empty()
    st.divider()
    st.caption("All times: Mountain Time (MDT/UTC-6)")

@st.cache_data(ttl=60)
def q(sql):
    return session.sql(sql).to_pandas()

# ── 1. Per-table ingestion status ─────────────────────────────────────────────
table_sql = f"""
WITH telemetry AS (
    SELECT
        RECORD_ATTRIBUTES:"source.table.name"::VARCHAR              AS table_name,
        MAX(CASE WHEN RECORD:"metric"."name"::VARCHAR = 'db.last.ingestion.time'
                 THEN TO_TIMESTAMP_NTZ(VALUE::BIGINT / 1000) END)              AS last_ingestion_utc,
        MAX(CASE WHEN RECORD:"metric"."name"::VARCHAR = 'db.last.ingestion.time'
                 THEN {to_mtn('TO_TIMESTAMP_NTZ(VALUE::BIGINT / 1000)')} END)  AS last_ingestion_mtn,
        MAX(CASE WHEN RECORD:"metric"."name"::VARCHAR = 'db.table.status'
                 THEN VALUE::INTEGER END)                           AS status_code
    FROM OPENFLOW.TELEMETRY.EVENTS
    WHERE RECORD_TYPE = 'METRIC'
      AND {OF_FILTER}
      AND RECORD:"metric"."name"::VARCHAR IN ('db.last.ingestion.time', 'db.table.status')
      AND TIMESTAMP >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
    GROUP BY 1
),
row_counts AS (
    SELECT TABLE_NAME, ROW_COUNT
    FROM FACETS_BRONZE.INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = 'RAW'
      AND TABLE_NAME NOT LIKE '%JOURNAL%'
)
SELECT
    t.table_name,
    t.last_ingestion_mtn,
    DATEDIFF('minute',
             t.last_ingestion_utc,
             CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP())::TIMESTAMP_NTZ)       AS mins_since_ingest,
    CASE t.status_code
        WHEN 3 THEN '🟢 Active'
        WHEN 2 THEN '🟡 Snapshot'
        WHEN 1 THEN '🟡 Starting'
        ELSE '🔴 Status ' || t.status_code
    END AS status,
    r.row_count
FROM telemetry t
LEFT JOIN row_counts r ON r.TABLE_NAME = t.table_name
ORDER BY t.last_ingestion_mtn DESC
"""
table_df = q(table_sql)

# ── Sidebar table filter ──────────────────────────────────────────────────────
all_tables = sorted(table_df["TABLE_NAME"].tolist()) if not table_df.empty else []
with table_filter_placeholder:
    selected_tables = st.multiselect(
        "Filter tables", options=all_tables, default=[], placeholder="All tables"
    )
display_df = table_df[table_df["TABLE_NAME"].isin(selected_tables)] if selected_tables else table_df

# ── 2. CDC throughput ─────────────────────────────────────────────────────────
cdc_sql = f"""
SELECT
    DATE_TRUNC('hour', {to_mtn('TIMESTAMP')})                       AS hour,
    SUM(CASE WHEN RECORD_ATTRIBUTES:"counter"::VARCHAR = 'DML Events Processed'
             THEN VALUE::FLOAT ELSE 0 END)                          AS dml_events,
    SUM(CASE WHEN RECORD_ATTRIBUTES:"counter"::VARCHAR = 'Rows Sent'
             AND RECORD_ATTRIBUTES:"component"::VARCHAR = 'PublishChangeDataSnowpipeStreaming'
             THEN VALUE::FLOAT ELSE 0 END)                          AS rows_sent_snowflake
FROM OPENFLOW.TELEMETRY.EVENTS
WHERE RECORD_TYPE = 'METRIC'
  AND {OF_FILTER}
  AND RECORD:"metric"."name"::VARCHAR = 'processor.counter'
  AND RECORD_ATTRIBUTES:"counter"::VARCHAR IN ('DML Events Processed', 'Rows Sent')
  AND TIMESTAMP >= DATEADD('hour', -{hours_back}, CURRENT_TIMESTAMP())
GROUP BY 1
ORDER BY 1
"""
cdc_df = q(cdc_sql)

# ── KPIs ──────────────────────────────────────────────────────────────────────
active_cnt  = len(table_df[table_df["STATUS"] == "🟢 Active"]) if not table_df.empty else 0
last_ingest = table_df["LAST_INGESTION_MTN"].max() if not table_df.empty else None
stale_cnt   = len(table_df[table_df["MINS_SINCE_INGEST"] > 120]) if not table_df.empty else 0
total_dml   = int(cdc_df["DML_EVENTS"].sum()) if not cdc_df.empty else 0

k1, k2, k3, k4, k5 = st.columns(5)
k1.metric("Tables Tracked", len(table_df))
k2.metric("Active (CDC)", active_cnt)
k3.metric("Last Ingestion (MT)", pd.Timestamp(last_ingest).strftime("%H:%M") if last_ingest else "—")
k4.metric("Stale (>2h)", stale_cnt,
          delta=f"{stale_cnt} stale" if stale_cnt > 0 else None, delta_color="inverse")
k5.metric(f"DML Events ({hours_back}h)", f"{total_dml:,}")

st.divider()

# ── Table grid ────────────────────────────────────────────────────────────────
st.subheader("Table Ingestion Status  ·  Click a row to see batch detail")

disp = display_df[["TABLE_NAME","STATUS","LAST_INGESTION_MTN","MINS_SINCE_INGEST","ROW_COUNT"]].rename(columns={
    "TABLE_NAME":         "Table",
    "STATUS":             "Status",
    "LAST_INGESTION_MTN": "Last Ingestion (MT)",
    "MINS_SINCE_INGEST":  "Mins Ago",
    "ROW_COUNT":          "Row Count",
})

def highlight_stale(row):
    return ["background-color: #fff3cd"] * len(row) if (row["Mins Ago"] or 0) > 120 else [""] * len(row)

selection = st.dataframe(
    disp.style.apply(highlight_stale, axis=1),
    use_container_width=True,
    height=420,
    on_select="rerun",
    selection_mode="single-row",
)

# ── Drill-down: per-batch DML table ───────────────────────────────────────────
selected_rows = selection.selection.rows if hasattr(selection, "selection") else []
if selected_rows:
    idx            = selected_rows[0]
    selected_table = display_df.iloc[idx]["TABLE_NAME"]
    row_info       = display_df.iloc[idx]

    st.divider()
    st.subheader(f"🔍 {selected_table}  —  Batch Load History (last {hours_back}h, MT)")
    st.caption(
        f"Status: {row_info['STATUS']}  ·  "
        f"Last Ingestion: {pd.Timestamp(row_info['LAST_INGESTION_MTN']).strftime('%Y-%m-%d %H:%M MT')}  ·  "
        f"Total Rows in Bronze: {int(row_info['ROW_COUNT'] or 0):,}"
    )

    # Group by minute of _SNOWFLAKE_UPDATED_AT to capture individual Openflow batches
    batch_sql = f"""
    SELECT
        DATE_TRUNC('minute',
            {to_mtn('_SNOWFLAKE_UPDATED_AT')})                      AS batch_time_mt,
        COUNT_IF(
            _SNOWFLAKE_INSERTED_AT = _SNOWFLAKE_UPDATED_AT
            AND _SNOWFLAKE_DELETED = FALSE
        )                                                            AS inserts,
        COUNT_IF(
            _SNOWFLAKE_UPDATED_AT > _SNOWFLAKE_INSERTED_AT
            AND _SNOWFLAKE_DELETED = FALSE
        )                                                            AS updates,
        COUNT_IF(_SNOWFLAKE_DELETED = TRUE)                          AS deletes,
        COUNT(*)                                                     AS total
    FROM FACETS_BRONZE.RAW.{selected_table}
    WHERE _SNOWFLAKE_UPDATED_AT >= DATEADD('hour', -{hours_back}, CURRENT_TIMESTAMP())
    GROUP BY 1
    ORDER BY 1 DESC
    """
    batch_df = q(batch_sql)

    if not batch_df.empty:
        d1, d2, d3, d4 = st.columns(4)
        d1.metric("Total Inserts",  f"{int(batch_df['INSERTS'].sum()):,}")
        d2.metric("Total Updates",  f"{int(batch_df['UPDATES'].sum()):,}")
        d3.metric("Total Deletes",  f"{int(batch_df['DELETES'].sum()):,}")
        d4.metric("Batches",        len(batch_df))

        st.dataframe(
            batch_df.rename(columns={
                "BATCH_TIME_MT": "Batch Time (MT)",
                "INSERTS":       "Inserts",
                "UPDATES":       "Updates",
                "DELETES":       "Deletes",
                "TOTAL":         "Total Rows",
            }),
            use_container_width=True,
            height=400,
        )
    else:
        st.info(f"No rows in {selected_table} were updated in the last {hours_back} hours.")

st.divider()

# ── Overall throughput charts ──────────────────────────────────────────────────
col1, col2 = st.columns(2)
with col1:
    st.subheader("DML Events Captured (MT)")
    if not cdc_df.empty and cdc_df["DML_EVENTS"].sum() > 0:
        st.bar_chart(cdc_df.set_index("HOUR")["DML_EVENTS"], height=250)
        st.caption("SQL Server change tracking → NiFi (MultiDatabaseCaptureChangeSqlServer)")
    else:
        st.info("No DML events in this window.")

with col2:
    st.subheader("Rows Sent to Snowflake (MT)")
    if not cdc_df.empty and cdc_df["ROWS_SENT_SNOWFLAKE"].sum() > 0:
        st.bar_chart(cdc_df.set_index("HOUR")["ROWS_SENT_SNOWFLAKE"], height=250)
        st.caption("NiFi → Snowflake via Snowpipe Streaming (PublishChangeDataSnowpipeStreaming)")
    else:
        st.info("No rows sent in this window.")

st.caption(
    f"60s cache · All times Mountain Time (MDT/UTC-6) · "
    f"Window: last {hours_back}h · "
    f"Rendered: {datetime.now().strftime('%Y-%m-%d %H:%M MT')}"
)
