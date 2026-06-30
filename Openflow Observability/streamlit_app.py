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
    # Table filter — updated dynamically once we have the table list
    table_filter_placeholder = st.empty()
    st.divider()
    st.caption("All times: Mountain Time (MDT/UTC-6)")

@st.cache_data(ttl=60)
def q(sql):
    return session.sql(sql).to_pandas()

# ── 1. Per-table ingestion status (from telemetry + INFORMATION_SCHEMA) ───────
table_sql = f"""
WITH telemetry AS (
    SELECT
        RECORD_ATTRIBUTES:"source.table.name"::VARCHAR              AS table_name,
        MAX(CASE WHEN RECORD:"metric"."name"::VARCHAR = 'db.last.ingestion.time'
                 THEN CONVERT_TIMEZONE('UTC', 'America/Denver',
                      TO_TIMESTAMP_NTZ(VALUE::BIGINT / 1000)) END)  AS last_ingestion_mtn,
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
    DATEDIFF('minute', t.last_ingestion_mtn,
             CONVERT_TIMEZONE('America/Denver', CURRENT_TIMESTAMP()))  AS mins_since_ingest,
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

# ── Populate sidebar table filter now that we have the list ──────────────────
all_tables = sorted(table_df["TABLE_NAME"].tolist()) if not table_df.empty else []
with table_filter_placeholder:
    selected_tables = st.multiselect(
        "Filter tables",
        options=all_tables,
        default=[],
        placeholder="All tables",
    )

# Apply sidebar filter to display table
display_df = table_df[table_df["TABLE_NAME"].isin(selected_tables)] if selected_tables else table_df

# ── 2. CDC throughput (MTN already applied in DATE_TRUNC) ────────────────────
cdc_sql = f"""
SELECT
    DATE_TRUNC('hour', CONVERT_TIMEZONE('America/Denver', TIMESTAMP)) AS hour,
    SUM(CASE WHEN RECORD_ATTRIBUTES:"counter"::VARCHAR = 'DML Events Processed'
             THEN VALUE::FLOAT ELSE 0 END)                            AS dml_events,
    SUM(CASE WHEN RECORD_ATTRIBUTES:"counter"::VARCHAR = 'Rows Sent'
             AND RECORD_ATTRIBUTES:"component"::VARCHAR = 'PublishChangeDataSnowpipeStreaming'
             THEN VALUE::FLOAT ELSE 0 END)                            AS rows_sent_snowflake
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

# ── KPI tiles ─────────────────────────────────────────────────────────────────
active_tables = len(table_df[table_df["STATUS"] == "🟢 Active"]) if not table_df.empty else 0
last_ingest   = table_df["LAST_INGESTION_MTN"].max() if not table_df.empty else None
stale_tables  = len(table_df[table_df["MINS_SINCE_INGEST"] > 120]) if not table_df.empty else 0
total_dml     = int(cdc_df["DML_EVENTS"].sum()) if not cdc_df.empty else 0

k1, k2, k3, k4, k5 = st.columns(5)
k1.metric("Tables Tracked", len(table_df))
k2.metric("Active (CDC)", active_tables)
k3.metric("Last Ingestion (MT)", pd.Timestamp(last_ingest).strftime("%H:%M") if last_ingest else "—")
k4.metric("Stale (>2h)", stale_tables,
          delta=f"{stale_tables} stale" if stale_tables > 0 else None,
          delta_color="inverse")
k5.metric(f"DML Events ({hours_back}h)", f"{total_dml:,}")

st.divider()

# ── Table grid with click-to-drilldown ────────────────────────────────────────
st.subheader("Table Ingestion Status  ·  Click a row to drill down")

