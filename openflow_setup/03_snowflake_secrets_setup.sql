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
-- Verify
-- =============================================================================
DESCRIBE SECRET           FACETS_SQL_CREDS;
DESCRIBE NETWORK RULE     AZURE_SQL_NETWORK_RULE;
DESCRIBE INTEGRATION      AZURE_SQL_FACETS_EAI;
