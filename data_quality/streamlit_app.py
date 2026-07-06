import streamlit as st
import pandas as pd
from datetime import datetime

st.set_page_config(
    page_title="CalOptima Member Data Quality",
    page_icon="🏥",
    layout="wide",
)

st.title("CalOptima Member Data Quality Monitor")
st.caption("zzFACETS_DEV_CLONE.SILVER.MEMBER  ·  9 data metric functions  ·  TRIGGER_ON_CHANGES")

conn = st.connection("snowflake")
session = conn.session()

DB   = "zzFACETS_DEV_CLONE"
SCH  = "SILVER"
TBL  = "MEMBER"
FQTN = f"{DB}.{SCH}.{TBL}"

HOURS_OPTIONS = {
    "Last 1 hour":  1,
    "Last 6 hours": 6,
    "Last 24 hours": 24,
    "Last 7 days":  168,
}

SEVERITY = {
    "DUPLICATE_COUNT":              "HIGH",
    "MEDICAID_MISSING_BIC_COUNT":   "HIGH",
    "NULL_COUNT":                   "MEDIUM",
    "INVALID_NPI_COUNT":            "MEDIUM",
    "FRESHNESS":                    "LOW",
    "ROW_COUNT":                    "LOW",
    "ACCEPTED_VALUES":              "LOW",
    "SCHEMA_CHANGE_COUNT":          "LOW",
}

# ── Sidebar ────────────────────────────────────────────────────────────────────
with st.sidebar:
    st.header("Filters")
    hours_label = st.selectbox("History window", list(HOURS_OPTIONS.keys()), index=2)
    hours_back  = HOURS_OPTIONS[hours_label]
    st.divider()
    if st.button("Refresh", use_container_width=True):
        st.cache_data.clear()

# ── Helpers ────────────────────────────────────────────────────────────────────
@st.cache_data(ttl=30)
def q(sql: str) -> pd.DataFrame:
    return session.sql(sql).to_pandas()

# ── Queries ────────────────────────────────────────────────────────────────────
status_sql = f"""
SELECT
  s.METRIC_NAME,
  s.ARGUMENT_NAMES AS COLUMN_NAME,
  s.EXPECTATION_NAME,
  s.EXPECTATION_EXPRESSION,
  s.VALUE,
  s.EXPECTATION_VIOLATED,
  s.MEASUREMENT_TIME
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS s
WHERE s.TABLE_NAME     = '{TBL}'
  AND s.TABLE_SCHEMA   = '{SCH}'
  AND s.TABLE_DATABASE = '{DB}'
  AND s.EXPECTATION_NAME IN (
    SELECT EXPECTATION_NAME
    FROM TABLE({DB}.INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_EXPECTATIONS(
      REF_ENTITY_NAME   => '{DB}.{SCH}.{TBL}',
      REF_ENTITY_DOMAIN => 'TABLE'
    ))
  )
QUALIFY ROW_NUMBER() OVER (PARTITION BY s.METRIC_NAME, s.ARGUMENT_NAMES, s.EXPECTATION_NAME ORDER BY s.MEASUREMENT_TIME DESC) = 1
ORDER BY s.EXPECTATION_VIOLATED DESC, s.METRIC_NAME
"""

history_sql = f"""
SELECT
  MEASUREMENT_TIME,
  METRIC_NAME,
  COALESCE(ARGUMENT_NAMES[0]::VARCHAR, '(table)') AS ARGUMENT_NAME,
  METRIC_NAME || ' — ' || COALESCE(ARGUMENT_NAMES[0]::VARCHAR, 'table') AS METRIC_LABEL,
  VALUE
FROM TABLE(SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS(
  REF_ENTITY_NAME   => '{FQTN}',
  REF_ENTITY_DOMAIN => 'TABLE'
))
WHERE MEASUREMENT_TIME >= DATEADD('hour', -{hours_back}, CURRENT_TIMESTAMP())
ORDER BY MEASUREMENT_TIME
"""

status_df  = q(status_sql)
history_df = q(history_sql)

