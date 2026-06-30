import streamlit as st
import pandas as pd
from datetime import datetime, timedelta

st.set_page_config(
    page_title="Openflow Observability",
    page_icon="🔄",
    layout="wide",
)

st.title("🔄 Openflow CDC Observability")
st.caption("Source: OPENFLOW.TELEMETRY.EVENTS — Facets SQL Server → FACETS_BRONZE.RAW")

# ── Connection ────────────────────────────────────────────────────────────────
conn = st.connection("snowflake")
session = conn.session()

# ── Sidebar controls ──────────────────────────────────────────────────────────
with st.sidebar:
    st.header("Filters")
    hours_back = st.selectbox(
        "Time window",
        options=[6, 12, 24, 48, 168],
        index=2,
        format_func=lambda h: f"Last {h}h" if h < 168 else "Last 7 days",
    )
    st.divider()
    st.caption(f"Window: last {hours_back} hours")
    st.caption("Event table: OPENFLOW.TELEMETRY.EVENTS")

# ── Helper ────────────────────────────────────────────────────────────────────
@st.cache_data(ttl=60)
def run_query(sql: str) -> pd.DataFrame:
    return session.sql(sql).to_pandas()

# ── KPI row ───────────────────────────────────────────────────────────────────
kpi_sql = f"""
SELECT
    COUNT(*)                                                                AS total_events,
    COUNT_IF(RECORD_TYPE = 'LOG')                                          AS log_events,
    COUNT_IF(RECORD_TYPE = 'METRIC')                                       AS metric_events,
    COUNT_IF(RECORD_TYPE = 'EVENT')                                        AS connector_events,
    COUNT_IF(
        RECORD_TYPE = 'EVENT'
        AND VALUE:"error_message"::VARCHAR IS NOT NULL
    )                                                                       AS error_events,
    MAX(TIMESTAMP)                                                          AS last_event_ts
FROM OPENFLOW.TELEMETRY.EVENTS
WHERE TIMESTAMP >= DATEADD('hour', -{hours_back}, CURRENT_TIMESTAMP())
"""
kpi = run_query(kpi_sql)

k1, k2, k3, k4, k5 = st.columns(5)
k1.metric("Total Events", f"{int(kpi['TOTAL_EVENTS'][0]):,}")
k2.metric("Log Events", f"{int(kpi['LOG_EVENTS'][0]):,}")
k3.metric("Connector Events", f"{int(kpi['CONNECTOR_EVENTS'][0]):,}")
k4.metric(
    "Error Events",
    f"{int(kpi['ERROR_EVENTS'][0]):,}",
    delta=None if kpi['ERROR_EVENTS'][0] == 0 else f"{int(kpi['ERROR_EVENTS'][0])} errors",
    delta_color="inverse",
)
last_ts = kpi['LAST_EVENT_TS'][0]
k5.metric("Last Event", pd.Timestamp(last_ts).strftime("%H:%M:%S") if last_ts else "—")

st.divider()

# ── Row 1: Event volume + Catalog poll health ─────────────────────────────────
col_left, col_right = st.columns(2)

with col_left:
    st.subheader("Event Volume by Type")
    vol_sql = f"""
    SELECT
        DATE_TRUNC('hour', TIMESTAMP)  AS hour,
        RECORD_TYPE,
        COUNT(*)                       AS event_count
    FROM OPENFLOW.TELEMETRY.EVENTS
    WHERE TIMESTAMP >= DATEADD('hour', -{hours_back}, CURRENT_TIMESTAMP())
    GROUP BY 1, 2
    ORDER BY 1, 2
    """
    vol_df = run_query(vol_sql)
    if not vol_df.empty:
        pivot = vol_df.pivot(index="HOUR", columns="RECORD_TYPE", values="EVENT_COUNT").fillna(0)
        st.line_chart(pivot, height=280)
    else:
        st.info("No event data in this window.")

with col_right:
    st.subheader("Catalog Poll Latency (ms)")
    poll_sql = f"""
    SELECT
        DATE_TRUNC('hour', TIMESTAMP)              AS hour,
        COUNT(*)                                   AS poll_count,
        ROUND(AVG(VALUE:"duration_millis"::FLOAT)) AS avg_ms,
        MAX(VALUE:"duration_millis"::FLOAT)        AS max_ms
    FROM OPENFLOW.TELEMETRY.EVENTS
    WHERE RECORD_TYPE = 'EVENT'
      AND VALUE:"catalog_poll_state"::VARCHAR = 'completed'
      AND TIMESTAMP >= DATEADD('hour', -{hours_back}, CURRENT_TIMESTAMP())
    GROUP BY 1
    ORDER BY 1
    """
    poll_df = run_query(poll_sql)
    if not poll_df.empty:
        latency_chart = poll_df.set_index("HOUR")[["AVG_MS", "MAX_MS"]]
        st.line_chart(latency_chart, height=280)
        st.caption(f"Polls/hour avg: {poll_df['POLL_COUNT'].mean():.0f} (~every 30s target)")
    else:
        st.info("No catalog poll data in this window.")

