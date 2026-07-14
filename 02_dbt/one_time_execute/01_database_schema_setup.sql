-- =============================================================================
-- FILE: database_schema_setup.sql
-- PURPOSE: Pre-build all databases and schemas required by the caloptima_dw
--          dbt project before running snow dbt execute.
--
--          Snowflake-native dbt projects do NOT create databases or schemas
--          automatically — they must exist before the first dbt run.
--
-- RUN THIS ONCE as ACCOUNTADMIN before deploying the dbt project.
-- Safe to re-run — all statements use IF NOT EXISTS.
--
-- ENVIRONMENTS:
--   dev  → FACETS_DEV
--   qa   → FACETS_QA
--   prod → FACETS_PROD
--
-- SCHEMAS CREATED PER DATABASE (driven by dbt_project.yml +schema config):
--   STAGING   → staging/ models (views)
--   SILVER    → silver/ models (incremental tables)
--   GOLD      → gold/ models (views)
--   DQ        → ops/ models (tables — row counts, dup metrics)
--
-- NOTE: intermediate/ models are ephemeral — no schema needed.
-- NOTE: FACETS_BRONZE (Openflow landing zone) is managed by Openflow, not dbt.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WH_XS;

-- =============================================================================
-- DEV
-- =============================================================================

CREATE DATABASE IF NOT EXISTS FACETS_DEV;

CREATE SCHEMA IF NOT EXISTS FACETS_DEV.STAGING;
CREATE SCHEMA IF NOT EXISTS FACETS_DEV.SILVER;
CREATE SCHEMA IF NOT EXISTS FACETS_DEV.GOLD;
CREATE SCHEMA IF NOT EXISTS FACETS_DEV.DQ;

-- =============================================================================
-- QA
-- =============================================================================

CREATE DATABASE IF NOT EXISTS FACETS_QA;

CREATE SCHEMA IF NOT EXISTS FACETS_QA.STAGING;
CREATE SCHEMA IF NOT EXISTS FACETS_QA.SILVER;
CREATE SCHEMA IF NOT EXISTS FACETS_QA.GOLD;
CREATE SCHEMA IF NOT EXISTS FACETS_QA.DQ;

-- =============================================================================
-- PROD
-- =============================================================================

CREATE DATABASE IF NOT EXISTS FACETS_PROD;

CREATE SCHEMA IF NOT EXISTS FACETS_PROD.STAGING;
CREATE SCHEMA IF NOT EXISTS FACETS_PROD.SILVER;
CREATE SCHEMA IF NOT EXISTS FACETS_PROD.GOLD;
CREATE SCHEMA IF NOT EXISTS FACETS_PROD.DQ;

-- =============================================================================
-- dbt project host database (where the project object itself lives)
-- =============================================================================

CREATE DATABASE IF NOT EXISTS ANALYTICS_ADMIN;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_ADMIN.PROJECTS;

-- =============================================================================
-- VERIFICATION: Confirm all schemas exist across all environments
-- =============================================================================

SHOW SCHEMAS IN DATABASE FACETS_DEV;
SHOW SCHEMAS IN DATABASE FACETS_QA;
SHOW SCHEMAS IN DATABASE FACETS_PROD;
SHOW SCHEMAS IN DATABASE ANALYTICS_ADMIN;
