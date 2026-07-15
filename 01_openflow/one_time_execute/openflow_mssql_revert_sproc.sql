-- =============================================================================
-- FILE: openflow_mssql_revert_sproc.sql
-- PURPOSE: Deploy a Snowflake stored procedure that resets the Openflow schema
--          drift demo on Azure SQL Server (CMC_PRTP_PROV_TYPE table).
--
-- WHAT IT DOES (matches 01_OF_schema_revert_mssql.sql, but idempotent):
--   1. Restores PRTP_ID 7 description back to 'Skilled Nursing Facility'
--   2. Re-inserts PRTP_ID 2 (DO) — skipped if it already exists
--   3. Deletes demo rows PRTP_ID >= 9001
--   4. Drops PRTP_EFFECTIVE_DT column — skipped if already dropped
--   5. Narrows PRTP_DESC back to VARCHAR(100)
--
-- IDEMPOTENT: safe to call multiple times in a row without errors or duplicates.
--
-- DEPLOY ONCE, then call via one_time_pre_demo_snow.sql each demo session.
-- =============================================================================

USE DATABASE FACETS_BRONZE;
USE SCHEMA   UTILS;

CREATE OR REPLACE PROCEDURE FACETS_BRONZE.UTILS.OPENFLOW_SCHEMA_REVERT_MSSQL(
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
HANDLER = 'openflow_schema_revert'
AS
$$
import pytds
import certifi
import _snowflake


def openflow_schema_revert(session, sql_server_host: str, sql_server_db: str) -> str:
    log = []

    # Connect to Azure SQL Server
    try:
        creds = _snowflake.get_username_password('facets_sql_creds')
        conn = pytds.connect(
            server=sql_server_host,
            port=1433,
            database=sql_server_db,
            user=creds.username,
            password=creds.password,
            cafile=certifi.where(),
            validate_host=False,
            timeout=30,
            autocommit=True
        )
    except Exception as e:
        return f"FAILED\nstep=connect\nerror={e}"

    cur = conn.cursor()

    try:
        # Step 1: Restore PRTP_ID 7 description (idempotent — safe to run always)
        cur.execute(
            "UPDATE raw.CMC_PRTP_PROV_TYPE SET PRTP_DESC = 'Skilled Nursing Facility' WHERE PRTP_ID = 7"
        )
        log.append(f"update_prtp_id_7: {cur.rowcount} row(s) updated")

        # Step 2: Re-insert PRTP_ID 2 only if it does not already exist
        cur.execute("SELECT COUNT(1) FROM raw.CMC_PRTP_PROV_TYPE WHERE PRTP_ID = 2")
        if cur.fetchone()[0] == 0:
            cur.execute("""
                INSERT INTO raw.CMC_PRTP_PROV_TYPE
                    (PRTP_ID, PRTP_CODE, PRTP_DESC, PRTP_CATEGORY, PRTP_ACTIVE_FLAG, PRTP_SORT_ORDER)
                VALUES (2, 'DO', 'Doctor of Osteopathy', 'Physician', 'Y', 2)
            """)
            log.append("insert_prtp_id_2: inserted (was missing)")
        else:
            log.append("insert_prtp_id_2: skipped (already exists)")

        # Step 3: Delete demo rows 9001-9005 (idempotent — 0 rows if already deleted)
        cur.execute("DELETE FROM raw.CMC_PRTP_PROV_TYPE WHERE PRTP_ID >= 9001")
        log.append(f"delete_demo_rows: {cur.rowcount} row(s) deleted")

        # Step 4a: Drop PRTP_EFFECTIVE_DT only if the column currently exists
        cur.execute("""
            SELECT COUNT(1) FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = 'raw'
              AND TABLE_NAME   = 'CMC_PRTP_PROV_TYPE'
              AND COLUMN_NAME  = 'PRTP_EFFECTIVE_DT'
        """)
        if cur.fetchone()[0] > 0:
            cur.execute("ALTER TABLE raw.CMC_PRTP_PROV_TYPE DROP COLUMN PRTP_EFFECTIVE_DT")
            log.append("drop_column_PRTP_EFFECTIVE_DT: dropped")
        else:
            log.append("drop_column_PRTP_EFFECTIVE_DT: skipped (column does not exist)")

        # Step 4b: Narrow PRTP_DESC back to VARCHAR(100) (idempotent)
        cur.execute("ALTER TABLE raw.CMC_PRTP_PROV_TYPE ALTER COLUMN PRTP_DESC VARCHAR(100)")
        log.append("alter_column_PRTP_DESC: set to VARCHAR(100)")

        # Step 5: Final row count — expect 15 (seeded rows, PRTP_ID 1-15)
        cur.execute("SELECT COUNT(*) FROM raw.CMC_PRTP_PROV_TYPE")
        total = cur.fetchone()[0]
        log.append(f"final_row_count: {total} (expect 15)")

    except Exception as e:
        log.append(f"FAILED\nerror={e}")
    finally:
        cur.close()
        conn.close()

    return "REVERT COMPLETE\n" + "\n".join(log)
$$;

-- =============================================================================
-- Deploy verification — run after CREATE OR REPLACE above
-- =============================================================================
CALL FACETS_BRONZE.UTILS.OPENFLOW_SCHEMA_REVERT_MSSQL(
    'tjonessqlserver.database.windows.net',
    'openflow'
);