display_cols = ["TABLE_NAME", "STATUS", "LAST_INGESTION_MTN", "MINS_SINCE_INGEST", "ROW_COUNT"]
disp = display_df[display_cols].rename(columns={
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
    height=450,
    on_select="rerun",
    selection_mode="single-row",
)

# ── Drill-down ─────────────────────────────────────────────────────────────────
selected_rows = selection.selection.rows if hasattr(selection, "selection") else []
if selected_rows:
    idx = selected_rows[0]
    selected_table = display_df.iloc[idx]["TABLE_NAME"]
    row_info       = display_df.iloc[idx]

    st.divider()
    st.subheader(f"🔍 Drill-down: {selected_table}")
    st.caption(
        f"Status: {row_info['STATUS']}  ·  "
        f"Last Ingestion: {pd.Timestamp(row_info['LAST_INGESTION_MTN']).strftime('%Y-%m-%d %H:%M MT')}  ·  "
        f"Row Count: {int(row_info['ROW_COUNT'] or 0):,}"
    )

    # Query Bronze table for insert/update/delete history
    detail_sql = f"""
    SELECT
        DATE_TRUNC('hour', CONVERT_TIMEZONE('UTC', 'America/Denver', _SNOWFLAKE_UPDATED_AT)) AS hour,
        COUNT_IF(
            _SNOWFLAKE_INSERTED_AT = _SNOWFLAKE_UPDATED_AT
            AND _SNOWFLAKE_DELETED = FALSE
        )                                                            AS inserts,
        COUNT_IF(
            _SNOWFLAKE_UPDATED_AT > _SNOWFLAKE_INSERTED_AT
            AND _SNOWFLAKE_DELETED = FALSE
        )                                                            AS updates,
        COUNT_IF(_SNOWFLAKE_DELETED = TRUE)                          AS deletes,
        COUNT(*)                                                     AS total_rows_touched
    FROM FACETS_BRONZE.RAW.{selected_table}
    WHERE _SNOWFLAKE_UPDATED_AT >= DATEADD('hour', -{hours_back}, CURRENT_TIMESTAMP())
    GROUP BY 1
    ORDER BY 1
    """
    detail_df = q(detail_sql)

    if not detail_df.empty:
        total_ins = int(detail_df["INSERTS"].sum())
        total_upd = int(detail_df["UPDATES"].sum())
        total_del = int(detail_df["DELETES"].sum())
        total_tot = int(detail_df["TOTAL_ROWS_TOUCHED"].sum())

        d1, d2, d3, d4 = st.columns(4)
        d1.metric("Inserts", f"{total_ins:,}")
        d2.metric("Updates", f"{total_upd:,}")
        d3.metric("Deletes", f"{total_del:,}")
        d4.metric("Total Rows Touched", f"{total_tot:,}")

        chart_data = detail_df.set_index("HOUR")[["INSERTS", "UPDATES", "DELETES"]]
        st.bar_chart(chart_data, height=300, color=["#2196F3", "#FF9800", "#F44336"])
        st.caption(
            "Inserts: _SNOWFLAKE_INSERTED_AT = _SNOWFLAKE_UPDATED_AT  ·  "
            "Updates: _SNOWFLAKE_UPDATED_AT > _SNOWFLAKE_INSERTED_AT  ·  "
            "Deletes: _SNOWFLAKE_DELETED = TRUE"
        )

        with st.expander("Raw hourly detail"):
            st.dataframe(
                detail_df.rename(columns={
                    "HOUR": "Hour (MT)", "INSERTS": "Inserts",
                    "UPDATES": "Updates", "DELETES": "Deletes",
                    "TOTAL_ROWS_TOUCHED": "Total",
                }),
                use_container_width=True,
            )
    else:
        st.info(f"No rows in {selected_table} were updated in the last {hours_back} hours.")

st.divider()

# ── Overall CDC throughput ─────────────────────────────────────────────────────
col1, col2 = st.columns(2)
with col1:
    st.subheader("DML Events Captured")
    if not cdc_df.empty and cdc_df["DML_EVENTS"].sum() > 0:
        st.bar_chart(cdc_df.set_index("HOUR")["DML_EVENTS"], height=250)
        st.caption("SQL Server change tracking → NiFi (MultiDatabaseCaptureChangeSqlServer)")
    else:
        st.info("No DML events in this window.")

with col2:
    st.subheader("Rows Sent to Snowflake")
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
