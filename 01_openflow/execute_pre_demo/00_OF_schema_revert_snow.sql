-- =============================================================================
-- FILE: 06.4_schema_revert_snow.sql
-- PURPOSE: Reset CMC_PRTP_PROV_TYPE in Snowflake after the schema drift demo.
--          Dropping the Bronze table reverts all three change types at once:
--            • 5 new rows (PRTP_ID 9001-9005) with PRTP_EFFECTIVE_DT
--            • Updated row (PRTP_ID 7: description change)
--            • Soft-deleted row (PRTP_ID 2: _SNOWFLAKE_DELETED = TRUE)
--          After drop, re-adding to Openflow triggers a clean full reload.
--
-- WORKFLOW:
-- SNOWFLAKE FIRST
-- 1. REMOVE FROM OPENFLOW REPLICATION
-- 2. RUN BELOW SCRIPT

-- THEN 

--SQL SERVER
-- Run revert script in mssql. 
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- =============================================================================
-- STEP 1: Drop all CMC_PRTP_PROV_TYPE journal tables (suffix is a timestamp ID
--         so we can't hardcode — multiple may exist if previous runs weren't
--         cleaned up).  Python proc handles 0, 1, or N tables safely.
-- =============================================================================

CREATE OR REPLACE PROCEDURE FACETS_BRONZE.UTILS.DROP_PRTP_JOURNAL_TABLES()
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS $$
def run(session):
    rows = session.sql("""
        SELECT TABLE_NAME
        FROM FACETS_BRONZE.INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA = 'RAW'
          AND TABLE_NAME ILIKE 'CMC_PRTP_PROV_TYPE%JOURNAL%'
    """).collect()
    if not rows:
        return 'No PRTP journal tables found — nothing to drop.'
    dropped = []
    for row in rows:
        name = row['TABLE_NAME']
        session.sql(f'DROP TABLE IF EXISTS FACETS_BRONZE.RAW.{name}').collect()
        dropped.append(name)
    return 'Dropped: ' + ', '.join(dropped)
$$;

CALL FACETS_BRONZE.UTILS.DROP_PRTP_JOURNAL_TABLES();

-- =============================================================================
-- STEP 2: Drop the main Bronze table so Openflow re-onboards clean
--         (removes PRTP_EFFECTIVE_DT column history + all DML changes)
-- =============================================================================

DROP TABLE IF EXISTS FACETS_BRONZE.RAW.CMC_PRTP_PROV_TYPE;

-- Confirm both are gone
SHOW TABLES LIKE 'CMC_PRTP_PROV_TYPE%' IN SCHEMA FACETS_BRONZE.RAW;