# ── KPI row ────────────────────────────────────────────────────────────────────
total_rules      = len(status_df)
active_violations = int(status_df["EXPECTATION_VIOLATED"].sum()) if not status_df.empty else 0
passing          = total_rules - active_violations
health_score     = round(100.0 * passing / total_rules, 1) if total_rules > 0 else 100.0

# Latest row count from history
rc_df = history_df[history_df["METRIC_NAME"] == "ROW_COUNT"] if not history_df.empty else pd.DataFrame()
member_count = int(rc_df["VALUE"].iloc[-1]) if not rc_df.empty else "—"

last_eval = (
    status_df["MEASUREMENT_TIME"].max().strftime("%H:%M:%S")
    if not status_df.empty and pd.notna(status_df["MEASUREMENT_TIME"].max())
    else "—"
)

score_color = "#28a745" if health_score == 100 else ("#fd7e14" if health_score >= 80 else "#dc3545")

k1, k2, k3, k4, k5 = st.columns(5)
k1.metric("DQ Health Score", f"{health_score}%",
          delta=f"{active_violations} violations" if active_violations > 0 else "All passing",
          delta_color="inverse" if active_violations > 0 else "off")
k2.metric("Total Rules", total_rules)
k3.metric("Active Violations", active_violations,
          delta_color="inverse" if active_violations > 0 else "off")
k4.metric("Total Members", f"{member_count:,}" if isinstance(member_count, int) else member_count)
k5.metric("Last Evaluated", last_eval)

st.divider()

# ── Section 1: Rule Status grid ────────────────────────────────────────────────
st.subheader("Rule Status  ·  All 9 Data Metric Functions")

if not status_df.empty:
    display = status_df.copy()
    display["STATUS"] = display["EXPECTATION_VIOLATED"].map(
        {True: "FAIL", False: "PASS"}
    )
    display["SEVERITY"] = display["METRIC_NAME"].map(SEVERITY).fillna("LOW")
    display["MEASUREMENT_TIME"] = pd.to_datetime(
        display["MEASUREMENT_TIME"]
    ).dt.strftime("%Y-%m-%d %H:%M:%S")

    grid = display[[
        "STATUS", "METRIC_NAME", "COLUMN_NAME",
        "EXPECTATION_EXPRESSION", "VALUE", "SEVERITY",
        "MEASUREMENT_TIME"
    ]].rename(columns={
        "STATUS":                   "Status",
        "METRIC_NAME":              "Rule",
        "COLUMN_NAME":              "Column",
        "EXPECTATION_EXPRESSION":   "Pass Condition",
        "VALUE":             "Current Value",
        "SEVERITY":                 "Severity",
        "MEASUREMENT_TIME":  "Last Evaluated",
    })

    def color_status(val):
        if val == "FAIL":
            return "color: #dc3545; font-weight: bold"
        return "color: #28a745; font-weight: bold"

    def color_severity(val):
        return {
            "HIGH":   "color: #dc3545",
            "MEDIUM": "color: #fd7e14",
            "LOW":    "color: #6c757d",
        }.get(val, "")

    st.dataframe(
        grid.style
            .map(color_status, subset=["Status"])
            .map(color_severity, subset=["Severity"]),
        use_container_width=True,
        hide_index=True,
    )
else:
    st.info("No DMF results yet. Wait ~30 seconds after setup for the first evaluation.")

st.divider()

# ── Section 2: Active Violations ───────────────────────────────────────────────
st.subheader(f"Active Violations  ·  {active_violations} rule{'s' if active_violations != 1 else ''} failing")

violations_df = status_df[status_df["EXPECTATION_VIOLATED"] == True].copy() if not status_df.empty else pd.DataFrame()