st.divider()

# ── Row 2: Catalog poll count per hour + connector error events ───────────────
col_a, col_b = st.columns(2)

with col_a:
    st.subheader("Catalog Polls per Hour")
    if not poll_df.empty:
        st.bar_chart(poll_df.set_index("HOUR")["POLL_COUNT"], height=280)
        healthy = poll_df[poll_df["POLL_COUNT"] >= 100]
        pct = 100 * len(healthy) / len(poll_df)
        color = "🟢" if pct > 90 else "🟡" if pct > 70 else "🔴"
        st.caption(f"{color} {pct:.0f}% of hours had ≥100 polls (expected ~116/hr)")
    else:
        st.info("No catalog poll data.")

with col_b:
    st.subheader("Connector State Events")
    state_sql = f"""
    SELECT
        TIMESTAMP,
        VALUE:"state"::VARCHAR           AS state,
        VALUE:"error_message"::VARCHAR   AS error_message,
        VALUE:"file_path"::VARCHAR       AS file_path,
        VALUE:"catalog_poll_state"::VARCHAR AS catalog_state
    FROM OPENFLOW.TELEMETRY.EVENTS
    WHERE RECORD_TYPE = 'EVENT'
      AND TIMESTAMP >= DATEADD('hour', -{hours_back}, CURRENT_TIMESTAMP())
    ORDER BY TIMESTAMP DESC
    LIMIT 50
    """
    state_df = run_query(state_sql)
    if not state_df.empty:
        # Show error/state events (non-catalog, non-file)
        errors = state_df[
            state_df["STATE"].notna() | state_df["ERROR_MESSAGE"].notna()
        ][["TIMESTAMP", "STATE", "ERROR_MESSAGE"]].dropna(how="all", subset=["STATE", "ERROR_MESSAGE"])
        if len(errors) > 0:
            st.dataframe(errors, use_container_width=True, height=280)
        else:
            st.success("✅ No connector error states in this window.")
            # Show catalog stats instead
            catalog_ok = state_df[state_df["CATALOG_STATE"] == "completed"]
            st.caption(f"Catalog polls in window: {len(catalog_ok)}")
    else:
        st.info("No connector state events.")

st.divider()

# ── Row 3: Recent log messages ─────────────────────────────────────────────────
st.subheader("Recent Log Messages (Data Plane)")
log_sql = f"""
SELECT
    TIMESTAMP,
    VALUE:"log":"level"::VARCHAR              AS level,
    SPLIT_PART(VALUE:"log":"logger"::VARCHAR, '.', -1) AS logger_short,
    SUBSTR(VALUE:"message"::VARCHAR, 1, 200) AS message
FROM OPENFLOW.TELEMETRY.EVENTS
WHERE RECORD_TYPE = 'LOG'
  AND TIMESTAMP >= DATEADD('hour', -{hours_back}, CURRENT_TIMESTAMP())
  AND VALUE:"log":"level"::VARCHAR IS NOT NULL
ORDER BY TIMESTAMP DESC
LIMIT 100
"""
log_df = run_query(log_sql)

if not log_df.empty:
    level_filter = st.multiselect(
        "Filter by level",
        options=sorted(log_df["LEVEL"].dropna().unique().tolist()),
        default=sorted(log_df["LEVEL"].dropna().unique().tolist()),
    )
    filtered = log_df[log_df["LEVEL"].isin(level_filter)] if level_filter else log_df

    def colour_level(val):
        colours = {"ERROR": "background-color: #ffcccc", "WARN": "background-color: #fff3cd"}
        return colours.get(val, "")

    st.dataframe(
        filtered.style.applymap(colour_level, subset=["LEVEL"]),
        use_container_width=True,
        height=300,
    )
else:
    st.info("No data-plane log messages in this window. Logs may be in NiFi runtime format — see full event table for details.")
    # Show raw log volume anyway
    raw_log_sql = f"""
    SELECT DATE_TRUNC('hour', TIMESTAMP) AS hour, COUNT(*) AS logs
    FROM OPENFLOW.TELEMETRY.EVENTS
    WHERE RECORD_TYPE = 'LOG'
      AND TIMESTAMP >= DATEADD('hour', -{hours_back}, CURRENT_TIMESTAMP())
    GROUP BY 1 ORDER BY 1
    """
    raw_df = run_query(raw_log_sql)
    if not raw_df.empty:
        st.caption("Log event volume (all formats):")
        st.bar_chart(raw_df.set_index("HOUR")["LOGS"], height=160)

st.divider()

# ── Footer ────────────────────────────────────────────────────────────────────
st.caption(
    f"Refreshes every 60s · "
    f"Event table: OPENFLOW.TELEMETRY.EVENTS · "
    f"Window: last {hours_back}h · "
    f"Last rendered: {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}"
)
