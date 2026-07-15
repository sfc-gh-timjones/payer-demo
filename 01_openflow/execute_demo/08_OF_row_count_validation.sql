
-- =============================================================================
-- Run the validation
-- =============================================================================
CALL FACETS_BRONZE.UTILS.FACETS_ROW_COUNT_VALIDATION(
    'tjonessqlserver.database.windows.net',
    'openflow'
);















































-- =============================================================================
-- FILE: 07_row_count_validation.sql
-- PURPOSE: Compare row counts between Azure SQL Server (source) and
--          Snowflake FACETS_BRONZE.RAW (destination) for all 35 CMC tables.
--          Returns a delta report showing replication parity.
-- =============================================================================

USE DATABASE FACETS_BRONZE;
USE SCHEMA   UTILS;

CREATE OR REPLACE PROCEDURE FACETS_ROW_COUNT_VALIDATION(
    SQL_SERVER_HOST STRING,
    SQL_SERVER_DB   STRING
)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
ARTIFACT_REPOSITORY = snowflake.snowpark.pypi_shared_repository
PACKAGES = ('snowflake-snowpark-python', 'python-tds', 'certifi')
EXTERNAL_ACCESS_INTEGRATIONS = (AZURE_SQL_FACETS_EAI)
SECRETS = ('facets_sql_creds' = FACETS_BRONZE.UTILS.FACETS_SQL_CREDS)
HANDLER = 'row_count_validation'
COMMENT = 'Compares Azure SQL vs Snowflake row counts for all 35 CMC Facets tables'
AS
$$
import pytds
import certifi

TABLES = [
    'CMC_NWNW_NETWORK', 'CMC_AGAG_AGREEMENT', 'CMC_CSCS_CLASS',
    'CMC_CSPI_CS_PLAN', 'CMC_PRPR_PROV', 'CMC_PRAD_ADDRESS',
    'CMC_PRER_RELATION', 'CMC_PRFA_FACILITY', 'CMC_PRAF_FAC_AFFIL',
    'CMC_NWPR_RELATION', 'CMC_PRCR_CREDEN', 'CMC_PRCF_CERT',
    'CMC_PRRG_REG', 'CMC_PRDS_DATE', 'CMC_PRCP_COMM_PRAC',
    'CMC_PRNP_NPI', 'CMC_PRLA_LANG', 'CMC_PRHI_HIST',
    'CMC_PROF_OFF_HRS', 'CMC_PRWM_PR_MSG', 'CMC_SBSB_SUBSC',
    'CMC_SBCS_CLASS', 'CMC_SBEL_ELIG_ENT', 'CMC_MEME_MEMBER',
    'CMC_MEDD_DEM_DATA', 'CMC_MECR_NO_XREF', 'CMC_MEPR_PRIM_PROV',
    'CMC_MECB_COB', 'CMC_MERP_RELATION', 'CMC_MEIA_ID_ACT',
    'CMC_MCTR_CD_TRANS', 'CMC_MEPE_PRCS_ELIG', 'CMC_MEES_EXCHANGE',
    'CMC_MECD_MEDICAID', 'CMC_MESU_SUBSIDY',
    'CMC_PRTP_PROV_TYPE',  # schema drift demo table — only present after demo Step 2
]


def row_count_validation(session, sql_server_host: str, sql_server_db: str) -> str:
    import _snowflake

    # ── 1. Azure SQL counts ──────────────────────────────────────────────────
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

    sql_counts = {}
    try:
        union_sql = '\nUNION ALL\n'.join(
            f"SELECT '{t}' AS table_name, COUNT(*) AS row_count FROM raw.{t}"
            for t in TABLES
        )
        cur.execute(union_sql)
        for row in cur.fetchall():
            sql_counts[row[0]] = row[1]
    finally:
        cur.close()
        conn.close()

    # ── 2. Snowflake counts (INFORMATION_SCHEMA for speed) ───────────────────
    # Snowflake: active rows only — Openflow soft-deletes with _snowflake_deleted
    sf_union = ' UNION ALL '.join(
        f"SELECT '{t}' AS table_name, COUNT(*) AS row_count "
        f"FROM FACETS_BRONZE.RAW.{t} WHERE _snowflake_deleted = FALSE"
        for t in TABLES
    )
    sf_rows = session.sql(sf_union).collect()
    sf_counts = {r['TABLE_NAME']: r['ROW_COUNT'] for r in sf_rows}

    # ── 3. Build delta report ─────────────────────────────────────────────────
    header = f"{'TABLE':<30}  {'SQL_SERVER':>10}  {'SNOWFLAKE':>10}  {'DELTA':>10}  STATUS"
    sep    = '-' * len(header)
    lines  = [header, sep]

    total_src = total_sf = 0
    has_gap = False

    for t in TABLES:
        src = sql_counts.get(t, 0)
        sf  = sf_counts.get(t, -1)
        delta = sf - src if sf >= 0 else None

        if sf < 0:
            sf_display = 'NOT FOUND'
            delta_display = 'N/A'
            status = '⚠ MISSING'
            has_gap = True
        elif delta == 0:
            sf_display = str(sf)
            delta_display = '0'
            status = '✓ IN SYNC'
        elif delta < 0:
            sf_display = str(sf)
            delta_display = str(delta)
            status = '✗ BEHIND'
            has_gap = True
        else:
            # Snowflake has more rows (e.g. duplicate injection)
            sf_display = str(sf)
            delta_display = f'+{delta}'
            status = '✓ AHEAD'

        total_src += src
        if sf >= 0:
            total_sf += sf

        lines.append(f"{t:<30}  {src:>10,}  {sf_display:>10}  {delta_display:>10}  {status}")

    lines.append(sep)
    lines.append(f"{'TOTAL':<30}  {total_src:>10,}  {total_sf:>10,}  {total_sf - total_src:>+10,}")
    lines.append('')
    lines.append('STATUS: ' + ('GAPS DETECTED — snapshot may still be in progress' if has_gap else 'ALL TABLES IN SYNC'))

    return '\n'.join(lines)
$$;

-- =============================================================================
-- Run the validation
-- =============================================================================
CALL FACETS_BRONZE.UTILS.FACETS_ROW_COUNT_VALIDATION(
    'tjonessqlserver.database.windows.net',
    'openflow'
);