if not violations_df.empty:
    violations_df["SEVERITY"] = violations_df["METRIC_NAME"].map(SEVERITY).fillna("LOW")
    violations_df["MEASUREMENT_TIME"] = pd.to_datetime(
        violations_df["MEASUREMENT_TIME"]
    ).dt.strftime("%Y-%m-%d %H:%M:%S")

    vgrid = violations_df[[
        "SEVERITY", "METRIC_NAME", "COLUMN_NAME",
        "EXPECTATION_EXPRESSION", "VALUE", "MEASUREMENT_TIME"
    ]].rename(columns={
        "SEVERITY":                 "Severity",
        "METRIC_NAME":              "Rule",
        "COLUMN_NAME":              "Column",
        "EXPECTATION_EXPRESSION":   "Pass Condition",
        "VALUE":             "Violation Count",
        "MEASUREMENT_TIME":  "Detected At",
    }).sort_values(
        by="Severity",
        key=lambda s: s.map({"HIGH": 0, "MEDIUM": 1, "LOW": 2})
    )

    st.dataframe(
        vgrid.style.map(color_severity, subset=["Severity"]),
        use_container_width=True,
        hide_index=True,
    )
else:
    st.success("No violations detected. All 9 rules are currently passing.")

st.divider()

# ── Section 3: Historical trend charts ────────────────────────────────────────
st.subheader(f"Historical Trends  ·  {hours_label}")

if not history_df.empty:
    col1, col2 = st.columns(2)

    # Left: violation metrics over time (everything except ROW_COUNT and FRESHNESS)
    violation_metrics = history_df[
        ~history_df["METRIC_NAME"].isin(["ROW_COUNT", "FRESHNESS"])
    ].copy()

    with col1:
        st.markdown("**Violation Metrics Over Time**")
        st.caption("NULL_COUNT, DUPLICATE_COUNT, ACCEPTED_VALUES, custom NPI + BIC checks")
        if not violation_metrics.empty:
            pivot = (
                violation_metrics
                .pivot_table(
                    index="MEASUREMENT_TIME",
                    columns="METRIC_LABEL",
                    values="VALUE",
                    aggfunc="last"
                )
                .reset_index()
                .set_index("MEASUREMENT_TIME")
            )
            st.line_chart(pivot, height=280)
        else:
            st.info("No history in this window yet.")

    # Right: member count (volume) trend
    with col2:
        st.markdown("**Member Count (Volume) Over Time**")
        st.caption("ROW_COUNT — total rows in SILVER.MEMBER per evaluation")
        if not rc_df.empty:
            rc_plot = rc_df[["MEASUREMENT_TIME", "VALUE"]].set_index("MEASUREMENT_TIME")
            rc_plot.columns = ["Member Count"]
            st.line_chart(rc_plot, height=280)
        else:
            st.info("No history in this window yet.")

    # Freshness trend (seconds since last SILVER_LOADED_AT)
    fresh_df = history_df[history_df["METRIC_NAME"] == "FRESHNESS"].copy()
    if not fresh_df.empty:
        st.markdown("**Data Freshness Over Time**")
        st.caption("FRESHNESS — seconds since the most recent SILVER_LOADED_AT value (threshold: < 86400s = 24h)")
        fresh_plot = fresh_df[["MEASUREMENT_TIME", "VALUE"]].set_index("MEASUREMENT_TIME")
        fresh_plot.columns = ["Seconds Since Last Load"]
        st.line_chart(fresh_plot, height=220)

else:
    st.info(
        "No measurement history in this window. "
        "Run INJECT_DIRTY_DATA() then CLEAN_DIRTY_DATA() a few times to seed trend data."
    )

st.divider()

# ── Section 4: Raw measurement log ────────────────────────────────────────────
with st.expander("Raw Measurement Log"):
    if not history_df.empty:
        log = history_df[["MEASUREMENT_TIME", "METRIC_NAME", "ARGUMENT_NAME", "VALUE"]].copy()
        log["MEASUREMENT_TIME"] = pd.to_datetime(log["MEASUREMENT_TIME"]).dt.strftime("%Y-%m-%d %H:%M:%S")
        st.dataframe(log.sort_values("MEASUREMENT_TIME", ascending=False), use_container_width=True, hide_index=True)
    else:
        st.info("No data in this window.")

st.caption(
    f"30s cache  ·  Database: {DB}  ·  "
    f"Rendered: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
)
