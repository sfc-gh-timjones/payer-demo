-- =============================================================================
-- FILE: openflow_mssql_schema_change_sproc.sql
-- PURPOSE: Deploy a Snowflake stored procedure that applies the Openflow schema
--          drift demo changes to Azure SQL Server (CMC_PRTP_PROV_TYPE table).
--
-- WHAT IT DOES (matches 02_OF_schema_change_mssql.sql, but idempotent):
--   1. Expands PRTP_DESC from VARCHAR(100) to VARCHAR(200)
--   2. Adds PRTP_EFFECTIVE_DT DATE column — skipped if already exists
--   3. Inserts demo rows PRTP_ID 9001-9005 — skipped individually if already present
--   4. Updates PRTP_ID 7 description to 'Skilled Nursing & Rehabilitation Facility'
--   5. Deletes PRTP_ID 2 (DO) — skipped if already deleted
--
-- IDEMPOTENT: safe to call multiple times in a row without errors or duplicates.
--
-- DEPLOY ONCE, then call via 02_OF_schema_change_mssql.sql (Snowflake side) each demo session.
-- =============================================================================

USE DATABASE FACETS_BRONZE;
USE SCHEMA   UTILS;

CREATE OR REPLACE PROCEDURE FACETS_BRONZE.UTILS.OPENFLOW_SCHEMA_CHANGE_MSSQL(
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
HANDLER = 'openflow_schema_change'
AS
$$
import pytds
import certifi
import _snowflake


def openflow_schema_change(session, sql_server_host: str, sql_server_db: str) -> str:
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
        # Step 1: Expand PRTP_DESC to VARCHAR(200) (idempotent — safe to run always)
        cur.execute("ALTER TABLE raw.CMC_PRTP_PROV_TYPE ALTER COLUMN PRTP_DESC VARCHAR(200)")
        log.append("alter_column_PRTP_DESC: set to VARCHAR(200)")

        # Step 2: Add PRTP_EFFECTIVE_DT column only if it does not already exist
        cur.execute("""
            SELECT COUNT(1) FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = 'raw'
              AND TABLE_NAME   = 'CMC_PRTP_PROV_TYPE'
              AND COLUMN_NAME  = 'PRTP_EFFECTIVE_DT'
        """)
        if cur.fetchone()[0] == 0:
            cur.execute("ALTER TABLE raw.CMC_PRTP_PROV_TYPE ADD PRTP_EFFECTIVE_DT DATE NULL")
            log.append("add_column_PRTP_EFFECTIVE_DT: added")
        else:
            log.append("add_column_PRTP_EFFECTIVE_DT: skipped (already exists)")

        # Step 3: Insert demo rows 9001-9005 — skip any that already exist
        demo_rows = [
            (9001, 'ACUP', 'Acupuncturist',           'Ancillary',     'Y', 16, '2024-01-01'),
            (9002, 'CHIR', 'Chiropractor',            'Ancillary',     'Y', 17, '2024-01-01'),
            (9003, 'POD',  'Podiatrist',              'Physician',     'Y', 18, '2024-01-01'),
            (9004, 'OPT',  'Optometrist',             'Dental/Vision', 'Y', 19, '2024-01-01'),
            (9005, 'MTL',  'Mental Health Counselor', 'Behavioral',    'Y', 20, '2024-01-01'),
        ]
        inserted = 0
        skipped  = 0
        for row in demo_rows:
            cur.execute("SELECT COUNT(1) FROM raw.CMC_PRTP_PROV_TYPE WHERE PRTP_ID = %d" % row[0])
            if cur.fetchone()[0] == 0:
                cur.execute("""
                    INSERT INTO raw.CMC_PRTP_PROV_TYPE
                        (PRTP_ID, PRTP_CODE, PRTP_DESC, PRTP_CATEGORY, PRTP_ACTIVE_FLAG, PRTP_SORT_ORDER, PRTP_EFFECTIVE_DT)
                    VALUES (%d, '%s', '%s', '%s', '%s', %d, '%s')
                """ % row)
                inserted += 1
            else:
                skipped += 1
        log.append(f"insert_demo_rows_9001_9005: {inserted} inserted, {skipped} skipped (already present)")

        # Step 4: Update PRTP_ID 7 description (idempotent — safe to run always)
        cur.execute(
            "UPDATE raw.CMC_PRTP_PROV_TYPE "
            "SET PRTP_DESC = 'Skilled Nursing & Rehabilitation Facility' "
            "WHERE PRTP_ID = 7"
        )
        log.append(f"update_prtp_id_7: {cur.rowcount} row(s) updated")

        # Step 5: Delete PRTP_ID 2 only if it still exists
        cur.execute("SELECT COUNT(1) FROM raw.CMC_PRTP_PROV_TYPE WHERE PRTP_ID = 2")
        if cur.fetchone()[0] > 0:
            cur.execute("DELETE FROM raw.CMC_PRTP_PROV_TYPE WHERE PRTP_ID = 2")
            log.append("delete_prtp_id_2: deleted")
        else:
            log.append("delete_prtp_id_2: skipped (already deleted)")

        # Final row count — expect 19 (20 seeded - 1 delete + 5 inserts - 1 deleted)
        cur.execute("SELECT COUNT(*) FROM raw.CMC_PRTP_PROV_TYPE")
        total = cur.fetchone()[0]
        log.append(f"final_row_count: {total} (expect 19)")

    except Exception as e:
        log.append(f"FAILED\nerror={e}")
    finally:
        cur.close()
        conn.close()

    return "SCHEMA CHANGE COMPLETE\n" + "\n".join(log)
$$;

-- =============================================================================
-- Deploy verification — run after CREATE OR REPLACE above
-- =============================================================================
CALL FACETS_BRONZE.UTILS.OPENFLOW_SCHEMA_CHANGE_MSSQL(
    'tjonessqlserver.database.windows.net',
    'openflow'
);
