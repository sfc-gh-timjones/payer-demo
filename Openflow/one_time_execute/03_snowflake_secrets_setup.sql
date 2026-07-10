-- =============================================================================
-- FILE: 03_snowflake_secrets_setup.sql
-- PURPOSE: Create FACETS_BRONZE database, UTILS schema, credentials secret,
--          network rule, and External Access Integration for the Facets demo.
--
-- RUN ONCE as ACCOUNTADMIN (requires CREATE DATABASE, CREATE SECRET,
--   CREATE NETWORK RULE, CREATE INTEGRATION privileges).
-- Fill in your actual password and hostname before running.
--
-- RUN ORDER:
--   1. 01_sql_server_ddl.sql         — create tables in Azure SQL Server
--   2. 02_sql_server_permissions.sql — change tracking + openflow_user grants
--   3. THIS FILE                     — database, schema, secret, network rule, EAI
--   4. 04_initial_load_deploy.sql    — initial load procedure + call once
--   5. 05_incremental_load_deploy.sql — incremental proc + scheduled task
-- =============================================================================

-- Database and UTILS schema (sproc home; Openflow will create the RAW schema)
CREATE DATABASE IF NOT EXISTS FACETS_BRONZE;
CREATE SCHEMA  IF NOT EXISTS FACETS_BRONZE.UTILS;

USE DATABASE FACETS_BRONZE;
USE SCHEMA   UTILS;

-- =============================================================================
-- Secret: SQL Server credentials for openflow_user
-- The stored procedures read this at runtime — the password never appears
-- in TASK definitions, CALL statements, or QUERY_HISTORY.
-- =============================================================================
CREATE OR REPLACE SECRET FACETS_SQL_CREDS
    TYPE     = PASSWORD
    USERNAME = 'tjones'
    PASSWORD = '<REPLACE_WITH_OPENFLOW_USER_PASSWORD>'
    COMMENT  = 'openflow_user credentials for Facets Azure SQL Server';

-- =============================================================================
-- Network Rule: allows outbound TCP to Azure SQL Server on port 1433
-- =============================================================================
CREATE OR REPLACE NETWORK RULE AZURE_SQL_NETWORK_RULE
    MODE       = EGRESS
    TYPE       = HOST_PORT
    VALUE_LIST = ('tjonessqlserver.database.windows.net:1433')
    COMMENT    = 'Egress rule for Facets Azure SQL Server';

-- =============================================================================
-- External Access Integration: shared by both initial and incremental sprocs
-- Must exist before either CREATE PROCEDURE is run.
-- =============================================================================
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION AZURE_SQL_FACETS_EAI
    ALLOWED_NETWORK_RULES          = (FACETS_BRONZE.UTILS.AZURE_SQL_NETWORK_RULE)
    ALLOWED_AUTHENTICATION_SECRETS = (FACETS_BRONZE.UTILS.FACETS_SQL_CREDS)
    ENABLED = TRUE
    COMMENT = 'Allows Facets demo stored procedures to connect to Azure SQL Server';

-- =============================================================================
-- App Config: key/value table read by the Openflow Observability Streamlit app
-- Add one row per SQL Server instance so the app knows which host/db to validate.
-- The Streamlit app reads these as defaults — the user can override them in the UI.
-- =============================================================================
CREATE TABLE IF NOT EXISTS FACETS_BRONZE.UTILS.APP_CONFIG (
    key     VARCHAR NOT NULL,
    value   VARCHAR NOT NULL,
    comment VARCHAR
);

-- Set your SQL Server hostname and database here.
-- Re-run this block when deploying to a new Snowflake account.
MERGE INTO FACETS_BRONZE.UTILS.APP_CONFIG AS t
USING (
    SELECT * FROM VALUES
        ('SQL_SERVER_HOST', 'tjonessqlserver.database.windows.net', 'Azure SQL Server hostname for row count validation'),
        ('SQL_SERVER_DB',   'openflow',                             'Azure SQL Server database for row count validation')
    AS v(key, value, comment)
) AS s ON t.key = s.key
WHEN MATCHED     THEN UPDATE SET t.value = s.value, t.comment = s.comment
WHEN NOT MATCHED THEN INSERT (key, value, comment) VALUES (s.key, s.value, s.comment);

SELECT * FROM FACETS_BRONZE.UTILS.APP_CONFIG;

-- =============================================================================
-- Verify
-- =============================================================================
DESCRIBE SECRET           FACETS_SQL_CREDS;
DESCRIBE NETWORK RULE     AZURE_SQL_NETWORK_RULE;
DESCRIBE INTEGRATION      AZURE_SQL_FACETS_EAI;
