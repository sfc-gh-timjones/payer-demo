-- =============================================================================
-- FILE: 06_azure_sql_connection_test.sql
-- PURPOSE: Test connectivity from Snowflake to Azure SQL via pytds (pure Python TDS).
--          pytds uses Python's built-in ssl module — bypasses FreeTDS entirely.
-- =============================================================================

USE DATABASE FACETS_BRONZE;
USE SCHEMA   UTILS;

CREATE OR REPLACE PROCEDURE FACETS_AZURE_SQL_CONNECTION_TEST(
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
HANDLER = 'connection_test'
AS
$$
import pytds
import certifi
import _snowflake


def connection_test(session, sql_server_host: str, sql_server_db: str) -> str:
    lines = [f"host={sql_server_host}", f"database={sql_server_db}"]

    # 1. Read credentials from Snowflake secret
    try:
        creds = _snowflake.get_username_password('facets_sql_creds')
        lines.append(f"secret=OK (user={creds.username})")
    except Exception as e:
        return "FAILED\nstep=read_secret\n" + str(e)

    # 2. Connect — pytds uses Python ssl, not FreeTDS
    conn, cur = None, None
    try:
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
        lines.append("connect=OK")
    except Exception as e:
        return "FAILED\nstep=connect\n" + "\n".join(lines) + f"\nerror={e}"

    # 3. Smoke test query
    try:
        cur = conn.cursor()
        cur.execute("SELECT @@VERSION")
        version = cur.fetchone()[0]
        lines.append(f"version={version[:120]}")
        lines.append("\nCONNECTION TEST PASSED")
        return "\n".join(lines)
    except Exception as e:
        return "FAILED\nstep=query\n" + "\n".join(lines) + f"\nerror={e}"
    finally:
        if cur:  cur.close()
        if conn: conn.close()
$$;

-- =============================================================================
-- Run the test
-- =============================================================================
CALL FACETS_AZURE_SQL_CONNECTION_TEST(
    'tjonessqlserver.database.windows.net',
    'openflow'
);
